//! The Scope kernel control: EKOS's own visibility decision, per panel item.
//!
//! Item kinds and their control lines:
//!
//! - `visible`      — `{"scope": <json text>, "id"?: <uuid>, "origins"?: [...]
//!                     | "sources"?: [...], "paths"?: [...]}` → `{"visible": bool}`
//!                    (`origins` are explicit `(source, path)` pairs; `sources` +
//!                    `paths` are crossed by EKOS's own `origins()`, which is how
//!                    the pipeline derives them from an object's sources and its
//!                    evidence paths). The id defaults to a fixed constant; it
//!                    only matters for rules that name an object.
//! - `parse`        — `{"scope": <text>}` → `{"error": "parse"|"rule"}` or
//!                    `{"parsed": true}`. `ReadScope::from_json` maps JSON and
//!                    shape errors to `ScopeError::Parse` and everything its own
//!                    `check()` (i.e. `Compiled::new`) refuses to `ScopeError::Rule`.
//! - `unrestricted` — `{"scope": <text>}` → `{"unrestricted": bool}`
//! - `origins`      — `{"sources": [...], "paths": [...]}` → the crossed origins
//!
//! On any scope that fails to parse or compile, the `visible` and
//! `unrestricted` answers carry `{"error": ...}` instead.

use crate::Item;
use ekos_kir::KirId;
use ekos_ledger::scope::{Compiled, Origin, ReadScope, ScopeError};
use serde_json::{json, Value};

/// The id used where the tests pass a fresh random `KirId::new()` and the
/// decision cannot depend on it (no rule names an object).
const DEFAULT_ID: &str = "00000000-0000-5000-8000-000000000000";

fn error_kind(e: &ScopeError) -> &'static str {
    match e {
        ScopeError::Parse(_) => "parse",
        ScopeError::Rule { .. } => "rule",
    }
}

fn origin_of(v: &Value) -> Result<Origin, String> {
    let source = match &v["source"] {
        Value::Null => None,
        Value::String(s) => Some(s.clone()),
        _ => return Err("origin.source is not a string or null".into()),
    };
    let path = match &v["path"] {
        Value::Null => None,
        Value::String(s) => Some(s.clone()),
        _ => return Err("origin.path is not a string or null".into()),
    };
    Ok(Origin { source, path })
}

fn string_list(v: &Value, field: &str) -> Result<Vec<String>, String> {
    match v {
        Value::Null => Ok(Vec::new()),
        Value::Array(a) => a
            .iter()
            .map(|s| {
                s.as_str()
                    .map(str::to_string)
                    .ok_or_else(|| format!("{field} must be a list of strings"))
            })
            .collect(),
        _ => Err(format!("{field} must be a list of strings")),
    }
}

fn build_origins(input: &Value) -> Result<Vec<Origin>, String> {
    if let Value::Array(pairs) = &input["origins"] {
        return pairs.iter().map(origin_of).collect();
    }
    // The pipeline shape: the object's recorded sources crossed with its
    // evidence paths, exactly what EKOS's `origins()` does.
    let sources = string_list(&input["sources"], "sources")?;
    let paths = string_list(&input["paths"], "paths")?;
    Ok(ekos_ledger::scope::origins(&sources, &paths))
}

pub fn control_for(item: &Item) -> Value {
    match item.kind.as_str() {
        "visible" => visible(item),
        "parse" => parse(item),
        "unrestricted" => unrestricted(item),
        "origins" => origins(item),
        other => json!({"item": item.item, "error": format!("unknown kind {other}")}),
    }
}

fn scope_text(item: &Item) -> Result<String, String> {
    item.input["scope"]
        .as_str()
        .map(str::to_string)
        .ok_or_else(|| "input.scope is not a string".into())
}

fn visible(item: &Item) -> Value {
    let run = || -> Result<Value, String> {
        let text = scope_text(item)?;
        let id: KirId = match item.input["id"].as_str() {
            None => DEFAULT_ID.parse().map_err(|e| format!("default id: {e}"))?,
            Some(s) => s.parse().map_err(|e| format!("id {s}: {e}"))?,
        };
        let origins = build_origins(&item.input)?;
        let scope = ReadScope::from_json(&text).map_err(|e| error_kind(&e).to_string())?;
        let compiled = Compiled::new(&scope).map_err(|e| error_kind(&e).to_string())?;
        Ok(json!({"item": item.item, "visible": compiled.visible(&id, &origins)}))
    };
    match run() {
        Ok(v) => v,
        // A scope that fails to parse is itself an answer (exploration 03 §1.5).
        Err(kind) if kind == "parse" || kind == "rule" => {
            json!({"item": item.item, "error": kind})
        }
        Err(e) => json!({"item": item.item, "error": e}),
    }
}

fn parse(item: &Item) -> Value {
    let text = match scope_text(item) {
        Ok(t) => t,
        Err(e) => return json!({"item": item.item, "error": e}),
    };
    match ReadScope::from_json(&text) {
        Err(e) => json!({"item": item.item, "error": error_kind(&e)}),
        Ok(_) => json!({"item": item.item, "parsed": true}),
    }
}

fn unrestricted(item: &Item) -> Value {
    let text = match scope_text(item) {
        Ok(t) => t,
        Err(e) => return json!({"item": item.item, "error": e}),
    };
    match ReadScope::from_json(&text) {
        Ok(scope) => json!({"item": item.item, "unrestricted": scope.is_unrestricted()}),
        Err(e) => json!({"item": item.item, "error": error_kind(&e)}),
    }
}

fn origins(item: &Item) -> Value {
    let run = || -> Result<Value, String> {
        let sources = string_list(&item.input["sources"], "sources")?;
        let paths = string_list(&item.input["paths"], "paths")?;
        let crossed = ekos_ledger::scope::origins(&sources, &paths);
        let list: Vec<Value> = crossed
            .iter()
            .map(|o| json!({"source": o.source, "path": o.path}))
            .collect();
        Ok(json!({"item": item.item, "origins": list}))
    };
    match run() {
        Ok(v) => v,
        Err(e) => json!({"item": item.item, "error": e}),
    }
}

/// The expected file carries the exact answer the transcribed Rust test
/// asserts; every key it names must equal the control's.
pub fn check_assert(control: &Value, assert: &Value) -> Vec<String> {
    let mut failures = Vec::new();
    if let Some(pairs) = assert.as_object() {
        for (key, want) in pairs {
            match control.get(key) {
                Some(got) if got == want => {}
                Some(got) => failures.push(format!("{key}: control {got} != expected {want}")),
                None => failures.push(format!("{key}: control has no such key")),
            }
        }
    } else {
        failures.push("assert is not an object".into());
    }
    failures
}
