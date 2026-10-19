//! The Redact control: EKOS's own `ekos_common::redaction` on the inputs of
//! its unit tests, per panel item (panel `redact.unit`, W15's transcription).
//!
//! Three functions, three input shapes: `redact` on `input.text`,
//! `is_excluded_path` on `input.path`, `redact_json` on `input.json`; every
//! item also carries the additive-only `RedactionConfig` halves
//! (`extra_patterns` as `[label, regex source]` pairs, `extra_excluded_globs`
//! as strings — empty lists are `RedactionConfig::default()`, the tests'
//! `cfg()`).
//!
//! The control line is `{"item", "redacted"}` / `{"item", "excluded"}` /
//! `{"item", "json"}` — the exact return value, no random part anywhere, so
//! two runs are byte-identical.
//!
//! The expected file's `expect` is the transcription of what the call returns.
//! W15's memo says twelve of the twenty-six are stronger than the test (the
//! test asserted a substring, an absence, or `count == 3`): equality with the
//! whole recorded output entails every one of those weaker assertions, so the
//! check is whole-value equality, and a mismatch is a transcription error or
//! an EKOS behaviour to record — never silently loosened here.

use ekos_common::redaction::{is_excluded_path, redact, redact_json, RedactionConfig};
use serde_json::{json, Value};

use crate::Item;

/// The item's `RedactionConfig`, exactly as the test built it.
fn config_of(input: &Value) -> Result<RedactionConfig, String> {
    let mut cfg = RedactionConfig::default();
    for pair in input["extra_patterns"]
        .as_array()
        .ok_or("extra_patterns is not a list")?
    {
        let entry = pair
            .as_array()
            .ok_or("an extra pattern is not a [label, regex] pair")?;
        let label = entry
            .first()
            .and_then(Value::as_str)
            .ok_or("extra pattern label is not a string")?;
        let regex_src = entry
            .get(1)
            .and_then(Value::as_str)
            .ok_or("extra pattern regex is not a string")?;
        cfg.extra_patterns.push((label.to_string(), regex_src.to_string()));
    }
    for glob in input["extra_excluded_globs"]
        .as_array()
        .ok_or("extra_excluded_globs is not a list")?
    {
        cfg.extra_excluded_globs
            .push(glob.as_str().ok_or("an extra glob is not a string")?.to_string());
    }
    Ok(cfg)
}

pub fn control_for(item: &Item) -> Value {
    let out = || -> Result<Value, String> {
        let cfg = config_of(&item.input)?;
        if let Some(text) = item.input.get("text").and_then(Value::as_str) {
            Ok(json!({"item": item.item, "redacted": redact(text, &cfg)}))
        } else if let Some(path) = item.input.get("path").and_then(Value::as_str) {
            Ok(json!({"item": item.item, "excluded": is_excluded_path(path, &cfg)}))
        } else if let Some(doc) = item.input.get("json") {
            let mut doc = doc.clone();
            redact_json(&mut doc, &cfg);
            Ok(json!({"item": item.item, "json": doc}))
        } else {
            Err("input has none of text / path / json".into())
        }
    }();
    match out {
        Ok(v) => v,
        Err(e) => json!({"item": item.item, "error": e}),
    }
}

/// `expect` is the transcribed return value: a bool for `is_excluded_path`, a
/// string for `redact`, the redacted document for `redact_json`. Each shape is
/// checked against the control's own field for that call.
pub fn check_assert(control: &Value, expect: &Value) -> Vec<String> {
    let mut failures = Vec::new();
    match expect {
        Value::Bool(want) => match &control["excluded"] {
            Value::Bool(got) if got == want => {}
            got => failures.push(format!("excluded: control {got}, expected {want}")),
        },
        Value::String(want) => match control["redacted"].as_str() {
            Some(got) if got == want => {}
            got => failures.push(format!("redacted: control {got:?}, expected {want:?}")),
        },
        Value::Object(_) => match control.get("json") {
            Some(got) if got == expect => {}
            got => failures.push(format!("json: control {got:?}, expected {expect}")),
        },
        other => failures.push(format!("expect is not a bool/string/object: {other}")),
    }
    if let Some(err) = control.get("error").and_then(Value::as_str) {
        failures.push(format!("control errored: {err}"));
    }
    failures
}
