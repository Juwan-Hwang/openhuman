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
pub const KEEPALIVE_TOOL_WHITELIST: &[&str] = &["ListAgents", "get_goal", "list_bash"];

/// The fallback keepalive name when the client declared none of the
/// whitelist tools. All three reviewed clients report "no such tool" and
/// continue.
pub const KEEPALIVE_FALLBACK_TOOL: &str = "ohka_noop";

/// Claude Code's interjection lead-in, per the reviewer's measurement.
/// Stripped when parsing an interjection; unverified until the matrix
/// confirms it (§6.4).
pub const CLAUDE_INTERJECTION_PREFIX: &str = "The user sent a new message while you were working:";

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
pub fn strip_interjection_leadin(text: &str) -> &str {
    text.strip_prefix(CLAUDE_INTERJECTION_PREFIX)
        .map(str::trim_start)
        .unwrap_or(text)
}
