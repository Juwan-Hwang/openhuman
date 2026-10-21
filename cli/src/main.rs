//! oh-seat — sit in the OpenHuman responder seat from any terminal.
//!
//! Built for AI agents that drive a shell one command at a time:
//! one command = one complete step, short structured output, state kept in
//! a file (never in the agent's head), every blocking call bounded by a
//! timeout the agent picks. See docs/seat-cli.md.

use clap::{Args, Parser, Subcommand};
use serde_json::{json, Map, Value};
use std::collections::BTreeMap;
use std::io::Read;
use std::path::PathBuf;
use std::process::ExitCode;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

// stdout closed early (`| head`): stop quietly instead of panicking.
macro_rules! println {
    ($($t:tt)*) => {{
        use std::io::Write as _;
        if writeln!(std::io::stdout(), $($t)*).is_err() {
            std::process::exit(0)
        }
    }};
}

const POLL_MAX: u64 = 85; // server caps a long-poll at 90 s
const UA: &str = concat!("oh-seat/", env!("CARGO_PKG_VERSION"));

// ── exit codes ──
const OK: u8 = 0;
const NOTHING: u8 = 2; // timed out with nothing new
const HTTP: u8 = 3; // network / auth / server error
const USAGE: u8 = 4;

#[derive(Parser)]
#[command(
    name = "oh-seat",
    version,
    about = "OpenHuman Agent Seat: answer callers (Claude Code, Codex, ...) and run tools on their side",
    after_help = "Typical loop:\n  oh-seat next                         # wait for a message\n  oh-seat tool bash command='ls -la'   # caller runs it, you get the output\n  oh-seat reply 'Done.' --next         # answer, then wait for the next message\n\nExit codes: 0 ok, 2 nothing new before --timeout, 3 network/auth/server error, 4 usage error."
)]
struct Cli {
    #[command(flatten)]
    g: Global,
    #[command(subcommand)]
    cmd: Cmd,
}

#[derive(Args)]
struct Global {
    /// Server base URL
    #[arg(
        long,
        env = "OH_SEAT_URL",
        default_value = "https://api.juwanh.com",
        global = true
    )]
    url: String,
    /// Responder API key (prefer OH_SEAT_KEY_FILE so it stays out of your history)
    #[arg(long, env = "OH_SEAT_KEY", hide_env_values = true, global = true)]
    key: Option<String>,
    /// File holding the key (a bare ohk_... or an `api_key=ohk_...` line). Default ~/.openhuman/seat_key
    #[arg(long, env = "OH_SEAT_KEY_FILE", global = true)]
    key_file: Option<PathBuf>,
    /// State file (cursor, active conversation, buffered events). Default ~/.openhuman/seat-state.json
    #[arg(long, env = "OH_SEAT_STATE", global = true)]
    state: Option<PathBuf>,
    /// One JSON object per line instead of text
    #[arg(long, global = true)]
    json: bool,
}

#[derive(Subcommand)]
enum Cmd {
    /// Wait until a caller message needs an answer, then print it (and make it the active conversation)
    Next {
        /// Give up after this many seconds (exit 2). Keep it under your shell's command timeout.
        #[arg(long, default_value_t = 100)]
        timeout: u64,
        /// Return on any event, not only messages
        #[arg(long)]
        all: bool,
    },
    /// Reply in a conversation. TEXT may be `-` (or omitted) to read stdin
    Reply {
        text: Option<String>,
        /// Read the reply from a file (no shell quoting problems)
        #[arg(long, short = 'f')]
        file: Option<PathBuf>,
        #[arg(long, short = 'c')]
        conv: Option<String>,
        /// Thinking shown before the reply (reasoning_content)
        #[arg(long, short = 'r')]
        reasoning: Option<String>,
        /// Keep the turn open for another reply
        #[arg(long)]
        more: bool,
        /// After replying, wait for the next message (same as running `next`)
        #[arg(long)]
        next: bool,
        /// Timeout for --next
        #[arg(long, default_value_t = 100)]
        timeout: u64,
    },
    /// Ask the caller to run one of its tools; waits for and prints the result.
    ///
    /// Input: one JSON object, or key=value pairs (value parsed as JSON when it is valid JSON,
    /// else taken as a string; key=@path reads a file; key:=value forces a string).
    Tool {
        name: String,
        input: Vec<String>,
        #[arg(long, short = 'c')]
        conv: Option<String>,
        /// Words shown alongside the call
        #[arg(long)]
        text: Option<String>,
        #[arg(long, short = 'r')]
        reasoning: Option<String>,
        /// Wait at most this long for the result; if it is not back, fetch it later with `oh-seat result ID`
        #[arg(long, default_value_t = 100)]
        timeout: u64,
    },
    /// Wait for the result of an earlier tool call
    Result {
        invocation_id: String,
        #[arg(long, default_value_t = 100)]
        timeout: u64,
    },
    /// The caller's tools and system prompt for a conversation
    Caps {
        #[arg(long, short = 'c')]
        conv: Option<String>,
        /// Print the whole system prompt and every tool schema
        #[arg(long)]
        full: bool,
        /// Only what changed since the last `caps` of this conversation
        #[arg(long)]
        diff: bool,
        /// One tool: signature and what each parameter means
        #[arg(long)]
        tool: Option<String>,
        /// With --tool: the raw JSON schema instead
        #[arg(long)]
        schema: bool,
    },
    /// Recent messages of a conversation
    History {
        #[arg(long, short = 'c')]
        conv: Option<String>,
        #[arg(long, default_value_t = 20)]
        limit: usize,
    },
    /// Conversations this seat has seen, newest first (* = active)
    Convs,
    /// Make a conversation the active one
    Use { conv: String },
    /// Persist a conversation on the server (messages are in memory by default)
    Save {
        #[arg(long, short = 'c')]
        conv: Option<String>,
    },
    /// Show URL, consumer, cursor, active conversation, open turns
    Status,
}

// ── errors ──

#[derive(Debug)]
struct Fail(u8, String);
type R<T> = Result<T, Fail>;
fn usage<T>(m: impl Into<String>) -> R<T> {
    Err(Fail(USAGE, m.into()))
}

// ── state ──

#[derive(Default, serde::Serialize, serde::Deserialize)]
struct State {
    #[serde(default)]
    cursor: u64,
    #[serde(default)]
    consumer: String,
    #[serde(default)]
    active: Option<String>,
    /// Events read from the server but not yet handed to the agent.
    #[serde(default)]
    buffer: Vec<Value>,
    #[serde(default)]
    convs: BTreeMap<String, ConvInfo>,
    /// Last `caps` text per conversation, for --diff.
    #[serde(default)]
    caps: BTreeMap<String, String>,
}

#[derive(Default, Clone, serde::Serialize, serde::Deserialize)]
struct ConvInfo {
    #[serde(default)]
    client: Option<String>,
    #[serde(default)]
    last: String,
    #[serde(default)]
    t: u64,
}

fn home() -> PathBuf {
    std::env::var_os("HOME")
        .or_else(|| std::env::var_os("USERPROFILE"))
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("."))
}

fn now_secs() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

fn rand_hex(n: usize) -> String {
    let mut x = (SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or(1) as u64)
        ^ (std::process::id() as u64).rotate_left(32);
    let mut s = String::new();
    while s.len() < n {
        x ^= x << 13;
        x ^= x >> 7;
        x ^= x << 17;
        s.push_str(&format!("{:016x}", x));
    }
    s.truncate(n);
    s
}

struct Ctx {
    url: String,
    key: String,
    state_path: PathBuf,
    st: State,
    json: bool,
    agent: ureq::Agent,
}

impl Ctx {
    fn new(g: Global) -> R<Ctx> {
        let key = match g.key.filter(|k| !k.trim().is_empty()) {
            Some(k) => k.trim().to_string(),
            None => {
                let path = g
                    .key_file
                    .unwrap_or_else(|| home().join(".openhuman").join("seat_key"));
                let txt = std::fs::read_to_string(&path).map_err(|e| {
                    Fail(
                        USAGE,
                        format!(
                            "no key: set OH_SEAT_KEY or OH_SEAT_KEY_FILE ({}: {e})",
                            path.display()
                        ),
                    )
                })?;
                txt.lines()
                    .map(|l| l.trim().trim_start_matches("api_key=").to_string())
                    .find(|l| l.starts_with("ohk_"))
                    .ok_or_else(|| {
                        Fail(USAGE, format!("no ohk_ key found in {}", path.display()))
                    })?
            }
        };
        let state_path = g
            .state
            .unwrap_or_else(|| home().join(".openhuman").join("seat-state.json"));
        let mut st: State = std::fs::read_to_string(&state_path)
            .ok()
            .and_then(|s| serde_json::from_str(&s).ok())
            .unwrap_or_default();
        if st.consumer.is_empty() {
            st.consumer = std::env::var("OH_SEAT_CONSUMER")
                .unwrap_or_else(|_| format!("oh-seat-{}", rand_hex(8)));
        }
        let agent = ureq::AgentBuilder::new()
            .timeout_connect(Duration::from_secs(15))
            .user_agent(UA)
            .build();
        Ok(Ctx {
            url: g.url.trim_end_matches('/').to_string(),
            key,
            state_path,
            st,
            json: g.json,
            agent,
        })
    }

    fn save(&self) {
        if let Some(dir) = self.state_path.parent() {
            let _ = std::fs::create_dir_all(dir);
        }
        let tmp = self.state_path.with_extension("tmp");
        if let Ok(s) = serde_json::to_string(&self.st) {
            if std::fs::write(&tmp, s).is_ok() {
                let _ = std::fs::rename(&tmp, &self.state_path);
            }
        }
    }

    fn call(&self, method: &str, path: &str, body: Option<Value>, timeout: u64) -> R<Value> {
        let req = self
            .agent
            .request(method, &format!("{}{}", self.url, path))
            .timeout(Duration::from_secs(timeout))
            .set("Authorization", &format!("Bearer {}", self.key));
        let res = match body {
            Some(b) => req.send_json(b),
            None => req.call(),
        };
        let short = path.split('?').next().unwrap_or(path);
        match res {
            Ok(r) => {
                let txt = r.into_string().unwrap_or_default();
                if txt.trim().is_empty() {
                    Ok(json!({}))
                } else {
                    serde_json::from_str(&txt)
                        .map_err(|e| Fail(HTTP, format!("{short}: bad JSON from server: {e}")))
                }
            }
            Err(ureq::Error::Status(code, r)) => {
                let body = r.into_string().unwrap_or_default();
                let msg = serde_json::from_str::<Value>(&body)
                    .ok()
                    .and_then(|v| {
                        v.pointer("/error/message")
                            .and_then(|m| m.as_str())
                            .map(String::from)
                    })
                    .unwrap_or_else(|| body.chars().take(400).collect());
                let hint = match code {
                    401 => " (key missing, wrong or revoked)",
                    403 => " (this key may not sit in the seat: it needs scope responder or both)",
                    _ => "",
                };
                Err(Fail(HTTP, format!("HTTP {code} {short}: {msg}{hint}")))
            }
            Err(e) => Err(Fail(HTTP, format!("{short}: {e}"))),
        }
    }

    /// One long-poll; buffers new events and advances the cursor.
    ///
    /// Returns the server's `waiting_turns`. If the server's `latest` is
    /// below our cursor the seat was re-created (idle reclaim or restart) and
    /// its cursors started over: reset and read again at once, otherwise
    /// every new event would sit below our cursor and never be returned.
    fn poll(&mut self, wait: u64) -> R<Value> {
        let wait = wait.min(POLL_MAX);
        let mut r = self.inbox(self.st.cursor, wait)?;
        let latest = r.get("latest").and_then(|v| v.as_u64());
        if matches!(latest, Some(l) if l < self.st.cursor) {
            self.st.cursor = 0;
            r = self.inbox(0, 0)?;
        }
        if let Some(c) = r.get("cursor").and_then(|v| v.as_u64()) {
            self.st.cursor = c;
        }
        for e in r
            .get("events")
            .and_then(|v| v.as_array())
            .cloned()
            .unwrap_or_default()
        {
            self.note(&e);
            self.st.buffer.push(e);
        }
        if self.st.buffer.len() > 500 {
            let cut = self.st.buffer.len() - 500;
            self.st.buffer.drain(..cut);
        }
        self.save(); // buffer persisted together with the advanced cursor
        Ok(r.get("waiting_turns").cloned().unwrap_or(json!([])))
    }

    fn inbox(&self, after: u64, wait: u64) -> R<Value> {
        let path = format!(
            "/v1/seat/inbox?after={}&wait={}&consumer={}",
            after,
            wait,
            enc(&self.st.consumer)
        );
        self.call("GET", &path, None, wait + 30)
    }

    fn note(&mut self, e: &Value) {
        let Some(c) = conv_id(e) else { return };
        let info = self.st.convs.entry(c.to_string()).or_default();
        if let Some(cl) = s(e, "client") {
            info.client = Some(cl.to_string());
        }
        if s(e, "type") == Some("message.received") {
            info.last = s(e, "text").unwrap_or("").chars().take(100).collect();
            info.t = now_secs();
        }
        if self.st.convs.len() > 50 {
            let mut v: Vec<_> = self
                .st
                .convs
                .iter()
                .map(|(k, i)| (i.t, k.clone()))
                .collect();
            v.sort();
            for (_, k) in v.into_iter().take(self.st.convs.len() - 50) {
                self.st.convs.remove(&k);
                self.st.caps.remove(&k);
            }
        }
    }

    fn conv(&self, c: Option<String>) -> R<String> {
        c.or_else(|| self.st.active.clone()).ok_or_else(|| {
            Fail(
                USAGE,
                "no conversation: pass -c CONV or run `oh-seat next` first".into(),
            )
        })
    }

    fn out(&self, v: &Value) {
        println!("{}", serde_json::to_string(v).unwrap_or_default());
    }
}

fn enc(x: &str) -> String {
    x.bytes()
        .map(|b| match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => {
                (b as char).to_string()
            }
            _ => format!("%{:02X}", b),
        })
        .collect()
}

fn s<'a>(e: &'a Value, k: &str) -> Option<&'a str> {
    e.get(k).and_then(|v| v.as_str()).filter(|v| !v.is_empty())
}

fn conv_id(e: &Value) -> Option<&str> {
    s(e, "conversation_id").filter(|c| c.starts_with("cnv_"))
}

// ── rendering ──

fn aux_hint(e: &Value) -> Option<String> {
    if let Some(f) = s(e, "expected_format") {
        return Some(format!("answer with {f}"));
    }
    let kind = s(e, "kind");
    let text = s(e, "text").unwrap_or("").to_lowercase();
    let head = s(e, "system_prompt_head").unwrap_or("").to_lowercase();
    let hay = format!("{head}\n{text}");
    let guess = if hay.contains("no_suggestion") {
        Some("suggestion lines, or exactly NO_SUGGESTION")
    } else if hay.contains("\"suggestions\"") {
        Some("JSON {\"suggestions\": [...]} (empty list when none)")
    } else if hay.contains("title") && hay.contains("\"title\"") {
        Some("JSON {\"title\": \"...\"}")
    } else if (hay.contains("title") && kind == Some("auxiliary"))
        || text.starts_with("generate a title")
    {
        Some("only a short title, no quotes or extra text")
    } else {
        None
    };
    match (guess, kind) {
        (Some(g), _) => Some(format!("answer with {g}")),
        (None, Some("auxiliary")) => Some(
            "auxiliary call: answer exactly in the format its prompt asks (oh-seat caps --full)"
                .into(),
        ),
        _ => None,
    }
}

fn max_output() -> usize {
    std::env::var("OH_SEAT_MAX_OUTPUT")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(30000)
}

/// Long tool output is cut so it does not flood the agent's context; the
/// whole of it is kept in a file the agent can read or grep.
fn cap_output(body: String, id: &str) -> String {
    let max = max_output();
    let n = body.chars().count();
    if n <= max {
        return body;
    }
    let dir = home().join(".openhuman").join("results");
    let _ = std::fs::create_dir_all(&dir);
    let path = dir.join(format!("{}.txt", id.replace(['/', '\\', '.'], "_")));
    let saved = std::fs::write(&path, &body).is_ok();
    let head: String = body.chars().take(max * 2 / 3).collect();
    let tail: String = body.chars().skip(n - max / 3).collect();
    let note = if saved {
        format!("full output: {}", path.display())
    } else {
        "full output could not be saved".into()
    };
    format!(
        "{head}\n[... {} of {n} chars cut; {note} ...]\n{tail}",
        n - head.chars().count() - tail.chars().count()
    )
}

fn print_event(e: &Value) {
    let c = conv_id(e).unwrap_or("-");
    match s(e, "type").unwrap_or("event") {
        "message.received" => {
            let mut h = format!("MESSAGE conv={c} client={}", s(e, "client").unwrap_or("?"));
            if let Some(a) = aux_hint(e) {
                h.push_str(&format!("  AUX: {a}; reply with -c {c}"));
            }
            println!("{h}");
            println!("{}", s(e, "text").unwrap_or(""));
            if let Some(n) = e
                .get("image_count")
                .and_then(|v| v.as_u64())
                .or_else(|| {
                    e.get("images")
                        .and_then(|v| v.as_array())
                        .map(|a| a.len() as u64)
                })
                .filter(|n| *n > 0)
            {
                println!("[{n} image(s) attached: oh-seat history -c {c}]");
            }
        }
        "conversation.started" => println!("NEW CONVERSATION conv={c}"),
        "tool.result" => {
            println!(
                "TOOL RESULT {} status={} id={}",
                s(e, "tool_id").unwrap_or("?"),
                s(e, "status").unwrap_or("?"),
                s(e, "invocation_id").unwrap_or("?")
            );
            let body = s(e, "output")
                .map(String::from)
                .or_else(|| {
                    e.get("error").filter(|v| !v.is_null()).map(|v| {
                        v.as_str()
                            .map(String::from)
                            .unwrap_or_else(|| v.to_string())
                    })
                })
                .unwrap_or_default();
            println!(
                "{}",
                cap_output(body, s(e, "invocation_id").unwrap_or("result"))
            );
        }
        t => {
            let mut rest = e.as_object().cloned().unwrap_or_default();
            for k in ["type", "conversation_id", "cursor"] {
                rest.remove(k);
            }
            let txt: String = Value::Object(rest).to_string().chars().take(300).collect();
            println!("{} conv={c} {txt}", t.to_uppercase());
        }
    }
}

// ── tool input ──

fn parse_input(args: &[String]) -> R<Value> {
    if args.is_empty() {
        return Ok(json!({}));
    }
    if args.len() == 1 && args[0] == "-" {
        let mut b = String::new();
        std::io::stdin()
            .read_to_string(&mut b)
            .or_else(|e| usage(format!("stdin: {e}")))?;
        let lines: Vec<String> = b
            .lines()
            .filter(|l| !l.trim().is_empty())
            .map(String::from)
            .collect();
        if b.trim_start().starts_with('{') {
            return serde_json::from_str(b.trim())
                .or_else(|e| usage(format!("stdin is not valid JSON: {e}")));
        }
        return parse_input(&lines);
    }
    if args.len() == 1 && args[0].trim_start().starts_with('{') {
        return serde_json::from_str(&args[0])
            .or_else(|e| usage(format!("tool input is not valid JSON: {e}")));
    }
    let mut m = Map::new();
    for a in args {
        if let Some((k, v)) = a.split_once(":=") {
            if !k.contains('=') {
                m.insert(k.to_string(), Value::String(v.to_string()));
                continue;
            }
        }
        let Some((k, v)) = a.split_once('=') else {
            return usage(format!(
                "tool input `{a}`: use key=value, or one JSON object"
            ));
        };
        let val = if v == "@-" {
            let mut b = String::new();
            std::io::stdin()
                .read_to_string(&mut b)
                .or_else(|e| usage(format!("stdin: {e}")))?;
            Value::String(b)
        } else if let Some(p) = v.strip_prefix('@') {
            Value::String(std::fs::read_to_string(p).or_else(|e| usage(format!("{k}=@{p}: {e}")))?)
        } else {
            match serde_json::from_str::<Value>(v) {
                Ok(j) if !j.is_string() => j,
                _ => Value::String(v.to_string()),
            }
        };
        m.insert(k.to_string(), val);
    }
    Ok(Value::Object(m))
}

// ── commands ──

fn cmd_next(cx: &mut Ctx, timeout: u64, all: bool) -> R<u8> {
    let deadline = Instant::now() + Duration::from_secs(timeout);
    loop {
        let wanted = |e: &Value| {
            all || matches!(
                s(e, "type"),
                Some("message.received") | Some("conversation.started")
            )
        };
        let has_msg = cx
            .st
            .buffer
            .iter()
            .any(|e| all || s(e, "type") == Some("message.received"));
        if has_msg {
            let buf = std::mem::take(&mut cx.st.buffer);
            // tool results nobody asked for yet stay buffered for `result`
            let (show, keep): (Vec<Value>, Vec<Value>) = buf.into_iter().partition(|e| wanted(e));
            cx.st.buffer = keep
                .into_iter()
                .filter(|e| s(e, "type") == Some("tool.result"))
                .collect();
            let mut new_convs = Vec::new();
            for e in &show {
                // Auxiliary calls (titles, suggestions) never take over the
                // active conversation: a later bare `reply` must still land
                // in the real chat.
                if s(e, "type") == Some("message.received") && aux_hint(e).is_none() {
                    cx.st.active = conv_id(e).map(String::from);
                }
                if s(e, "type") == Some("conversation.started") {
                    if let Some(c) = conv_id(e) {
                        new_convs.push(c.to_string());
                    }
                }
            }
            for e in &show {
                if let Some(c) = conv_id(e).filter(|_| aux_hint(e).is_none()) {
                    if !cx.st.caps.contains_key(c) && !new_convs.iter().any(|n| n == c) {
                        new_convs.push(c.to_string());
                    }
                }
            }
            let mut tools_lines = Vec::new();
            for c in &new_convs {
                if let Ok(r) = fetch_caps(cx, c) {
                    let (tools, sp_len, client) = caps_summary(&r);
                    if let Some(cl) = client {
                        cx.st.convs.entry(c.clone()).or_default().client = Some(cl);
                    }
                    tools_lines.push(format!("tools in {c}: {}  (system prompt {sp_len} chars; `oh-seat caps` for signatures)", tools.join(", ")));
                    cx.st.caps.insert(c.clone(), caps_text(&r, true));
                }
            }
            cx.save();
            let mut show = show;
            for e in show.iter_mut() {
                if s(e, "client").is_none() {
                    if let Some(cl) = conv_id(e)
                        .and_then(|c| cx.st.convs.get(c))
                        .and_then(|i| i.client.clone())
                    {
                        e["client"] = json!(cl);
                    }
                }
            }
            for e in &show {
                if cx.json {
                    cx.out(e);
                } else {
                    print_event(e);
                }
            }
            // A conversation seen for the first time: say what tools it has,
            // so the next step needs no extra call.
            if !cx.json {
                for l in tools_lines {
                    println!("{l}");
                }
            }
            return Ok(OK);
        }
        let left = deadline.saturating_duration_since(Instant::now()).as_secs();
        if left == 0 {
            if !cx.json {
                println!("nothing new in {timeout}s (run `oh-seat next` again)");
            }
            return Ok(NOTHING);
        }
        cx.poll(left)?;
    }
}

fn cmd_reply(
    cx: &mut Ctx,
    text: Option<String>,
    file: Option<PathBuf>,
    conv: Option<String>,
    reasoning: Option<String>,
    more: bool,
) -> R<u8> {
    let c = cx.conv(conv)?;
    let text = match (file, text) {
        (Some(f), _) if f.as_os_str() != "-" => {
            std::fs::read_to_string(&f).or_else(|e| usage(format!("{}: {e}", f.display())))?
        }
        (None, Some(t)) if t != "-" => t,
        _ => {
            let mut b = String::new();
            std::io::stdin()
                .read_to_string(&mut b)
                .or_else(|e| usage(format!("stdin: {e}")))?;
            b
        }
    };
    if text.trim().is_empty() {
        return usage("empty reply");
    }
    let mut body = json!({
        "conversation_id": c, "text": text, "end_turn": !more,
        "client_msg_id": format!("ohs_{}", rand_hex(24)),
    });
    if let Some(r) = reasoning {
        body["reasoning"] = json!(r);
    }
    let r = cx.call("POST", "/v1/seat/reply", Some(body), 60)?;
    if cx.json {
        cx.out(&r);
    } else {
        let how = match r.get("live").and_then(|v| v.as_bool()) {
            Some(true) => "delivered live",
            Some(false) => "caller not connected; it gets the reply with its next request",
            None => "sent",
        };
        println!("replied conv={c} ({how})");
    }
    Ok(OK)
}

fn wait_result(cx: &mut Ctx, inv: &str, timeout: u64) -> R<u8> {
    let deadline = Instant::now() + Duration::from_secs(timeout);
    loop {
        if let Some(i) =
            cx.st.buffer.iter().position(|e| {
                s(e, "type") == Some("tool.result") && s(e, "invocation_id") == Some(inv)
            })
        {
            let e = cx.st.buffer.remove(i);
            cx.save();
            if cx.json {
                cx.out(&e);
            } else {
                print_event(&e);
            }
            return Ok(OK);
        }
        let left = deadline.saturating_duration_since(Instant::now()).as_secs();
        if left == 0 {
            if cx.json {
                cx.out(&json!({"pending": inv}));
            } else {
                println!("result not back yet: run `oh-seat result {inv}` to keep waiting");
            }
            return Ok(NOTHING);
        }
        cx.poll(left)?;
    }
}

fn cmd_tool(
    cx: &mut Ctx,
    name: String,
    input: Vec<String>,
    conv: Option<String>,
    text: Option<String>,
    reasoning: Option<String>,
    timeout: u64,
) -> R<u8> {
    let c = cx.conv(conv)?;
    let input = parse_input(&input)?;
    let mut body = json!({
        "conversation_id": c, "tool": name, "input": input, "wait": 0,
        "client_msg_id": format!("ohs_{}", rand_hex(24)),
    });
    if let Some(t) = text {
        body["text"] = json!(t);
    }
    if let Some(r) = reasoning {
        body["reasoning"] = json!(r);
    }
    let r = match cx.call("POST", "/v1/seat/tool-call", Some(body), 60) {
        Err(Fail(code, m)) if m.contains("404") => {
            let avail = cx
                .st
                .caps
                .get(&c)
                .map(|t| t.lines().nth(1).unwrap_or("").to_string())
                .unwrap_or_default();
            return Err(Fail(code, format!("{m}\n{avail}")));
        }
        x => x?,
    };
    let inv = s(&r, "invocation_id").unwrap_or("").to_string();
    if let Some(res) = r.get("result").filter(|v| !v.is_null()) {
        if cx.json {
            cx.out(res);
        } else {
            print_event(res);
        }
        return Ok(OK);
    }
    if inv.is_empty() {
        return Err(Fail(HTTP, format!("server returned no invocation id: {r}")));
    }
    wait_result(cx, &inv, timeout)
}

fn fetch_caps(cx: &Ctx, c: &str) -> R<Value> {
    cx.call(
        "GET",
        &format!("/v1/seat/capabilities?conversation_id={}&view=full", enc(c)),
        None,
        60,
    )
}

fn tool_list(r: &Value) -> Vec<Value> {
    for p in ["/context/tools", "/tools", "/capabilities"] {
        if let Some(a) = r
            .pointer(p)
            .and_then(|v| v.as_array())
            .filter(|a| !a.is_empty())
        {
            return a.clone();
        }
    }
    Vec::new()
}

fn tool_name(t: &Value) -> String {
    ["id", "name"]
        .iter()
        .find_map(|k| s(t, k))
        .or_else(|| t.pointer("/function/name").and_then(|v| v.as_str()))
        .unwrap_or("?")
        .to_string()
}

fn tool_schema(t: &Value) -> &Value {
    t.get("input_schema")
        .or_else(|| t.get("parameters"))
        .or_else(|| t.pointer("/function/parameters"))
        .unwrap_or(&Value::Null)
}

fn tool_desc(t: &Value) -> &str {
    s(t, "description")
        .or_else(|| t.pointer("/function/description").and_then(|v| v.as_str()))
        .unwrap_or("")
}

fn first_sentence(d: &str, max: usize) -> String {
    let line = d
        .lines()
        .map(str::trim)
        .find(|l| !l.is_empty())
        .unwrap_or("");
    let cut = line.find(". ").map(|i| &line[..=i]).unwrap_or(line);
    let mut out: String = cut.chars().take(max).collect();
    if cut.chars().count() > max {
        out.push('…');
    }
    out
}

fn ptype(p: &Value) -> String {
    match p.get("type") {
        Some(Value::String(t)) if t == "array" => {
            let inner = p.get("items").map(ptype).unwrap_or_else(|| "any".into());
            format!("{inner}[]")
        }
        Some(Value::String(t)) => t.clone(),
        Some(Value::Array(a)) => a
            .iter()
            .filter_map(|v| v.as_str())
            .collect::<Vec<_>>()
            .join("|"),
        _ if p.get("enum").is_some() => "enum".into(),
        _ => "any".into(),
    }
}

/// `Bash(command*: string, timeout: number)` — required params first, marked *.
fn tool_sig(t: &Value) -> String {
    let sc = tool_schema(t);
    let req: Vec<&str> = sc
        .get("required")
        .and_then(|v| v.as_array())
        .map(|a| a.iter().filter_map(|v| v.as_str()).collect())
        .unwrap_or_default();
    let mut params: Vec<(bool, String)> = Vec::new();
    if let Some(props) = sc.get("properties").and_then(|v| v.as_object()) {
        for (k, p) in props {
            let r = req.contains(&k.as_str());
            params.push((!r, format!("{k}{}: {}", if r { "*" } else { "" }, ptype(p))));
        }
    }
    params.sort_by(|a, b| a.0.cmp(&b.0));
    format!(
        "{}({})",
        tool_name(t),
        params
            .into_iter()
            .map(|p| p.1)
            .collect::<Vec<_>>()
            .join(", ")
    )
}

fn caps_summary(r: &Value) -> (Vec<String>, usize, Option<String>) {
    let tools = tool_list(r).iter().map(tool_name).collect();
    let sp = r
        .pointer("/context/system_prompt")
        .or_else(|| r.get("system_prompt"))
        .and_then(|v| v.as_str())
        .unwrap_or("");
    let client = r
        .pointer("/context/client")
        .or_else(|| r.get("client"))
        .and_then(|v| v.as_str())
        .map(String::from);
    (tools, sp.chars().count(), client)
}

fn caps_text(r: &Value, full: bool) -> String {
    let (tools, sp_len, client) = caps_summary(r);
    let mut out = vec![
        format!("client: {}", client.unwrap_or_else(|| "?".into())),
        format!("tools ({}): {}", tools.len(), tools.join(", ")),
    ];
    if full {
        let sp = r
            .pointer("/context/system_prompt")
            .or_else(|| r.get("system_prompt"))
            .and_then(|v| v.as_str())
            .unwrap_or("");
        out.push(format!("system prompt ({sp_len} chars):"));
        out.push(sp.to_string());
        for t in tool_list(r) {
            out.push(format!("--- tool {}", tool_name(&t)));
            out.push(t.to_string());
        }
    } else {
        for t in tool_list(r) {
            out.push(format!(
                "  {}  {}",
                tool_sig(&t),
                first_sentence(tool_desc(&t), 90)
            ));
        }
        out.push(format!(
            "system prompt: {sp_len} chars (--full to read it; * = required)"
        ));
    }
    out.join("\n")
}

fn line_diff(old: &str, new: &str) -> String {
    let o: Vec<&str> = old.lines().collect();
    let n: Vec<&str> = new.lines().collect();
    let mut out = Vec::new();
    for l in &o {
        if !n.contains(l) {
            out.push(format!("- {l}"));
        }
    }
    for l in &n {
        if !o.contains(l) {
            out.push(format!("+ {l}"));
        }
    }
    out.join("\n")
}

fn cmd_caps(
    cx: &mut Ctx,
    conv: Option<String>,
    full: bool,
    diff: bool,
    tool: Option<String>,
    schema: bool,
) -> R<u8> {
    let c = cx.conv(conv)?;
    let r = fetch_caps(cx, &c)?;
    if let Some(name) = tool {
        let list = tool_list(&r);
        let Some(t) = list.iter().find(|t| tool_name(t) == name) else {
            let names: Vec<_> = list.iter().map(tool_name).collect();
            return usage(format!(
                "no tool `{name}` in {c}; tools: {}",
                names.join(", ")
            ));
        };
        if cx.json {
            cx.out(t);
        } else if schema {
            println!(
                "{}",
                serde_json::to_string_pretty(tool_schema(t)).unwrap_or_default()
            );
        } else {
            println!("{}", tool_sig(t));
            println!("{}", first_sentence(tool_desc(t), 300));
            if let Some(props) = tool_schema(t).get("properties").and_then(|v| v.as_object()) {
                for (k, p) in props {
                    let mut line = format!("  {k}: {}", ptype(p));
                    if let Some(en) = p.get("enum").and_then(|v| v.as_array()) {
                        line.push_str(&format!(" one of {}", Value::Array(en.clone())));
                    }
                    if let Some(d) = s(p, "description") {
                        line.push_str(&format!(" — {}", first_sentence(d, 160)));
                    }
                    println!("{line}");
                }
            }
            println!("(oh-seat tool {name} key=value ... ; --schema for raw JSON)");
        }
        return Ok(OK);
    }
    if cx.json {
        cx.out(&r);
        return Ok(OK);
    }
    let txt = caps_text(&r, true);
    if diff {
        match cx.st.caps.get(&c) {
            None => println!(
                "{}",
                if full {
                    txt.clone()
                } else {
                    caps_text(&r, false)
                }
            ),
            Some(old) if *old == txt => println!("no change since last view"),
            Some(old) => println!("{}", line_diff(old, &txt)),
        }
    } else {
        println!(
            "{}",
            if full {
                txt.clone()
            } else {
                caps_text(&r, false)
            }
        );
    }
    cx.st.caps.insert(c, txt);
    cx.save();
    Ok(OK)
}

fn cmd_history(cx: &mut Ctx, conv: Option<String>, limit: usize) -> R<u8> {
    let c = cx.conv(conv)?;
    let r = cx.call(
        "GET",
        &format!("/v1/seat/history?conversation_id={}&limit={limit}", enc(&c)),
        None,
        60,
    )?;
    if cx.json {
        cx.out(&r);
        return Ok(OK);
    }
    let msgs = r
        .get("messages")
        .and_then(|v| v.as_array())
        .cloned()
        .or_else(|| r.as_array().cloned())
        .unwrap_or_default();
    if msgs.is_empty() {
        println!("no messages");
    }
    for m in msgs {
        let role = s(&m, "role").or_else(|| s(&m, "side")).unwrap_or("?");
        let when = s(&m, "time").or_else(|| s(&m, "timestamp")).unwrap_or("");
        let text = match m.get("text").or_else(|| m.get("content")) {
            Some(Value::String(t)) => t.clone(),
            Some(v) => v.to_string(),
            None => String::new(),
        };
        println!("[{when}] {role}: {text}");
    }
    Ok(OK)
}

fn cmd_convs(cx: &Ctx) -> R<u8> {
    let mut v: Vec<_> = cx.st.convs.iter().collect();
    v.sort_by_key(|(_, i)| std::cmp::Reverse(i.t));
    if v.is_empty() {
        println!("no conversations seen yet (run `oh-seat next`)");
    }
    for (c, i) in v {
        let mark = if cx.st.active.as_deref() == Some(c.as_str()) {
            "*"
        } else {
            " "
        };
        if cx.json {
            cx.out(&json!({"conversation_id": c, "client": i.client, "last": i.last, "active": mark == "*"}));
        } else {
            println!(
                "{mark} {c} client={} last={:?}",
                i.client.as_deref().unwrap_or("?"),
                i.last
            );
        }
    }
    Ok(OK)
}

fn cmd_status(cx: &mut Ctx) -> R<u8> {
    // A wait=0 poll is still a read: keep what it returned.
    let (waiting, ok) = match cx.poll(0) {
        Ok(w) => (w, "ok".to_string()),
        Err(Fail(_, m)) => (json!([]), m),
    };
    let st = json!({
        "url": cx.url, "server": ok, "consumer": cx.st.consumer, "cursor": cx.st.cursor,
        "active": cx.st.active, "buffered_events": cx.st.buffer.len(), "open_turns": waiting,
        "state_file": cx.state_path.display().to_string(),
    });
    if cx.json {
        cx.out(&st);
    } else {
        for (k, v) in st.as_object().unwrap() {
            println!(
                "{k}: {}",
                v.as_str()
                    .map(String::from)
                    .unwrap_or_else(|| v.to_string())
            );
        }
    }
    Ok(if ok == "ok" { OK } else { HTTP })
}

fn run(cli: Cli) -> R<u8> {
    let mut cx = Ctx::new(cli.g)?;
    match cli.cmd {
        Cmd::Next { timeout, all } => cmd_next(&mut cx, timeout, all),
        Cmd::Reply {
            text,
            file,
            conv,
            reasoning,
            more,
            next,
            timeout,
        } => {
            cmd_reply(&mut cx, text, file, conv, reasoning, more)?;
            if next {
                cmd_next(&mut cx, timeout, false)
            } else {
                Ok(OK)
            }
        }
        Cmd::Tool {
            name,
            input,
            conv,
            text,
            reasoning,
            timeout,
        } => cmd_tool(&mut cx, name, input, conv, text, reasoning, timeout),
        Cmd::Result {
            invocation_id,
            timeout,
        } => wait_result(&mut cx, &invocation_id, timeout),
        Cmd::Caps {
            conv,
            full,
            diff,
            tool,
            schema,
        } => cmd_caps(&mut cx, conv, full, diff, tool, schema),
        Cmd::History { conv, limit } => cmd_history(&mut cx, conv, limit),
        Cmd::Convs => cmd_convs(&cx),
        Cmd::Use { conv } => {
            cx.st.active = Some(conv.clone());
            cx.save();
            println!("active conversation: {conv}");
            Ok(OK)
        }
        Cmd::Save { conv } => {
            let c = cx.conv(conv)?;
            let r = cx.call(
                "POST",
                "/v1/seat/save",
                Some(json!({"conversation_id": c})),
                60,
            )?;
            if cx.json {
                cx.out(&r);
            } else {
                println!("saved conv={c}");
            }
            Ok(OK)
        }
        Cmd::Status => cmd_status(&mut cx),
    }
}

fn main() -> ExitCode {
    let cli = Cli::parse();
    match run(cli) {
        Ok(c) => ExitCode::from(c),
        Err(Fail(c, m)) => {
            eprintln!("error: {m}");
            ExitCode::from(c)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn input_pairs_and_json() {
        let v = parse_input(&[
            "command=ls -la".into(),
            "timeout=5".into(),
            "flag=true".into(),
            "s:=5".into(),
        ])
        .unwrap();
        assert_eq!(
            v,
            json!({"command": "ls -la", "timeout": 5, "flag": true, "s": "5"})
        );
        let v = parse_input(&[r#"{"a":[1,2]}"#.into()]).unwrap();
        assert_eq!(v, json!({"a": [1, 2]}));
        assert!(parse_input(&["oops".into()]).is_err());
        assert_eq!(parse_input(&[]).unwrap(), json!({}));
    }

    #[test]
    fn aux_hints() {
        let e = json!({"type": "message.received", "text": "Generate a title for this conversation: hi"});
        assert!(aux_hint(&e).unwrap().contains("short title"));
        let e =
            json!({"type": "message.received", "text": "x", "expected_format": "a JSON object"});
        assert_eq!(aux_hint(&e).unwrap(), "answer with a JSON object");
        let e = json!({"type": "message.received", "text": "hello", "kind": "chat"});
        assert!(aux_hint(&e).is_none());
    }

    #[test]
    fn diff_lines() {
        assert_eq!(line_diff("a\nb", "a\nc"), "- b\n+ c");
    }
}
