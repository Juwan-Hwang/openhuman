//! Segmented continuous streaming (design doc §6).
//!
//! Filled in by the ingress work: segment timing (quiet / progressive /
//! max), keepalive tool selection, interjection parsing. Kept as a module
//! from the start so `rooms::mod` does not grow a second responsibility.

/// The fixed id prefix every keepalive tool call carries. Results whose
/// call id starts with this are dropped on sight — never logged, never
/// broadcast, never counted for dedup — and a restart needs no state to
/// recognize them.
pub const KEEPALIVE_ID_PREFIX: &str = "ohka_";

/// Read-only, approval-free tools we borrow to close a segment, in
/// preference order per client. This is a maintained config table with
/// version notes, not a frozen enum: clients rename tools across
/// versions, and only tools the validation matrix confirmed as
/// approval-free may be listed.
///
/// - Claude Code: `ListAgents` (2.1.x, confirmed approval-free by review)
/// - Codex: `get_goal` (0.16x, reportedly invisible in the UI)
/// - Copilot: `list_bash` (1.0.x)
/// - DeepSeek Harness 0.2.1: `get_goal`, `job_list`, `schedule_list` (all
///   argument-free reads, measured 2026-11-02). DSH nudges the model after
///   3 identical consecutive calls, so keepalives rotate among the
///   client's listed tools (see [`keepalive_candidates`]).
/// - ZCode 3.16: `TodoRead`; Reasonix 2.47: `context_budget` (argument-free
///   reads, measured 2026-11-02; before this both got the fallback and
///   showed "tool not found" in their UI). Grok 1.0.62: `scheduler_list`.
pub const KEEPALIVE_TOOL_WHITELIST: &[&str] = &[
    "ListAgents",
    "get_goal",
    "job_list",
    "schedule_list",
    "list_bash",
    "TodoRead",
    "context_budget",
    "scheduler_list",
];

/// The whitelisted tools this client declared, in whitelist order.
pub fn keepalive_candidates(declared: &[String]) -> Vec<&'static str> {
    KEEPALIVE_TOOL_WHITELIST
        .iter()
        .copied()
        .filter(|w| declared.iter().any(|d| d == w))
        .collect()
}

/// The keepalive tool for the `n`th keepalive: rotate among the client's
/// candidates so no two consecutive keepalives are identical calls when
/// the client offers more than one; the fallback when it offers none.
pub fn keepalive_tool_for(declared: &[String], n: usize) -> &'static str {
    let c = keepalive_candidates(declared);
    if c.is_empty() {
        KEEPALIVE_FALLBACK_TOOL
    } else {
        c[n % c.len()]
    }
}

/// The fallback keepalive name when the client declared none of the
/// whitelist tools. All three reviewed clients report "no such tool" and
/// continue.
pub const KEEPALIVE_FALLBACK_TOOL: &str = "ohka_noop";

/// Claude Code's interjection lead-in, per the reviewer's measurement.
/// Stripped when parsing an interjection; unverified until the matrix
/// confirms it (§6.4).
pub const CLAUDE_INTERJECTION_PREFIX: &str = "The user sent a new message while you were working:";

/// The trailer Claude Code 2.1.30x appends after the interjected text
/// (measured on 2.1.306 in an interactive TUI, 2026-11-02):
/// `\n\nThis is how Claude Code surfaces messages the user sends mid-turn
/// — … Address the message above as you continue this turn.`
pub const CLAUDE_INTERJECTION_TRAILER: &str =
    "This is how Claude Code surfaces messages the user sends mid-turn";

/// The client-neutral tail of that trailer.
pub const INTERJECTION_TRAILER_TAIL: &str = " surfaces messages the user sends mid-turn";

/// Is this call id one of our keepalives?
pub fn is_keepalive_call_id(call_id: &str) -> bool {
    call_id.starts_with(KEEPALIVE_ID_PREFIX)
}

/// Pairing fallback for clients that rewrite call ids: a result counts as
/// a keepalive result when the call it answers was a whitelisted (or
/// fallback-named) tool with `{}` arguments that the owner never invoked.
pub fn looks_like_keepalive_pair(tool_name: &str, args: &serde_json::Value) -> bool {
    let empty_args = match args {
        serde_json::Value::Object(o) => o.is_empty(),
        // Clients echo function arguments as a JSON *string*.
        serde_json::Value::String(s) => serde_json::from_str::<serde_json::Value>(s)
            .ok()
            .and_then(|v| v.as_object().map(|o| o.is_empty()))
            .unwrap_or(false),
        _ => false,
    };
    (KEEPALIVE_TOOL_WHITELIST.contains(&tool_name) || tool_name == KEEPALIVE_FALLBACK_TOOL)
        && empty_args
}

/// Strip a client interjection lead-in; returns the bare user text.
///
/// Only text that opens with Claude's lead-in is touched; then its trailer
/// (if any) goes too, so the room sees exactly what the person typed.
pub fn strip_interjection_leadin(text: &str) -> &str {
    // Reasonix 2.47.1 `/steer` (Ctrl+Enter): one bracketed line, then the text.
    if let Some(rest) = text.trim_start().strip_prefix(REASONIX_STEER_PREFIX) {
        return rest.trim_start();
    }
    let Some(rest) = text.strip_prefix(CLAUDE_INTERJECTION_PREFIX) else {
        return text;
    };
    let rest = rest.trim_start();
    // The trailer names the client ("This is how Claude Code surfaces …",
    // ZCode 3.16: "This is how ZCode surfaces …"): match it by its tail.
    if let Some(i) = rest.rfind(CLAUDE_INTERJECTION_TRAILER) {
        return rest[..i].trim_end();
    }
    match rest.rfind(INTERJECTION_TRAILER_TAIL) {
        Some(j) => match rest[..j].rfind("This is how ") {
            Some(i) => rest[..i].trim_end(),
            None => rest,
        },
        None => rest,
    }
}

/// Reasonix 2.47.1 wraps a mid-turn `/steer` with this line (measured).
pub const REASONIX_STEER_PREFIX: &str = "[Mid-turn steer queued by the user. Do not treat this as a new task; use it only as additional guidance for the current task after completing the current step.]";

/// Prompts a client writes into the chat by itself, as a user message,
/// with no person behind them. Measured in real TUIs: Reasonix 2.47.1
/// re-asks when a turn ended with no visible text. Matched by exact
/// opening, never by a loose keyword in user text.
pub const CLIENT_AUTO_PROMPTS: &[&str] =
    &["The previous assistant response finished without any visible answer text."];

/// Is this (already unwrapped) user text a client's own auto prompt?
pub fn is_client_auto_prompt(text: &str) -> bool {
    let t = text.trim_start();
    CLIENT_AUTO_PROMPTS.iter().any(|p| t.starts_with(p))
}

#[cfg(test)]
mod interjection_tests {
    use super::*;

    #[test]
    fn keepalive_rotates_among_declared_tools() {
        let dsh: Vec<String> = ["bash", "get_goal", "job_list", "schedule_list"]
            .iter()
            .map(|s| s.to_string())
            .collect();
        let picks: Vec<_> = (0..4).map(|n| keepalive_tool_for(&dsh, n)).collect();
        assert_eq!(picks, ["get_goal", "job_list", "schedule_list", "get_goal"]);
        let zc: Vec<String> = vec!["Bash".into(), "TodoRead".into()];
        assert_eq!(keepalive_tool_for(&zc, 5), "TodoRead");
        assert_eq!(keepalive_tool_for(&[], 0), KEEPALIVE_FALLBACK_TOOL);
    }

    #[test]
    fn reasonix_steer_prefix_is_stripped() {
        let t = format!("{REASONIX_STEER_PREFIX}\n插话：暗号 X");
        assert_eq!(strip_interjection_leadin(&t), "插话：暗号 X");
    }

    #[test]
    fn reasonix_auto_nudge_is_not_speech() {
        assert!(is_client_auto_prompt("The previous assistant response finished without any visible answer text. Continue the same task now and provide a concise visible answer to the user. Do not send reasoning only."));
        assert!(!is_client_auto_prompt(
            "插话：The previous assistant response finished without any visible answer text."
        ));
    }

    #[test]
    fn strips_claude_2_1_306_leadin_and_trailer() {
        let raw = "The user sent a new message while you were working:\n插话：暗号 X\n\nThis is how Claude Code surfaces messages the user sends mid-turn — within the running turn, often alongside the next tool result, rather than as a separate conversation turn. Address the message above as you continue this turn.";
        assert_eq!(strip_interjection_leadin(raw), "插话：暗号 X");
    }

    #[test]
    fn leadin_without_trailer_and_plain_text() {
        assert_eq!(
            strip_interjection_leadin("The user sent a new message while you were working:\nhi"),
            "hi"
        );
        // A user quoting the trailer in ordinary text is left alone.
        let plain = "This is how Claude Code surfaces messages the user sends mid-turn?";
        assert_eq!(strip_interjection_leadin(plain), plain);
    }
}
