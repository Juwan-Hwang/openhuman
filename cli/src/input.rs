//! Tool input: parse `key=value` words, type them by the tool's own JSON
//! schema, and check them before anything is sent.
//!
//! Why schema typing: guessing from the text (`content=42` → number) breaks
//! string parameters in exactly the cases an agent cannot see coming. The
//! caller already told us each parameter's type, so use it: a `string`
//! parameter keeps the text byte for byte, a `number` must parse, an
//! `array` takes JSON. Without a schema the old guess still applies.
//!
//! Why check locally: a missing or misspelled parameter used to travel to
//! the caller, wait for its validator, and come back as a "successful" tool
//! result with an error inside, a full round-trip wasted. Here it fails at
//! once with the signature and a "did you mean".

use serde_json::{Map, Value};
use std::io::Read;

/// One `key=value` word before typing.
#[derive(Debug, Clone, PartialEq)]
pub enum Raw {
    /// From `key=value`: typed by the schema.
    Text(String),
    /// From `key:=value`, `key=@file`, `key=@-`: always a string.
    Str(String),
    /// From `key:json=value`: parsed as JSON whatever the schema says.
    Json(Value),
}

/// Input of one call as the agent wrote it.
#[derive(Debug, Clone, PartialEq)]
pub enum Input {
    Pairs(Vec<(String, Raw)>),
    /// A whole JSON object: sent as is (still checked).
    Object(Map<String, Value>),
}

fn read_stdin() -> Result<String, String> {
    let mut b = String::new();
    std::io::stdin()
        .read_to_string(&mut b)
        .map_err(|e| format!("stdin: {e}"))?;
    Ok(b)
}

/// Parse the words after the tool name.
pub fn parse(args: &[String]) -> Result<Input, String> {
    if args.is_empty() {
        return Ok(Input::Pairs(Vec::new()));
    }
    if args.len() == 1 && args[0] == "-" {
        let b = read_stdin()?;
        if b.trim_start().starts_with('{') {
            return object(b.trim(), "stdin");
        }
        let lines: Vec<String> = b
            .lines()
            .filter(|l| !l.trim().is_empty())
            .map(String::from)
            .collect();
        return parse(&lines);
    }
    if args.len() == 1 && args[0].trim_start().starts_with('{') {
        return object(&args[0], "tool input");
    }
    let mut out: Vec<(String, Raw)> = Vec::new();
    for a in args {
        let Some(eq) = a.find('=') else {
            return Err(format!(
                "`{a}` is not key=value (write key=value pairs, or one JSON object)"
            ));
        };
        let (left, v) = (&a[..eq], &a[eq + 1..]);
        let (k, raw) = if let Some(k) = left.strip_suffix(':') {
            (k, Raw::Str(v.to_string()))
        } else if let Some(k) = left.strip_suffix(":json") {
            let j = serde_json::from_str(v).map_err(|e| format!("{k}:json=…: not JSON: {e}"))?;
            (k, Raw::Json(j))
        } else if v == "@-" {
            (left, Raw::Str(read_stdin()?))
        } else if let Some(p) = v
            .strip_prefix('@')
            .filter(|p| !p.is_empty() && !p.contains(' '))
        {
            match std::fs::read_to_string(p) {
                Ok(t) => (left, Raw::Str(t)),
                // `@user` mentions and the like: not a file, keep the text.
                Err(_) if !std::path::Path::new(p).exists() => (left, Raw::Text(v.to_string())),
                Err(e) => return Err(format!("{left}=@{p}: {e}")),
            }
        } else {
            (left, Raw::Text(v.to_string()))
        };
        if k.is_empty() {
            return Err(format!("`{a}`: empty parameter name"));
        }
        out.retain(|(x, _)| x != k);
        out.push((k.to_string(), raw));
    }
    Ok(Input::Pairs(out))
}

fn object(s: &str, what: &str) -> Result<Input, String> {
    match serde_json::from_str::<Value>(s) {
        Ok(Value::Object(m)) => Ok(Input::Object(m)),
        Ok(_) => Err(format!("{what} must be a JSON object")),
        Err(e) => Err(format!("{what} is not valid JSON: {e}")),
    }
}

/// Split `A k=v + B k=v` into calls.
pub fn split_batch(name: &str, rest: &[String]) -> Result<Vec<(String, Vec<String>)>, String> {
    let mut calls = vec![(name.to_string(), Vec::new())];
    let mut expect_name = false;
    for a in rest {
        if a == "+" {
            if expect_name {
                return Err("`+ +`: a tool name must follow each +".into());
            }
            expect_name = true;
            continue;
        }
        if expect_name {
            if a.contains('=') || a.starts_with('{') {
                return Err(format!("expected a tool name after +, got `{a}`"));
            }
            calls.push((a.clone(), Vec::new()));
            expect_name = false;
        } else {
            calls.last_mut().unwrap().1.push(a.clone());
        }
    }
    if expect_name {
        return Err("trailing +: a tool name must follow it".into());
    }
    Ok(calls)
}

// ── schema helpers ──

pub fn props(schema: &Value) -> Option<&Map<String, Value>> {
    schema.get("properties").and_then(|v| v.as_object())
}

pub fn required(schema: &Value) -> Vec<String> {
    schema
        .get("required")
        .and_then(|v| v.as_array())
        .map(|a| {
            a.iter()
                .filter_map(|v| v.as_str().map(String::from))
                .collect()
        })
        .unwrap_or_default()
}

/// Every JSON type a parameter accepts (`type`, `type: [..]`, anyOf/oneOf).
pub fn types(p: &Value) -> Vec<String> {
    let mut out = Vec::new();
    match p.get("type") {
        Some(Value::String(t)) => out.push(t.clone()),
        Some(Value::Array(a)) => out.extend(a.iter().filter_map(|v| v.as_str().map(String::from))),
        _ => {}
    }
    for k in ["anyOf", "oneOf"] {
        if let Some(a) = p.get(k).and_then(|v| v.as_array()) {
            for x in a {
                out.extend(types(x));
            }
        }
    }
    if out.is_empty() {
        if let Some(e) = p.get("enum").and_then(|v| v.as_array()) {
            if e.iter().all(|v| v.is_string()) {
                out.push("string".into());
            }
        }
        if p.get("const").map(|c| c.is_string()).unwrap_or(false) {
            out.push("string".into());
        }
    }
    out.retain(|t| t != "null");
    out.dedup();
    out
}

fn guess(v: &str) -> Value {
    match serde_json::from_str::<Value>(v) {
        Ok(j) if !j.is_string() => j,
        _ => Value::String(v.to_string()),
    }
}

/// Type one `key=value` text by the parameter's schema.
pub fn coerce(key: &str, v: &str, p: Option<&Value>) -> Result<Value, String> {
    let Some(p) = p else {
        return Ok(guess(v));
    };
    let ts = types(p);
    if ts.is_empty() {
        return Ok(guess(v));
    }
    let has = |t: &str| ts.iter().any(|x| x == t);
    // Strings win whenever they are allowed: the text is the value.
    if has("string") && !(ts.len() > 1 && looks_structured(v, &ts)) {
        return Ok(Value::String(v.to_string()));
    }
    if has("integer") || has("number") {
        if let Ok(n) = serde_json::from_str::<Value>(v.trim()) {
            if n.is_number() && (has("number") || n.is_i64() || n.is_u64()) {
                return Ok(n);
            }
        }
        if ts.len() == 1 {
            return Err(format!("{key}={v}: expects {} (e.g. {key}=5)", ts[0]));
        }
    }
    if has("boolean") {
        match v.trim().to_ascii_lowercase().as_str() {
            "true" | "yes" | "1" | "on" => return Ok(Value::Bool(true)),
            "false" | "no" | "0" | "off" => return Ok(Value::Bool(false)),
            _ if ts.len() == 1 => return Err(format!("{key}={v}: expects true or false")),
            _ => {}
        }
    }
    if has("array") {
        match serde_json::from_str::<Value>(v) {
            Ok(a @ Value::Array(_)) => return Ok(a),
            _ => {
                let item = p.get("items").map(types).unwrap_or_default();
                if ts.len() == 1 && (item.is_empty() || item.iter().any(|t| t == "string")) {
                    // A bare word for a list of strings: a list of one.
                    return Ok(Value::Array(vec![Value::String(v.to_string())]));
                }
                if ts.len() == 1 {
                    return Err(format!(
                        "{key}={v}: expects a JSON array (e.g. {key}='[1,2]')"
                    ));
                }
            }
        }
    }
    if has("object") {
        match serde_json::from_str::<Value>(v) {
            Ok(o @ Value::Object(_)) => return Ok(o),
            _ if ts.len() == 1 => {
                return Err(format!(
                    "{key}=…: expects a JSON object (e.g. {key}='{{\"a\":1}}')"
                ))
            }
            _ => {}
        }
    }
    Ok(guess(v))
}

fn looks_structured(v: &str, ts: &[String]) -> bool {
    let t = v.trim_start();
    (t.starts_with('[') && ts.iter().any(|x| x == "array"))
        || (t.starts_with('{') && ts.iter().any(|x| x == "object"))
}

/// Typed input, or every problem found (all at once, not one per try).
pub fn build(input: Input, schema: &Value) -> Result<Map<String, Value>, Vec<String>> {
    let pr = props(schema);
    let mut errs = Vec::new();
    let m = match input {
        Input::Object(m) => m,
        Input::Pairs(pairs) => {
            let mut m = Map::new();
            for (k, raw) in pairs {
                let key = resolve_key(&k, pr).unwrap_or(k);
                let p = pr.and_then(|pr| pr.get(&key));
                let v = match raw {
                    Raw::Str(s) => Value::String(s),
                    Raw::Json(j) => j,
                    Raw::Text(t) => match coerce(&key, &t, p) {
                        Ok(v) => v,
                        Err(e) => {
                            errs.push(e);
                            continue;
                        }
                    },
                };
                m.insert(key, v);
            }
            m
        }
    };
    if let Some(pr) = pr {
        let closed = schema.get("additionalProperties") != Some(&Value::Bool(true));
        for k in m.keys() {
            if !pr.contains_key(k) && closed {
                let names: Vec<&str> = pr.keys().map(|s| s.as_str()).collect();
                match closest(k, &names) {
                    Some(c) => errs.push(format!("unknown parameter `{k}` (did you mean `{c}`?)")),
                    None => errs.push(format!("unknown parameter `{k}`")),
                }
            }
        }
        for (k, v) in &m {
            if let Some(e) = pr
                .get(k)
                .and_then(|p| p.get("enum"))
                .and_then(|e| e.as_array())
            {
                if !e.contains(v) {
                    errs.push(format!(
                        "{k}={v}: must be one of {}",
                        Value::Array(e.clone())
                    ));
                }
            }
        }
    }
    let missing: Vec<String> = required(schema)
        .into_iter()
        .filter(|r| !m.contains_key(r))
        .collect();
    if !missing.is_empty() {
        errs.push(format!("missing required: {}", missing.join(", ")));
    }
    if errs.is_empty() {
        Ok(m)
    } else {
        Err(errs)
    }
}

/// `Command=…` for a schema that says `command`: case is not worth a failure.
fn resolve_key(k: &str, pr: Option<&Map<String, Value>>) -> Option<String> {
    let pr = pr?;
    if pr.contains_key(k) {
        return None;
    }
    let norm = |s: &str| s.to_ascii_lowercase().replace(['-', '_'], "");
    let hits: Vec<&String> = pr.keys().filter(|p| norm(p) == norm(k)).collect();
    (hits.len() == 1).then(|| hits[0].clone())
}

pub fn edit_distance(a: &str, b: &str) -> usize {
    let a: Vec<char> = a.to_lowercase().chars().collect();
    let b: Vec<char> = b.to_lowercase().chars().collect();
    let mut prev: Vec<usize> = (0..=b.len()).collect();
    for i in 1..=a.len() {
        let mut cur = vec![i; b.len() + 1];
        for j in 1..=b.len() {
            let cost = usize::from(a[i - 1] != b[j - 1]);
            cur[j] = (prev[j] + 1).min(cur[j - 1] + 1).min(prev[j - 1] + cost);
        }
        prev = cur;
    }
    prev[b.len()]
}

fn subseq(short: &str, long: &str) -> bool {
    let mut it = long.chars();
    short.len() >= 2 && short.chars().all(|c| it.any(|x| x == c))
}

/// The nearest name, when it is near enough to be what was meant.
pub fn closest<'a>(k: &str, names: &[&'a str]) -> Option<&'a str> {
    let kl = k.to_lowercase();
    let mut best: Option<(usize, &str)> = None;
    for n in names {
        let nl = n.to_lowercase();
        let d = if nl == kl {
            0
        } else if nl.contains(&kl) || kl.contains(&nl) || subseq(&kl, &nl) {
            1
        } else {
            edit_distance(k, n)
        };
        if best.map(|b| d < b.0).unwrap_or(true) {
            best = Some((d, n));
        }
    }
    best.filter(|(d, n)| *d <= (n.len().max(k.len()) / 2).max(2))
        .map(|b| b.1)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn pairs(a: &[&str]) -> Input {
        parse(&a.iter().map(|s| s.to_string()).collect::<Vec<_>>()).unwrap()
    }

    fn write_schema() -> Value {
        json!({"type":"object","properties":{
            "path":{"type":"string"},"content":{"type":"string"},
            "lines":{"type":"integer"},"force":{"type":"boolean"},
            "tags":{"type":"array","items":{"type":"string"}},
            "mode":{"type":"string","enum":["a","w"]}},
            "required":["path","content"]})
    }

    #[test]
    fn strings_stay_strings() {
        let m = build(pairs(&["path=a", "content=42"]), &write_schema()).unwrap();
        assert_eq!(m["content"], json!("42"));
        let m = build(pairs(&["path=a", "content=true"]), &write_schema()).unwrap();
        assert_eq!(m["content"], json!("true"));
        let m = build(pairs(&["path=a", "content={\"x\":1}"]), &write_schema()).unwrap();
        assert_eq!(m["content"], json!("{\"x\":1}"));
    }

    #[test]
    fn numbers_bools_arrays_by_schema() {
        let m = build(
            pairs(&["path=a", "content=b", "lines=3", "force=yes", "tags=x"]),
            &write_schema(),
        )
        .unwrap();
        assert_eq!(m["lines"], json!(3));
        assert_eq!(m["force"], json!(true));
        assert_eq!(m["tags"], json!(["x"]));
        let m = build(
            pairs(&["path=a", "content=b", "tags=[\"x\",\"y\"]"]),
            &write_schema(),
        )
        .unwrap();
        assert_eq!(m["tags"], json!(["x", "y"]));
        let e = build(
            pairs(&["path=a", "content=b", "lines=many"]),
            &write_schema(),
        )
        .unwrap_err();
        assert!(e[0].contains("expects integer"), "{e:?}");
    }

    #[test]
    fn all_problems_at_once() {
        let e = build(pairs(&["pth=a", "mode=x"]), &write_schema()).unwrap_err();
        let all = e.join("\n");
        assert!(all.contains("did you mean `path`"), "{all}");
        assert!(all.contains("must be one of"), "{all}");
        assert!(all.contains("missing required: path, content"), "{all}");
    }

    #[test]
    fn key_case_is_forgiven() {
        let m = build(pairs(&["Path=a", "CONTENT=b"]), &write_schema()).unwrap();
        assert_eq!(m["path"], json!("a"));
    }

    #[test]
    fn forced_forms() {
        let s = json!({"type":"object","properties":{"n":{"type":"integer"},"x":{}}});
        let m = build(pairs(&["n:=5", "x:json=[1]"]), &s).unwrap();
        assert_eq!(m["n"], json!("5"));
        assert_eq!(m["x"], json!([1]));
    }

    #[test]
    fn no_schema_guesses() {
        let m = build(pairs(&["a=5", "b=hi", "c=true"]), &Value::Null).unwrap();
        assert_eq!(m["a"], json!(5));
        assert_eq!(m["b"], json!("hi"));
        assert_eq!(m["c"], json!(true));
    }

    #[test]
    fn value_with_equals_and_at_mentions() {
        let m = build(pairs(&["path=a", "content=x=1 @bob"]), &write_schema()).unwrap();
        assert_eq!(m["content"], json!("x=1 @bob"));
        let m = build(
            pairs(&["path=a", "content=@nobody-file-here"]),
            &write_schema(),
        )
        .unwrap();
        assert_eq!(m["content"], json!("@nobody-file-here"));
    }

    #[test]
    fn batches() {
        let w = |a: &[&str]| a.iter().map(|s| s.to_string()).collect::<Vec<_>>();
        let b = split_batch("Read", &w(&["path=a", "+", "Bash", "command=ls"])).unwrap();
        assert_eq!(b.len(), 2);
        assert_eq!(b[1].0, "Bash");
        assert!(split_batch("Read", &w(&["path=a", "+"])).is_err());
        assert!(split_batch("Read", &w(&["+", "x=1"])).is_err());
        // `+` inside a value is just text
        let b = split_batch("Bash", &w(&["command=echo 1 + 1"])).unwrap();
        assert_eq!(b.len(), 1);
    }

    #[test]
    fn nearest() {
        assert_eq!(closest("cmd", &["command", "timeout"]), Some("command"));
        assert_eq!(closest("zzzzzz", &["command", "timeout"]), None);
        assert_eq!(closest("bash", &["Bash", "Read"]), Some("Bash"));
    }

    #[test]
    fn union_types() {
        let p = json!({"type":["string","array"]});
        assert_eq!(coerce("k", "[1]", Some(&p)).unwrap(), json!([1]));
        assert_eq!(coerce("k", "hi", Some(&p)).unwrap(), json!("hi"));
        let p = json!({"anyOf":[{"type":"integer"},{"type":"null"}]});
        assert_eq!(coerce("k", "4", Some(&p)).unwrap(), json!(4));
    }
}
