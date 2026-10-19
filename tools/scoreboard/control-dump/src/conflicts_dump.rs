//! The Conflicts kernel control: EKOS's own conflict detectors, per panel item.
//!
//! Item kinds and their control lines:
//!
//! - `normalize_type_pair` — `{"a": ..., "b": ...}` → whether EKOS's
//!   `normalize_type` maps the two spellings to one type (and both forms).
//! - `duplicate_definitions` — `{"objects": [...], "also_reversed"?: bool}` →
//!   what survives the collapse and every conflict object emitted. Each object
//!   row is the test helper's shape: `{key, name, kind, path, line, fragment?,
//!   columns, check_constraints}`; `key` is turned into the id exactly as
//!   EKOS's private `kid()` does (UUIDv5 over the URL namespace), which is what
//!   makes conflict ids stable. `also_reversed` runs the same input in reverse
//!   order and reports whether `(id, attribute, claims, signature)` survive —
//!   the permutation-invariance the EKOS test asserts.
//! - `merge_losses`       — `{"objects": [...], "proposals": [...]}` → the
//!   conflicts a merge would drop, via `MergeProposal`s built from keys.
//! - `label_mismatches`   — `{"enums": [{key, name, kind, properties}]}` →
//!   the label conflicts.
//!
//! Every field the control prints is deterministic: object and conflict ids
//! come from UUIDv5 keys, claims are sorted by the emitter, and `created_at`
//! and evidence ids are never printed. (`KirEvidence::new` mints random ids,
//! exactly as EKOS's own tests do; they do not enter any conflict id.)

use crate::Item;
use ekos_identity::MergeProposal;
use ekos_kir::{KirEvidence, KirGraph, KirId, KirObject, ObjectKind, SourceLocation};
use ekos_semantic::conflicts::{
    duplicate_definitions, label_mismatches, merge_losses, normalize_type,
};
use serde_json::{json, Map, Value};
use uuid::Uuid;

/// EKOS's private `kid()` (semantic/src/conflicts.rs): UUIDv5 over the URL
/// namespace. Reimplemented here because it is not exported; panel keys go
/// through it, so ids match what EKOS's own tests derive.
fn kid(key: &str) -> KirId {
    KirId(Uuid::new_v5(&Uuid::NAMESPACE_URL, key.as_bytes()))
}

#[derive(Clone)]
struct Row {
    key: String,
    name: String,
    kind: ObjectKind,
    path: String,
    line: Option<u32>,
    fragment: String,
    columns: Value,
    check_constraints: Value,
}

fn field_str(v: &Value, key: &str) -> Result<String, String> {
    v[key].as_str().map(str::to_string).ok_or(format!("{key} is not a string"))
}

fn parse_kind(v: &Value) -> Result<ObjectKind, String> {
    serde_json::from_value(v.clone()).map_err(|e| format!("kind: {e}"))
}

fn parse_line(v: &Value) -> Result<Option<u32>, String> {
    match &v["line"] {
        Value::Null => Ok(None),
        Value::Number(n) => n
            .as_u64()
            .and_then(|n| u32::try_from(n).ok())
            .map(Some)
            .ok_or_else(|| "line is not a u32".into()),
        _ => Err("line is not a number".into()),
    }
}

/// The test helper `table()` (conflicts.rs:611): one table object with its
/// `CREATE TABLE` evidence at a fixed line, columns, and checks.
fn table_row(v: &Value) -> Result<Row, String> {
    let name = field_str(v, "name")?;
    Ok(Row {
        key: field_str(v, "key")?,
        name: name.clone(),
        kind: parse_kind(&v["kind"])?,
        fragment: match v.get("fragment") {
            Some(Value::String(s)) => s.clone(),
            _ => format!("CREATE TABLE {name}"),
        },
        path: field_str(v, "path")?,
        line: parse_line(v)?,
        columns: v.get("columns").cloned().unwrap_or(Value::Null),
        check_constraints: v.get("check_constraints").cloned().unwrap_or(Value::Null),
    })
}

fn row_to_parts(row: &Row) -> (KirObject, KirEvidence) {
    let evidence = KirEvidence::new(
        SourceLocation {
            path: row.path.clone(),
            line: row.line,
            column: None,
        },
        row.fragment.clone(),
    );
    let mut object = KirObject::new(row.name.clone(), row.kind.clone());
    object.id = kid(&row.key);
    object.evidence.push(evidence.id);
    if !row.columns.is_null() {
        object
            .properties
            .insert("columns".into(), row.columns.clone());
    }
    if !row.check_constraints.is_null() {
        object
            .properties
            .insert("check_constraints".into(), row.check_constraints.clone());
    }
    (object, evidence)
}

fn graph_from_rows(rows: &[Row]) -> KirGraph {
    let mut graph = KirGraph::new();
    for row in rows {
        let (object, evidence) = row_to_parts(row);
        graph.objects.push(object);
        graph.evidence.push(evidence);
    }
    graph
}

fn object_summary(object: &KirObject) -> Value {
    json!({
        "id": object.id.to_string(),
        "name": object.name,
        "properties": Value::Object(
            object
                .properties
                .iter()
                .map(|(k, v)| (k.clone(), v.clone()))
                .collect::<Map<String, Value>>(),
        ),
    })
}

/// What every detector's output graph becomes: its conflict objects and
/// `Disputes` links. Only deterministic fields; no `created_at`, no evidence
/// ids, but the evidence count (one per claim).
fn conflicts_out(graph: &KirGraph) -> (Value, Value) {
    let conflicts: Vec<Value> = graph
        .objects
        .iter()
        .map(|o| {
            let prop = |k: &str| o.properties.get(k).cloned().unwrap_or(Value::Null);
            json!({
                "id": o.id.to_string(),
                "name": o.name,
                "subject_id": prop("subject_id"),
                "attribute": prop("attribute"),
                "conflict_type": prop("conflict_type"),
                "status": prop("status"),
                "chosen": prop("chosen"),
                "claims": prop("claims"),
                "signature": prop("signature"),
                "evidence_count": o.evidence.len(),
            })
        })
        .collect();
    let disputes: Vec<Value> = graph
        .relationships
        .iter()
        .map(|r| {
            json!({
                "from": r.from.to_string(),
                "to": r.to.to_string(),
                "kind": serde_json::to_value(&r.kind).unwrap_or(Value::Null),
                "attribute": r.properties.get("attribute").cloned().unwrap_or(Value::Null),
            })
        })
        .collect();
    (Value::Array(conflicts), Value::Array(disputes))
}

/// The permutation-invariance the EKOS test asserts: id, attribute, claims and
/// signature are equal across input orders (`chosen` is not — it is whoever
/// came last).
fn stable_under_permutation(a: &KirGraph, b: &KirGraph) -> bool {
    let key = |g: &KirGraph| {
        let mut rows: Vec<(String, String, String, String)> = g
            .objects
            .iter()
            .map(|o| {
                (
                    o.id.to_string(),
                    o.properties
                        .get("attribute")
                        .and_then(Value::as_str)
                        .unwrap_or_default()
                        .to_string(),
                    o.properties
                        .get("claims")
                        .map(|c| c.to_string())
                        .unwrap_or_default(),
                    o.properties
                        .get("signature")
                        .and_then(Value::as_str)
                        .unwrap_or_default()
                        .to_string(),
                )
            })
            .collect();
        rows.sort();
        rows
    };
    key(a) == key(b)
}

pub fn control_for(item: &Item) -> Value {
    match item.kind.as_str() {
        "normalize_type_pair" => normalize_pair(item),
        "duplicate_definitions" => duplicate(item),
        "merge_losses" => merge(item),
        "label_mismatches" => labels(item),
        other => json!({"item": item.item, "error": format!("unknown kind {other}")}),
    }
}

fn normalize_pair(item: &Item) -> Value {
    let run = || -> Result<Value, String> {
        let a = field_str(&item.input, "a")?;
        let b = field_str(&item.input, "b")?;
        let (na, nb) = (normalize_type(&a), normalize_type(&b));
        Ok(json!({"item": item.item, "same": na == nb, "a": na, "b": nb}))
    };
    match run() {
        Ok(v) => v,
        Err(e) => json!({"item": item.item, "error": e}),
    }
}

fn rows_of(input: &Value) -> Result<Vec<Row>, String> {
    match input["objects"].as_array() {
        Some(rows) => rows.iter().map(table_row).collect(),
        None => Err("objects is not a list".into()),
    }
}

fn duplicate(item: &Item) -> Value {
    let run = || -> Result<Value, String> {
        let rows = rows_of(&item.input)?;
        let mut graph = graph_from_rows(&rows);
        let conflicts = duplicate_definitions(&mut graph);
        let (conflicts_v, disputes_v) = conflicts_out(&conflicts);
        let remaining: Vec<Value> = graph.objects.iter().map(object_summary).collect();
        let mut out = json!({
            "item": item.item,
            "remaining": remaining,
            "conflicts": conflicts_v,
            "disputes": disputes_v,
        });
        if item.input["also_reversed"].as_bool() == Some(true) {
            let mut reversed: Vec<Row> = rows.clone();
            reversed.reverse();
            let mut graph2 = graph_from_rows(&reversed);
            let conflicts2 = duplicate_definitions(&mut graph2);
            out["permuted_stable"] = json!(stable_under_permutation(&conflicts, &conflicts2));
        }
        Ok(out)
    };
    match run() {
        Ok(v) => v,
        Err(e) => json!({"item": item.item, "error": e}),
    }
}

/// One panel proposal row → an identity `MergeProposal`, with keys resolved
/// through the same `kid()` the objects went through.
fn proposal_of(p: &Value) -> Result<MergeProposal, String> {
    let mut source_ids = Vec::new();
    for key in p["source_keys"]
        .as_array()
        .ok_or("source_keys is not a list")?
    {
        source_ids.push(kid(key.as_str().ok_or("source_keys entry is not a string")?));
    }
    Ok(MergeProposal {
        canonical_id: kid(&field_str(p, "canonical_key")?),
        canonical_name: field_str(p, "canonical_name")?,
        canonical_kind: parse_kind(&p["canonical_kind"])?,
        source_ids,
        confidence: p["confidence"].as_f64().unwrap_or(1.0) as f32,
        exact_name_match: p["exact_name_match"].as_bool().unwrap_or(false),
    })
}

fn merge(item: &Item) -> Value {    let run = || -> Result<Value, String> {
        let rows = rows_of(&item.input)?;
        let graph = graph_from_rows(&rows);
        let proposals = match item.input["proposals"].as_array() {
            Some(ps) => ps
                .iter()
                .map(proposal_of)
                .collect::<Result<Vec<MergeProposal>, String>>()?,
            None => return Err("proposals is not a list".into()),
        };
        let conflicts = merge_losses(&graph, &proposals);
        let (conflicts_v, disputes_v) = conflicts_out(&conflicts);
        Ok(json!({
            "item": item.item,
            "conflicts": conflicts_v,
            "disputes": disputes_v,
        }))
    };
    match run() {
        Ok(v) => v,
        Err(e) => json!({"item": item.item, "error": e}),
    }
}

fn labels(item: &Item) -> Value {
    let run = || -> Result<Value, String> {
        let enums = match item.input["enums"].as_array() {
            Some(es) => es
                .iter()
                .map(|e| {
                    let mut object = KirObject::new(
                        field_str(e, "name")?,
                        parse_kind(&e["kind"])?,
                    );
                    object.id = kid(&field_str(e, "key")?);
                    if let Some(props) = e["properties"].as_object() {
                        for (k, v) in props {
                            object.properties.insert(k.clone(), v.clone());
                        }
                    }
                    Ok(object)
                })
                .collect::<Result<Vec<KirObject>, String>>()?,
            None => return Err("enums is not a list".into()),
        };
        let conflicts = label_mismatches(&enums);
        let (conflicts_v, disputes_v) = conflicts_out(&conflicts);
        Ok(json!({
            "item": item.item,
            "conflicts": conflicts_v,
            "disputes": disputes_v,
        }))
    };
    match run() {
        Ok(v) => v,
        Err(e) => json!({"item": item.item, "error": e}),
    }
}

/// The expected file carries the assertions the transcribed Rust test makes
/// (`expect_from_test`, exploration 03 §5.4), checked against the control.
pub fn check_assert(control: &Value, assert: &Value) -> Vec<String> {
    let mut failures = Vec::new();
    let Some(pairs) = assert.as_object() else {
        return vec!["assert is not an object".into()];
    };
    for (key, want) in pairs {
        let ok = match key.as_str() {
            "same" => control.get("same") == Some(want),
            "remaining_count" => count_as_u64(&control["remaining"]) == want.as_u64(),
            "remaining_columns_contain" => control["remaining"].as_array().is_some_and(|rows| {
                rows.iter().any(|r| {
                    r["properties"]["columns"]
                        .to_string()
                        .contains(want.as_str().unwrap_or_default())
                })
            }),
            "conflicts_count" => count_as_u64(&control["conflicts"]) == want.as_u64(),
            "permuted_stable" => control.get("permuted_stable") == Some(want),
            "disputes_to_first_remaining" => match (
                control["disputes"].as_array(),
                control["remaining"].as_array(),
            ) {
                (Some(disputes), Some(remaining)) if disputes.len() == 1 => {
                    d_first_to(disputes) == remaining.first().and_then(|o| o["id"].as_str())
                }
                _ => false,
            }
            "first_conflict" => {
                // Appends its own, more precise, failures.
                check_conflict(&control["conflicts"], want, &mut failures);
                continue;
            }
            other => {
                failures.push(format!("unknown assert key {other}"));
                continue;
            }
        };
        if !ok {
            failures.push(format!("{key}: control does not satisfy {want}"));
        }
    }
    failures
}

fn d_first_to(disputes: &[Value]) -> Option<&str> {
    disputes.first().and_then(|d| d["to"].as_str())
}

fn count_as_u64(v: &Value) -> Option<u64> {
    v.as_array().map(|a| a.len() as u64)
}

fn check_conflict(conflicts: &Value, want: &Value, failures: &mut Vec<String>) -> bool {
    let Some(list) = conflicts.as_array() else {
        failures.push("conflicts is not a list".into());
        return false;
    };
    let Some(first) = list.first() else {
        failures.push(format!("first_conflict: no conflicts emitted, expected {want}"));
        return false;
    };
    let mut ok = true;
    for (key, value) in want.as_object().into_iter().flatten() {
        let this = match key.as_str() {
            "claims_paths" => {
                let paths: Vec<&str> = first["claims"]
                    .as_array()
                    .map(|cs| {
                        cs.iter()
                            .map(|c| c["path"].as_str().unwrap_or_default())
                            .collect()
                    })
                    .unwrap_or_default();
                paths == want_str_list(value)
            }
            "claims_count" => first["claims"].as_array().map(|a| a.len()) == want.as_u64().map(|n| n as usize),
            "evidence_count" => first["evidence_count"].as_u64() == value.as_u64(),
            other => first.get(other) == Some(value),
        };
        if !this {
            failures.push(format!("first_conflict.{key}: control {first} does not carry {value}"));
            ok = false;
        }
    }
    ok
}

fn want_str_list(v: &Value) -> Vec<&str> {
    v.as_array()
        .map(|a| a.iter().map(|s| s.as_str().unwrap_or_default()).collect())
        .unwrap_or_default()
}
