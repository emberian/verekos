//! The EKL controls (W16's panels `ekl.parser` and `ekl.interpreter`): EKOS's
//! own `ekos_ekl::ekl_parse` and `EklInterpreter::execute`, per panel item.
//!
//! **Parser** (input: the query string). The control line is
//! `{"item", "panics", "ast": {...}}` or `{"item", "panics", "error",
//! "position"}`; `panics` comes from `catch_unwind` around the call (the fuzz
//! test's only assertion is "never panics"). The AST is printed whole, every
//! field, in a fixed spelling: `op` and `entity` and `direction` as the Rust
//! variant names, a literal as `{"str": s}` or `{"num": n}`, `as_of` as RFC
//! 3339 with `Z`.
//!
//! **Interpreter** (input: `{objects, relationships, query}` plus, for three
//! `AS OF` tests, a `clock` note and `later_objects`). The control builds a
//! temp SQLite ledger exactly as the tests' fixtures do (append every object,
//! then every relationship, through the public API, with the panel's fixed ids
//! standing in for `new`'s random ones), wraps it in `Runtime::new`, parses
//! and executes. Rows are printed in result order with keys sorted.
//!
//! The `AS OF` placeholders (`{before}`, `{now}`, `{mid}`) are filled from the
//! wall clock at the same moment the Rust test fills them (after the fixture's
//! appends; `{mid}` between two 5 ms sleeps, before `later_objects` is
//! appended). The ledger stamps `written_at` with the wall clock and offers no
//! public way to fix it, so a fixed clock is not possible here; the control
//! line never prints a timestamp, so two runs are still byte-identical, and
//! the result depends on the clock exactly as the test's does. For the `{mid}`
//! item the control also prints the test's second, non-EKL assertion:
//! whether `reconstruct_state_at(orders, mid)` shows `row_count`.

use std::panic::{AssertUnwindSafe, catch_unwind};
use std::str::FromStr;

use chrono::{Duration, SecondsFormat, Utc};
use ekos_ekl::{EklAst, EklError, EklInterpreter, Entity, Literal, Op, Order, ekl_parse};
use ekos_kir::{KirId, KirObject, KirRelationship, ObjectKind, RelationshipKind};
use ekos_ledger::Ledger;
use ekos_runtime::Runtime;
use serde_json::{Map, Value, json};
use uuid::Uuid;

use crate::Item;

fn op_name(op: Op) -> &'static str {
    match op {
        Op::Eq => "Eq",
        Op::Ne => "Ne",
        Op::Gt => "Gt",
        Op::Lt => "Lt",
        Op::Ge => "Ge",
        Op::Le => "Le",
        Op::Contains => "Contains",
    }
}

fn ast_json(ast: &EklAst) -> Value {
    let predicates: Vec<Value> = ast
        .predicates
        .iter()
        .map(|p| {
            let value = match &p.value {
                Literal::Str(s) => json!({"str": s}),
                Literal::Num(n) => json!({"num": n}),
            };
            json!({"field": p.field, "op": op_name(p.op), "value": value})
        })
        .collect();
    json!({
        "entity": match ast.entity { Entity::Object => "Object", Entity::Relationship => "Relationship" },
        "predicates": predicates,
        "from": ast.from,
        "semantic": ast.semantic,
        "via": ast.via,
        "depth": ast.depth,
        "returns": ast.returns,
        "order_by": ast.order_by.as_ref().map(|(f, o)| json!({
            "field": f,
            "direction": match o { Order::Asc => "Asc", Order::Desc => "Desc" },
        })),
        "limit": ast.limit,
        "as_of": ast.as_of.map(|t| t.to_rfc3339_opts(SecondsFormat::AutoSi, true)),
        "count": ast.count,
        "group_by": ast.group_by,
    })
}

pub fn parser_control_for(item: &Item) -> Value {
    let Some(query) = item.input.as_str() else {
        return json!({"item": item.item, "error_input": "input is not a query string"});
    };
    let query = query.to_string();
    // The fuzz test asserts only that parse never panics; silence the default
    // hook so a panic would show in the control line, not as stderr noise.
    let prev = std::panic::take_hook();
    std::panic::set_hook(Box::new(|_| {}));
    let outcome = catch_unwind(AssertUnwindSafe(|| ekl_parse(&query)));
    std::panic::set_hook(prev);
    match outcome {
        Err(_) => json!({"item": item.item, "panics": true}),
        Ok(Ok(ast)) => json!({"item": item.item, "panics": false, "ast": ast_json(&ast)}),
        Ok(Err(e)) => json!({
            "item": item.item, "panics": false,
            "error": e.message, "position": e.position,
        }),
    }
}

/// The parser expectations W16 transcribed. Field keys compare against the
/// printed AST; three derived keys (`predicates_len`, `first_op`,
/// `second_op`) read the predicate list. `error`: the test asserts only
/// `is_err()`; W16 recorded the message, and the check requires the
/// message to *start with* it (one test asserts only a substring, recorded as
/// `message_contains`). `panics`: compared directly.
pub fn parser_check(control: &Value, expect: &Value) -> Vec<String> {
    let mut failures = Vec::new();
    let Some(want) = expect.as_object() else {
        return vec![format!("expect is not an object: {expect}")];
    };
    if control.get("error_input").is_some() {
        return vec![format!("bad input: {control}")];
    }
    let ast = &control["ast"];
    for (key, val) in want {
        let ok = match key.as_str() {
            "panics" => control["panics"] == *val,
            "error" => match (control["error"].as_str(), val.as_str()) {
                (Some(got), Some(w)) => got.starts_with(w),
                _ => false,
            },
            "message_contains" => match (control["error"].as_str(), val.as_str()) {
                (Some(got), Some(w)) => got.contains(w),
                _ => false,
            },
            "predicates_len" => ast["predicates"].as_array().map(|a| a.len() as u64) == val.as_u64(),
            "first_op" => ast["predicates"][0]["op"] == *val,
            "second_op" => ast["predicates"][1]["op"] == *val,
            field => !ast.is_null() && ast.get(field) == Some(val),
        };
        if !ok {
            failures.push(format!("{key}: expected {val}, control {control}"));
        }
    }
    failures
}

// ── interpreter ──────────────────────────────────────────────────────────────

fn parse_id(v: &Value) -> Result<KirId, String> {
    let s = v.as_str().ok_or("id is not a string")?;
    Ok(KirId(Uuid::parse_str(s).map_err(|e| format!("id {s}: {e}"))?))
}

fn object_of(v: &Value) -> Result<KirObject, String> {
    let name = v["name"].as_str().ok_or("name is not a string")?;
    let kind: ObjectKind =
        serde_json::from_value(v["kind"].clone()).map_err(|e| format!("kind: {e}"))?;
    let mut obj = KirObject::new(name, kind);
    obj.id = parse_id(&v["id"])?;
    for (k, val) in v["properties"].as_object().into_iter().flatten() {
        obj.properties.insert(k.clone(), val.clone());
    }
    Ok(obj)
}

fn relationship_of(v: &Value) -> Result<KirRelationship, String> {
    let kind = RelationshipKind::from_str(v["kind"].as_str().ok_or("kind is not a string")?)
        .expect("FromStr on RelationshipKind is infallible");
    let mut rel = KirRelationship::new(kind, parse_id(&v["from"])?, parse_id(&v["to"])?);
    rel.id = parse_id(&v["id"])?;
    for (k, val) in v["properties"].as_object().into_iter().flatten() {
        rel.properties.insert(k.clone(), val.clone());
    }
    Ok(rel)
}

fn error_json(e: &EklError) -> Value {
    let variant = match e {
        EklError::Runtime(_) => "Runtime",
        EklError::AnchorNotFound(_) => "AnchorNotFound",
        EklError::AsOfWithFromUnsupported => "AsOfWithFromUnsupported",
        EklError::UnknownField { .. } => "UnknownField",
    };
    let mut out = json!({"error": variant, "message": e.to_string()});
    if let EklError::UnknownField { field, .. } = e {
        out["field"] = json!(field);
    }
    out
}

fn interpret(item: &Item, dir: &std::path::Path) -> Result<Value, String> {
    let ledger = Ledger::open(&dir.join("ledger.db")).map_err(|e| format!("open: {e}"))?;
    for spec in item.input["objects"].as_array().ok_or("objects is not a list")? {
        ledger.append_object(&object_of(spec)?).map_err(|e| format!("append_object: {e}"))?;
    }
    for spec in item.input["relationships"].as_array().ok_or("relationships is not a list")? {
        ledger
            .append_relationship(&relationship_of(spec)?)
            .map_err(|e| format!("append_relationship: {e}"))?;
    }
    let mut query = item.input["query"].as_str().ok_or("query is not a string")?.to_string();
    let mut mid = None;
    if query.contains("{before}") {
        let before = Utc::now() - Duration::seconds(60);
        query = query.replace("{before}", &before.to_rfc3339());
    }
    if query.contains("{now}") {
        query = query.replace("{now}", &Utc::now().to_rfc3339());
    }
    if query.contains("{mid}") {
        std::thread::sleep(std::time::Duration::from_millis(5));
        let m = Utc::now();
        std::thread::sleep(std::time::Duration::from_millis(5));
        for spec in item.input["later_objects"].as_array().ok_or("later_objects is not a list")? {
            ledger.append_object(&object_of(spec)?).map_err(|e| format!("append_object: {e}"))?;
        }
        query = query.replace("{mid}", &m.to_rfc3339());
        mid = Some(m);
    }
    let runtime = Runtime::new(&ledger);
    let ast = ekl_parse(&query).map_err(|e| format!("parse: {e}"))?;
    let mut out = match EklInterpreter::new(&runtime).execute(&ast) {
        Err(e) => error_json(&e),
        Ok(result) => {
            let rows: Vec<Value> = result
                .rows
                .iter()
                .map(|row| {
                    let mut keys: Vec<&String> = row.keys().collect();
                    keys.sort();
                    let mut m = Map::new();
                    for k in keys {
                        m.insert(k.clone(), row[k].clone());
                    }
                    Value::Object(m)
                })
                .collect();
            json!({"row_count": rows.len(), "rows": rows})
        }
    };
    if let Some(m) = mid {
        // The test's second assertion, outside EklResult.
        let first = &item.input["objects"][0];
        let id = parse_id(&first["id"])?;
        let state = runtime.reconstruct_state_at(&id, m).map_err(|e| format!("reconstruct: {e}"))?;
        out["history_has_row_count"] =
            json!(state.map(|s| s.object.properties.contains_key("row_count")));
    }
    Ok(out)
}

pub fn interpreter_control_for(item: &Item) -> Value {
    let dir = std::env::temp_dir().join(format!(
        "verekos-ekl-{}-{}",
        std::process::id(),
        item.item.replace(['/', ' '], "_")
    ));
    let _ = std::fs::remove_dir_all(&dir);
    let result = std::fs::create_dir_all(&dir)
        .map_err(|e| format!("tempdir: {e}"))
        .and_then(|_| interpret(item, &dir));
    let _ = std::fs::remove_dir_all(&dir);
    let mut line = match result {
        Ok(v) => v,
        Err(e) => json!({"error_input": e}),
    };
    line["item"] = json!(item.item);
    line
}

fn row_matches(row: &Value, want: &Value) -> bool {
    want.as_object()
        .map(|w| w.iter().all(|(k, v)| row.get(k) == Some(v)))
        .unwrap_or(false)
}

/// The interpreter expectations W16 transcribed. `row_count`; `rows` (row
/// *i* has at least these key/value pairs: "other keys are not asserted");
/// `row0_has_keys`, `row0_len`; `names_exclude` (no row has that name);
/// `groups` (each listed row appears, any order: the test finds rows by
/// key); `error` (the `EklError` variant), `field`, `message_contains` (a
/// substring of the error's Display).
pub fn interpreter_check(control: &Value, expect: &Value) -> Vec<String> {
    let mut failures = Vec::new();
    let Some(want) = expect.as_object() else {
        return vec![format!("expect is not an object: {expect}")];
    };
    if let Some(e) = control.get("error_input") {
        return vec![format!("control could not run: {e}")];
    }
    let rows = control["rows"].as_array().cloned().unwrap_or_default();
    for (key, val) in want {
        let ok = match key.as_str() {
            "row_count" => control["row_count"] == *val,
            "rows" => val.as_array().is_some_and(|ws| {
                ws.iter().enumerate().all(|(i, w)| rows.get(i).is_some_and(|r| row_matches(r, w)))
            }),
            "row0_has_keys" => val.as_array().is_some_and(|ks| {
                ks.iter().all(|k| k.as_str().is_some_and(|k| rows.first().is_some_and(|r| r.get(k).is_some())))
            }),
            "row0_len" => rows.first().and_then(Value::as_object).map(|r| r.len() as u64) == val.as_u64(),
            "names_exclude" => val.as_array().is_some_and(|ns| {
                !rows.is_empty() && rows.iter().all(|r| !ns.contains(&r["name"]))
            }),
            "groups" => val.as_array().is_some_and(|gs| {
                gs.iter().all(|g| rows.iter().any(|r| row_matches(r, g)))
            }),
            "error" => control["error"] == *val,
            "field" => control["field"] == *val,
            "message_contains" => match (control["message"].as_str(), val.as_str()) {
                (Some(m), Some(w)) => m.contains(w),
                _ => false,
            },
            other => {
                failures.push(format!("unknown expectation key {other}"));
                continue;
            }
        };
        if !ok {
            failures.push(format!("{key}: expected {val}, control {control}"));
        }
    }
    failures
}
