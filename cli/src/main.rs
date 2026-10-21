//! oh-seat — sit in the OpenHuman responder seat from any terminal.
//!
//! Built for AI agents that drive a shell one command at a time:
//! one command = one complete step, short structured output, state kept in
//! a file (never in the agent's head), every blocking call bounded by a
//! timeout the agent picks. See docs/seat-cli.md.

use clap::{Args, Parser, Subcommand};
use serde_json::{json, Value};
use std::collections::BTreeMap;
use std::io::Read;
use std::path::PathBuf;
use std::process::ExitCode;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

mod input;

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
const TOOL_ERR: u8 = 1; // the tool ran on the caller and reported an error
const NOTHING: u8 = 2; // timed out with nothing new
const HTTP: u8 = 3; // network / auth / server error
const USAGE: u8 = 4; // bad command, unknown tool/parameter, unknown conversation
const NO_TURN: u8 = 5; // the caller is not waiting: no open turn to act in

const GUIDE: &str = include_str!("guide.txt");

#[derive(Parser)]
#[command(
    name = "oh-seat",
    version,
    about = "OpenHuman Agent Seat: answer callers (Claude Code, Codex, ...) and run tools on their side",
    after_help = "Start with `oh-seat guide` (one screen, everything you need).\n\nExit codes: 0 ok, 1 tool reported an error, 2 nothing new before --timeout, 3 network/auth/server, 4 usage (unknown tool/parameter/conversation), 5 no open turn."
)]
struct Cli {
    #[command(flatten)]
    g: Global,
    #[command(subcommand)]
    cmd: Option<Cmd>,
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
        #[arg(allow_hyphen_values = true)]
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
    /// Ask the caller to run one of its tools (or several: `A k=v + B k=v`); waits and prints results in order.
    ///
    /// Input: key=value pairs typed by the tool's schema (string params keep the text as is),
    /// key=@path reads a file, key=@- reads stdin, key:=v forces a string, key:json=v forces JSON;
    /// or one JSON object; or `-` for the whole input on stdin. Checked before sending.
    Tool {
        name: String,
        input: Vec<String>,
        /// Send even if the input does not match the tool's schema
        #[arg(long)]
        force: bool,
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
    /// Everything you need on one screen: the loop, input rules, exit codes
    Guide,
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
    /// Tool list (with schemas) per conversation, to type and check input.
    #[serde(default)]
    tools: BTreeMap<String, Vec<Value>>,
    /// Tool results already printed: a replay never shows them again.
    #[serde(default)]
    done: Vec<String>,
    /// Late results already mentioned once by `next`.
    #[serde(default)]
    hinted: Vec<String>,
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
                let ecode = serde_json::from_str::<Value>(&body)
                    .ok()
                    .and_then(|v| {
                        v.pointer("/error/code")
                            .and_then(|c| c.as_str())
                            .map(String::from)
                    })
                    .unwrap_or_default();
                let hint = match code {
                    401 => " (key missing, wrong or revoked)",
                    403 => " (this key may not sit in the seat: it needs scope responder or both)",
                    _ => "",
                };
                let exit = match (code, ecode.as_str()) {
                    (409, "no_open_turn") => NO_TURN,
                    (400 | 404 | 409 | 422, _) => USAGE,
                    _ => HTTP,
                };
                Err(Fail(exit, format!("HTTP {code} {short}: {msg}{hint}")))
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
        let mut from_zero = self.st.cursor == 0;
        let mut r = self.inbox(self.st.cursor, wait)?;
        let latest = r.get("latest").and_then(|v| v.as_u64());
        if matches!(latest, Some(l) if l < self.st.cursor) {
            self.st.cursor = 0;
            from_zero = true;
            r = self.inbox(0, 0)?;
        }
        // Reading from the start (a fresh state file, or a re-created seat)
        // returns whatever the queue still holds, including messages another
        // seat process already answered. Only those whose turn is still open
        // need an answer; replaying the rest makes an agent answer twice.
        let open: Vec<String> = r
            .get("waiting_turns")
            .and_then(|v| v.as_array())
            .map(|a| {
                a.iter()
                    .filter_map(|v| v.as_str().map(String::from))
                    .collect()
            })
            .unwrap_or_default();
        if let Some(c) = r.get("cursor").and_then(|v| v.as_u64()) {
            self.st.cursor = c;
        }
        for e in r
            .get("events")
            .and_then(|v| v.as_array())
            .cloned()
            .unwrap_or_default()
        {
            // Delivery receipts tell the seat nothing it can act on.
            if matches!(s(&e, "type"), Some("reply.delivered")) {
                continue;
            }
            if from_zero
                && s(&e, "type") == Some("message.received")
                && !open
                    .iter()
                    .any(|o| Some(o.as_str()) == s(&e, "conversation_id"))
            {
                continue;
            }
            if s(&e, "type") == Some("tool.result") {
                let inv = s(&e, "invocation_id").unwrap_or("");
                let dup = self.st.done.iter().any(|d| d == inv)
                    || self
                        .st
                        .buffer
                        .iter()
                        .any(|b| s(b, "invocation_id") == Some(inv));
                if dup {
                    continue;
                }
            }
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
                self.st.tools.remove(&k);
            }
        }
    }

    fn conv(&self, c: Option<String>) -> R<String> {
        match c {
            Some(c) => self.resolve_conv(&c),
            None => self.st.active.clone().ok_or_else(|| {
                Fail(
                    USAGE,
                    "no active conversation: run `oh-seat next` first, or pass -c CONV".into(),
                )
            }),
        }
    }

    /// A full id, or any unique piece of one this seat has seen (`-c 6da0c`).
    fn resolve_conv(&self, c: &str) -> R<String> {
        let c = c.trim();
        if self.st.convs.contains_key(c) {
            return Ok(c.to_string());
        }
        let hits: Vec<&String> = self.st.convs.keys().filter(|k| k.contains(c)).collect();
        match hits.len() {
            1 => Ok(hits[0].clone()),
            0 if c.starts_with("cnv_") && c.len() >= 20 => Ok(c.to_string()),
            0 => usage(format!(
                "no conversation matches `{c}` (known: {}; `oh-seat convs`)",
                self.short_list()
            )),
            _ => usage(format!(
                "`{c}` matches {} conversations: {}; give more of the id",
                hits.len(),
                hits.iter()
                    .map(|h| h.as_str())
                    .collect::<Vec<_>>()
                    .join(", ")
            )),
        }
    }

    fn short_list(&self) -> String {
        if self.st.convs.is_empty() {
            return "none yet".into();
        }
        self.st.convs.keys().cloned().collect::<Vec<_>>().join(", ")
    }

    /// The caller's tools for a conversation, cached; `fresh` re-reads them.
    fn tools_for(&mut self, c: &str, fresh: bool) -> Vec<Value> {
        if !fresh {
            if let Some(t) = self.st.tools.get(c).filter(|t| !t.is_empty()) {
                return t.clone();
            }
        }
        match fetch_caps(self, c) {
            Ok(r) => {
                let t = tool_list(&r);
                self.st.tools.insert(c.to_string(), t.clone());
                self.save();
                t
            }
            Err(_) => self.st.tools.get(c).cloned().unwrap_or_default(),
        }
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
            let code = exit_code(e)
                .map(|c| format!(" exit_code={c}"))
                .unwrap_or_default();
            println!(
                "TOOL RESULT {} status={}{code} id={}",
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
            let ev_env = |c: &str| -> Option<String> {
                show.iter()
                    .filter(|e| conv_id(e) == Some(c))
                    .find_map(|e| e.get("env").and_then(|v| v.as_object()).cloned())
                    .map(|m| {
                        m.iter()
                            .map(|(k, v)| format!("{k}={}", v.as_str().unwrap_or("")))
                            .collect::<Vec<_>>()
                            .join("  ")
                    })
            };
            for c in &new_convs {
                if let Ok(r) = fetch_caps(cx, c) {
                    let (_, sp_len, client) = caps_summary(&r);
                    if let Some(cl) = client {
                        cx.st.convs.entry(c.clone()).or_default().client = Some(cl);
                    }
                    let list = tool_list(&r);
                    if list.is_empty() {
                        tools_lines.push(format!(
                            "{c} declared no tools (system prompt {sp_len} chars): reply only"
                        ));
                    } else {
                        tools_lines.push(format!(
                            "tools in {c} ({}; * = required; system prompt {sp_len} chars, `oh-seat caps --full`):",
                            list.len()
                        ));
                        for t in &list {
                            tools_lines.push(format!("  {}", tool_sig(t)));
                        }
                    }
                    if let Some(env) = env_line(&r).or_else(|| ev_env(c)) {
                        tools_lines.push(format!("  caller env: {env}"));
                    }
                    cx.st.tools.insert(c.clone(), list);
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
                let late: Vec<String> = cx
                    .st
                    .buffer
                    .iter()
                    .filter(|e| s(e, "type") == Some("tool.result"))
                    .filter_map(|e| s(e, "invocation_id"))
                    .filter(|i| !cx.st.hinted.iter().any(|h| h == i))
                    .map(String::from)
                    .collect();
                cx.st.hinted.extend(late.iter().cloned());
                let n = cx.st.hinted.len();
                if n > 200 {
                    cx.st.hinted.drain(..n - 200);
                }
                cx.save();
                if !late.is_empty() {
                    println!(
                        "({} earlier tool result(s) waiting: oh-seat result {})",
                        late.len(),
                        late.join(" / ")
                    );
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

/// Wait for one tool result (from the buffer or new polls) until `deadline`.
fn await_result(cx: &mut Ctx, inv: &str, deadline: Instant) -> R<Option<Value>> {
    loop {
        if let Some(i) =
            cx.st.buffer.iter().position(|e| {
                s(e, "type") == Some("tool.result") && s(e, "invocation_id") == Some(inv)
            })
        {
            let e = cx.st.buffer.remove(i);
            cx.st.done.push(inv.to_string());
            let n = cx.st.done.len();
            if n > 200 {
                cx.st.done.drain(..n - 200);
            }
            cx.save();
            return Ok(Some(e));
        }
        let left = deadline.saturating_duration_since(Instant::now()).as_secs();
        if left == 0 {
            return Ok(None);
        }
        cx.poll(left)?;
    }
}

/// The shell exit code a caller wrote into a result's text. pi and Codex
/// report a failed command as a successful tool call whose output ends
/// with "Command exited with code 2" / "Process exited with code 2".
fn exit_code(e: &Value) -> Option<i64> {
    let out = s(e, "output")?;
    let tail: String = {
        let t = out.trim_end();
        let start = t.char_indices().rev().nth(400).map(|(i, _)| i).unwrap_or(0);
        t[start..].to_string()
    };
    let mut found = None;
    for line in tail.lines().chain(out.lines().take(4)) {
        let l = line.trim().to_ascii_lowercase();
        for pre in [
            "command exited with code ",
            "process exited with code ",
            "exit code: ",
            "exit code ",
            "exited with code ",
        ] {
            if let Some(rest) = l.strip_prefix(pre) {
                let n: String = rest
                    .chars()
                    .take_while(|c| c.is_ascii_digit() || *c == '-')
                    .collect();
                if let Ok(n) = n.parse::<i64>() {
                    found = Some(n);
                }
            }
        }
        if found.is_some() {
            break;
        }
    }
    found
}

fn result_exit(e: &Value) -> u8 {
    if matches!(exit_code(e), Some(c) if c != 0) {
        return TOOL_ERR;
    }
    match s(e, "status") {
        Some("error") | Some("failed") | Some("failure") => TOOL_ERR,
        _ if e.get("error").map(|v| !v.is_null()).unwrap_or(false) => TOOL_ERR,
        _ => OK,
    }
}

fn wait_result(cx: &mut Ctx, inv: &str, timeout: u64) -> R<u8> {
    let deadline = Instant::now() + Duration::from_secs(timeout);
    match await_result(cx, inv, deadline)? {
        Some(mut e) => {
            if let Some(c) = exit_code(&e) {
                e["exit_code"] = json!(c);
            }
            if cx.json {
                cx.out(&e);
            } else {
                print_event(&e);
            }
            Ok(result_exit(&e))
        }
        None => {
            if cx.json {
                cx.out(&json!({"pending": inv}));
            } else {
                println!("result not back yet: run `oh-seat result {inv}` to keep waiting");
            }
            Ok(NOTHING)
        }
    }
}

/// Find a tool by name: exact, then case-insensitive.
fn find_tool<'a>(tools: &'a [Value], name: &str) -> Option<&'a Value> {
    tools.iter().find(|t| tool_name(t) == name).or_else(|| {
        let hits: Vec<&Value> = tools
            .iter()
            .filter(|t| tool_name(t).eq_ignore_ascii_case(name))
            .collect();
        (hits.len() == 1).then(|| hits[0])
    })
}

fn unknown_tool(c: &str, name: &str, tools: &[Value]) -> String {
    let names: Vec<String> = tools.iter().map(tool_name).collect();
    let refs: Vec<&str> = names.iter().map(|s| s.as_str()).collect();
    let mut m = format!("no tool `{name}` in {c}");
    if let Some(n) = input::closest(name, &refs) {
        if let Some(t) = find_tool(tools, n) {
            m.push_str(&format!("; did you mean {}?", tool_sig(t)));
        }
    }
    m.push_str(&format!("\ntools: {}", names.join(", ")));
    m
}

struct Prepared {
    tool: String,
    input: Value,
}

fn prepare(
    cx: &mut Ctx,
    c: &str,
    calls: Vec<(String, Vec<String>)>,
    force: bool,
) -> R<Vec<Prepared>> {
    let mut tools = cx.tools_for(c, false);
    let mut refreshed = false;
    let mut out = Vec::new();
    let mut errs = Vec::new();
    let many = calls.len() > 1;
    for (i, (name, args)) in calls.into_iter().enumerate() {
        let tag = if many {
            format!("call {} ({name})", i + 1)
        } else {
            name.clone()
        };
        let parsed = input::parse(&args).map_err(|e| Fail(USAGE, format!("{tag}: {e}")))?;
        if tools.is_empty() {
            // No tool list known (the caller declared none we can read):
            // send as written and let the server judge the name.
            let m = input::build(parsed, &Value::Null).unwrap_or_default();
            out.push(Prepared {
                tool: name,
                input: Value::Object(m),
            });
            continue;
        }
        let mut t = find_tool(&tools, &name).cloned();
        if t.is_none() && !refreshed {
            tools = cx.tools_for(c, true);
            refreshed = true;
            t = find_tool(&tools, &name).cloned();
        }
        let Some(t) = t else {
            if force {
                let m = input::build(parsed, &Value::Null).unwrap_or_default();
                out.push(Prepared {
                    tool: name,
                    input: Value::Object(m),
                });
                continue;
            }
            errs.push(unknown_tool(c, &name, &tools));
            continue;
        };
        let real = tool_name(&t);
        match input::build(parsed.clone(), tool_schema(&t)) {
            Ok(m) => out.push(Prepared {
                tool: real,
                input: Value::Object(m),
            }),
            Err(_) if force => {
                let m = input::build(parsed, &Value::Null).unwrap_or_default();
                out.push(Prepared {
                    tool: real,
                    input: Value::Object(m),
                });
            }
            Err(e) => errs.push(format!(
                "{tag}: {}\n  usage: {}   (`oh-seat caps --tool {real}` explains each parameter)",
                e.join("; "),
                tool_sig(&t)
            )),
        }
    }
    if !errs.is_empty() {
        return usage(format!(
            "{}\nnothing was sent (--force sends anyway)",
            errs.join("\n")
        ));
    }
    Ok(out)
}

#[allow(clippy::too_many_arguments)]
fn cmd_tool(
    cx: &mut Ctx,
    name: String,
    input: Vec<String>,
    conv: Option<String>,
    text: Option<String>,
    reasoning: Option<String>,
    timeout: u64,
    force: bool,
) -> R<u8> {
    let c = cx.conv(conv)?;
    let calls = input::split_batch(&name, &input).map_err(|e| Fail(USAGE, e))?;
    let prepared = prepare(cx, &c, calls, force)?;
    let n = prepared.len();
    let bodies: Vec<Value> = prepared
        .into_iter()
        .enumerate()
        .map(|(i, p)| {
            let mut body = json!({
                "conversation_id": c, "tool": p.tool, "input": p.input, "wait": 0,
                "client_msg_id": format!("ohs_{}", rand_hex(24)),
            });
            // Words and thinking ride on the first call only.
            if i == 0 {
                if let Some(t) = &text {
                    body["text"] = json!(t);
                }
                if let Some(r) = &reasoning {
                    body["reasoning"] = json!(r);
                }
            }
            body
        })
        .collect();
    // All calls go out at once so they land inside the server's merge
    // window and reach the caller as one assistant message (parallel
    // tool_calls), exactly like a model calling several tools.
    let sent: Vec<R<Value>> = if n == 1 {
        vec![cx.call("POST", "/v1/seat/tool-call", Some(bodies[0].clone()), 60)]
    } else {
        let cxr: &Ctx = cx;
        std::thread::scope(|sc| {
            let hs: Vec<_> = bodies
                .iter()
                .enumerate()
                .map(|(i, b)| {
                    sc.spawn(move || {
                        // keep the caller-visible order stable
                        std::thread::sleep(Duration::from_millis(40 * i as u64));
                        cxr.call("POST", "/v1/seat/tool-call", Some(b.clone()), 60)
                    })
                })
                .collect();
            hs.into_iter()
                .map(|h| {
                    h.join()
                        .unwrap_or_else(|_| Err(Fail(HTTP, "thread panicked".into())))
                })
                .collect()
        })
    };
    let mut invs: Vec<R<String>> = Vec::new();
    for (r, b) in sent.into_iter().zip(&bodies) {
        invs.push(r.and_then(|r| match s(&r, "invocation_id") {
            Some(i) => Ok(i.to_string()),
            None => Err(Fail(
                HTTP,
                format!("server returned no invocation id for {}: {r}", b["tool"]),
            )),
        }));
    }
    if n == 1 {
        let inv = invs.pop().unwrap()?;
        return wait_result(cx, &inv, timeout);
    }
    let deadline = Instant::now() + Duration::from_secs(timeout);
    let mut worst = OK;
    for (i, (inv, b)) in invs.into_iter().zip(&bodies).enumerate() {
        let tool = b["tool"].as_str().unwrap_or("?").to_string();
        let res = match inv {
            Ok(inv) => await_result(cx, &inv, deadline).map(|r| (inv, r)),
            Err(e) => Err(e),
        };
        match res {
            Ok((_, Some(e))) => {
                worst = worst.max(result_exit(&e));
                if cx.json {
                    let mut e = e;
                    e["batch_index"] = json!(i + 1);
                    if let Some(c) = exit_code(&e) {
                        e["exit_code"] = json!(c);
                    }
                    cx.out(&e);
                } else {
                    println!("[{}/{n}]", i + 1);
                    print_event(&e);
                }
            }
            Ok((inv, None)) => {
                worst = worst.max(NOTHING);
                if cx.json {
                    cx.out(&json!({"batch_index": i + 1, "pending": inv, "tool": tool}));
                } else {
                    println!(
                        "[{}/{n}] {tool}: not back yet: `oh-seat result {inv}`",
                        i + 1
                    );
                }
            }
            Err(Fail(code, m)) => {
                worst = worst.max(code);
                if cx.json {
                    cx.out(&json!({"batch_index": i + 1, "tool": tool, "error": m, "exit": code}));
                } else {
                    println!("[{}/{n}] {tool}: not sent: {m}", i + 1);
                }
            }
        }
    }
    Ok(worst)
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
    params.sort_by_key(|a| a.0);
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

/// The caller's machine as its system prompt describes it: working
/// directory, platform, shell, date. Saves reading 10k chars of prompt to
/// learn where relative paths land.
fn env_hints(sp: &str) -> Vec<(&'static str, String)> {
    let mut out: Vec<(&'static str, String)> = Vec::new();
    let mut put = |k: &'static str, v: &str| {
        let v = v.trim().trim_matches('`').trim();
        if !v.is_empty() && v.len() < 300 && !out.iter().any(|(x, _)| *x == k) {
            out.push((k, v.to_string()));
        }
    };
    for line in sp.lines() {
        let l = line.trim().trim_start_matches(['-', '*', ' ']);
        let low = l.to_ascii_lowercase();
        for (pre, k) in [
            ("current working directory:", "cwd"),
            ("working directory:", "cwd"),
            ("primary working directory:", "cwd"),
            ("cwd:", "cwd"),
            ("platform:", "platform"),
            ("os:", "platform"),
            ("shell:", "shell"),
            ("current date:", "date"),
            ("today's date:", "date"),
        ] {
            if low.starts_with(pre) {
                put(k, &l[pre.len()..]);
            }
        }
        for (tag, k) in [("cwd", "cwd"), ("shell", "shell"), ("current_date", "date")] {
            let open = format!("<{tag}>");
            let close = format!("</{tag}>");
            if let Some(a) = l.find(&open) {
                if let Some(b) = l[a..].find(&close) {
                    put(k, &l[a + open.len()..a + b]);
                }
            }
        }
        if let Some(rest) = low.strip_prefix("today's date is ") {
            put("date", rest.trim_end_matches('.'));
        }
    }
    let rank = |k: &str| {
        ["cwd", "platform", "shell", "date"]
            .iter()
            .position(|x| *x == k)
    };
    out.sort_by_key(|(k, _)| rank(k));
    out.retain(|(_, v)| v != "unknown");
    out
}

fn env_line(r: &Value) -> Option<String> {
    let sp = r
        .pointer("/context/system_prompt")
        .or_else(|| r.get("system_prompt"))
        .and_then(|v| v.as_str())
        .unwrap_or("");
    let h = env_hints(sp);
    (!h.is_empty()).then(|| {
        h.iter()
            .map(|(k, v)| format!("{k}={v}"))
            .collect::<Vec<_>>()
            .join("  ")
    })
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
    if let Some(env) = env_line(r) {
        out.push(format!("caller env: {env}"));
    }
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
        cx.st.tools.insert(c.clone(), list.clone());
        let Some(t) = find_tool(&list, &name) else {
            return usage(unknown_tool(&c, &name, &list));
        };
        let name = tool_name(t);
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
    let cmd = match cli.cmd {
        None | Some(Cmd::Guide) => {
            println!("{}", GUIDE.trim_end());
            return Ok(OK);
        }
        Some(c) => c,
    };
    let mut cx = Ctx::new(cli.g)?;
    match cmd {
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
            force,
        } => cmd_tool(&mut cx, name, input, conv, text, reasoning, timeout, force),
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
            let conv = cx.resolve_conv(&conv)?;
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
        Cmd::Guide => unreachable!(),
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
    fn exit_codes_in_output() {
        let r = |o: &str| json!({"type": "tool.result", "status": "success", "output": o});
        assert_eq!(
            exit_code(&r("ls: nope\n\n\nCommand exited with code 2")),
            Some(2)
        );
        assert_eq!(result_exit(&r("x\nCommand exited with code 2")), TOOL_ERR);
        let codex =
            "Chunk ID: 1\nWall time: 0.0 seconds\nProcess exited with code 0\nOutput:\n/w\n";
        assert_eq!(exit_code(&r(codex)), Some(0));
        assert_eq!(result_exit(&r(codex)), OK);
        assert_eq!(
            exit_code(&r("Exit code 127\nbash: foo: not found")),
            Some(127)
        );
        assert_eq!(exit_code(&r("hello")), None);
    }

    #[test]
    fn env_from_prompts() {
        let claude = "<env>\nWorking directory: /home/a/p\nIs directory a git repo: no\nPlatform: linux\nOS Version: Linux 6\n</env>\nToday's date is 2026-10-21.";
        let h = env_hints(claude);
        assert_eq!(h[0], ("cwd", "/home/a/p".to_string()));
        assert!(h.contains(&("platform", "linux".to_string())));
        assert!(h.contains(&("date", "2026-10-21".to_string())));
        let codex = "<environment_context>\n  <cwd>/srv/x</cwd>\n  <shell>bash</shell>\n</environment_context>";
        let h = env_hints(codex);
        assert_eq!(
            h,
            vec![("cwd", "/srv/x".to_string()), ("shell", "bash".to_string())]
        );
        assert_eq!(
            env_hints("Current working directory: /w\nCurrent date: 2026-10-21")[0].1,
            "/w"
        );
        assert!(env_hints("you are helpful").is_empty());
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
