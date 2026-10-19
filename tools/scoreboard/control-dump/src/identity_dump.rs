//! The Identity kernel control (W3's panel): EKOS's own `DefaultResolver`,
//! per panel item.
//!
//! Item kinds (the panel carries no `kind` envelope field; the `input.op`
//! names the operation, so `main.rs` hands every identity item here and the
//! op dispatches):
//!
//! - `resolve`           — `{"objects": [...]}` → `DefaultResolver::new()`
//!   `.resolve(&graph)`: every merge proposal (canonical, members,
//!   confidence, `exact_name_match`) and every conflict (kind, ids). The
//!   control line also carries `is_structurally_keyed` for each `Custom`
//!   kind in the input, the registry predicate the exclusion rule reads.
//! - `name_for_similarity` — `{"objects": [...]}` → the RFC 0060/0062 name
//!   text for each object, in input order.
//!
//! Objects are `{"id", "name", "kind", "properties"?}`; the fixed ids stand
//! in for `KirObject::new`'s random ones (the panel's own substitution, W3).
//!
//! Determinism: proposals and conflicts are emitted in HashMap order inside
//! EKOS, so the control sorts them (by canonical id / first member id);
//! within one proposal `members` keeps EKOS's own order (input order), and
//! `confidence` is an order-independent max. Nothing random and no
//! timestamp is printed, so two runs are byte-identical.
//!
//! `name_for_similarity` is `pub(crate)` in EKOS (identity/src/lib.rs:609).
//! Like conflicts_dump's `kid()`, the smallest faithful copy lives below and
//! is self-checked two ways: the five direct items assert its output, and
//! every resolve item exercises EKOS's own copy inside
//! `DefaultResolver::score` — a divergence between the copies moves merge
//! decisions and fails those items' assertions.

use crate::Item;
use ekos_identity::{DefaultResolver, IdentityResolver};
use ekos_kir::custom_kinds::is_structurally_keyed;
use ekos_kir::{KirGraph, KirObject, ObjectKind};
use serde_json::{json, Value};
use uuid::Uuid;

/// EKOS's private `name_for_similarity` (identity/src/lib.rs:609), copied
/// verbatim (let-chains included — this crate is edition 2024 like EKOS).
fn name_for_similarity(obj: &KirObject) -> &str {
    if obj.kind == ObjectKind::Table
        && !obj.name.contains('/')
        && let Some((_, local)) = obj.name.rsplit_once('.')
        && !local.is_empty()
    {
        return local;
    }
    if matches!(&obj.kind, ObjectKind::Custom(k) if k == "Issue" || k == "PullRequest")
        && let Some(hash_pos) = obj.name.find('#')
        && let Some(sep_pos) = obj.name[hash_pos..].find(": ")
    {
        return &obj.name[hash_pos + sep_pos + 2..];
    }
    &obj.name
}

fn field_str(v: &Value, key: &str) -> Result<String, String> {
    v[key]
        .as_str()
        .map(str::to_string)
        .ok_or_else(|| format!("{key} is not a string"))
}

fn parse_kind(v: &Value) -> Result<ObjectKind, String> {
    serde_json::from_value(v.clone()).map_err(|e| format!("kind: {e}"))
}

fn parse_id(v: &Value) -> Result<ekos_kir::KirId, String> {
    let s = v.as_str().ok_or("id is not a string")?;
    Ok(ekos_kir::KirId(
        Uuid::parse_str(s).map_err(|e| format!("id {s}: {e}"))?,
    ))
}

fn object_of(v: &Value) -> Result<KirObject, String> {
    let mut obj = KirObject::new(field_str(v, "name")?, parse_kind(&v["kind"])?);
    obj.id = parse_id(&v["id"])?;
    if let Some(props) = v["properties"].as_object() {
        for (k, val) in props {
            obj.properties.insert(k.clone(), val.clone());
        }
    }
    Ok(obj)
}

fn objects_of(input: &Value) -> Result<Vec<KirObject>, String> {
    match input["objects"].as_array() {
        Some(rows) => rows.iter().map(object_of).collect(),
        None => Err("objects is not a list".into()),
    }
}

fn resolve(item: &Item) -> Value {
    let run = || -> Result<Value, String> {
        let objects = objects_of(&item.input)?;
        let mut graph = KirGraph::new();
        for obj in objects {
            graph.objects.push(obj);
        }
        let result = DefaultResolver::new().resolve(&graph);
        let mut proposals: Vec<Value> = result
            .proposals
            .iter()
            .map(|p| {
                json!({
                    "canonical": p.canonical_id.to_string(),
                    "canonical_name": p.canonical_name,
                    "canonical_kind": p.canonical_kind.to_string(),
                    "members": p.source_ids.iter().map(|i| i.to_string()).collect::<Vec<_>>(),
                    "confidence": p.confidence,
                    "exact_name_match": p.exact_name_match,
                })
            })
            .collect();
        proposals.sort_by(|a, b| a["canonical"].as_str().cmp(&b["canonical"].as_str()));
        let mut conflicts: Vec<Value> = result
            .conflicts
            .iter()
            .map(|c| {
                json!({
                    "kind": serde_json::to_value(&c.kind).unwrap_or(Value::Null),
                    "ids": c.ids.iter().map(|i| i.to_string()).collect::<Vec<_>>(),
                    "description": c.description,
                })
            })
            .collect();
        conflicts.sort_by(|a, b| {
            let key = |v: &Value| {
                v["ids"]
                    .as_array()
                    .and_then(|ids| ids.first())
                    .and_then(Value::as_str)
                    .unwrap_or_default()
                    .to_string()
            };
            key(a).cmp(&key(b))
        });
        // The registry predicate `candidate_blocks` reads (RFC 0135 D): for
        // every distinct Custom kind in this input, is it excluded from
        // resolution? Asserted by `a_non_keyed_custom_kind_still_resolves_normally`.
        let mut keyed = serde_json::Map::new();
        for obj in &graph.objects {
            if let ObjectKind::Custom(k) = &obj.kind {
                keyed
                    .entry(k.clone())
                    .or_insert_with(|| json!(is_structurally_keyed(k)));
            }
        }
        Ok(json!({
            "item": item.item,
            "proposals": proposals,
            "conflicts": conflicts,
            "is_structurally_keyed": Value::Object(keyed),
        }))
    };
    match run() {
        Ok(v) => v,
        Err(e) => json!({"item": item.item, "error": e}),
    }
}

fn name_for_similarity_items(item: &Item) -> Value {
    let run = || -> Result<Value, String> {
        let objects = objects_of(&item.input)?;
        Ok(json!({
            "item": item.item,
            "name_for_similarity": objects.iter().map(name_for_similarity).collect::<Vec<_>>(),
        }))
    };
    match run() {
        Ok(v) => v,
        Err(e) => json!({"item": item.item, "error": e}),
    }
}

pub fn control_for(item: &Item) -> Value {
    match item.input["op"].as_str().unwrap_or_default() {
        "resolve" => resolve(item),
        "name_for_similarity" => name_for_similarity_items(item),
        other => json!({"item": item.item, "error": format!("unknown op {other}")}),
    }
}

/// A JSON array of strings as a plain `Vec<String>`, order preserved (both
/// the control's and the expected file's lists are in input order).
fn str_list(v: &Value) -> Vec<String> {
    v.as_array()
        .map(|a| {
            a.iter()
                .map(|s| s.as_str().unwrap_or_default().to_string())
                .collect::<Vec<_>>()
        })
        .unwrap_or_default()
}

/// The expected file (`controls/identity.unit.expected.jsonl`,
/// W3's layout) carries `expect` per line: proposals as member-id sets with
/// `exact_name_match`, conflicts as `kind`+`ids`, `name_for_similarity`
/// strings, and (one item) `is_structurally_keyed_<Kind>`.
pub fn check_assert(control: &Value, assert: &Value) -> Vec<String> {
    let mut failures = Vec::new();
    let Some(pairs) = assert.as_object() else {
        return vec!["assert is not an object".into()];
    };
    for (key, want) in pairs {
        let ok = match key.as_str() {
            "proposals" => match (control["proposals"].as_array(), want.as_array()) {
                (Some(got), Some(wanted)) => {
                    if got.len() != wanted.len() {
                        false
                    } else {
                        wanted.iter().all(|w| {
                            got.iter().any(|g| {
                                str_list(&g["members"]) == str_list(&w["members"])
                                    && g["exact_name_match"] == w["exact_name_match"]
                            })
                        })
                    }
                }
                _ => false,
            },
            "conflicts" => match (control["conflicts"].as_array(), want.as_array()) {
                (Some(got), Some(wanted)) => {
                    if got.len() != wanted.len() {
                        false
                    } else {
                        wanted.iter().all(|w| {
                            got.iter().any(|g| {
                                g["kind"] == w["kind"]
                                    && str_list(&g["ids"]) == str_list(&w["ids"])
                            })
                        })
                    }
                }
                _ => false,
            },
            "name_for_similarity" => control.get("name_for_similarity") == Some(want),
            other if other.starts_with("is_structurally_keyed_") => {
                let kind = &other["is_structurally_keyed_".len()..];
                control["is_structurally_keyed"].get(kind) == Some(want)
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
