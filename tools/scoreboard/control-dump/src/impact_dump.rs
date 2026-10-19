//! The Impact kernel control (W11's panel): EKOS's own `Runtime` walks, per
//! panel item.
//!
//! Item input shape (no `kind` envelope field; `main.rs` hands every impact
//! item here):
//!
//! ```json
//! {"objects": [{"id", "name", "kind", "properties"?}],
//!  "relationships": [{"id", "kind", "from", "to", "properties"?}],
//!  "query": {"seed", "direction", "kinds", "max_hops", "max_objects"?}}
//! ```
//!
//! The control builds one temp SQLite ledger (the tests' own fixture shape:
//! append every object, then every relationship, through the public API;
//! fixed panel ids stand in for `new`'s random ones), wraps it in
//! `Runtime::new`, and runs the named walk:
//!
//! - `direction: "neighborhood"` — `load_neighborhood`, or
//!   `load_neighborhood_bounded` when the query carries `max_objects`. The
//!   control line prints `truncated`, the object list as `{id, name}` in
//!   walk order, the relationship count, the ordered id vecs, and
//!   `no_dangling` (the truncated-graph assert: no edge endpoint outside
//!   the object set).
//! - `direction: "Dependents"` with `kinds` exactly `DEPENDENT_KINDS` —
//!   `dependents(seed, max_hops)` (that function is `trace_impact` with
//!   exactly those kinds; the panel records them to say which call the test
//!   made), plus the trace it wraps so the hop numbers are printed too; the
//!   two are required to agree. Prints `hops`, `ids` and `names` in
//!   first-reached order.
//! - `direction: "Dependents"`/`"Dependencies"` otherwise — `trace_impact`
//!   with the query's kind list. Prints `hops` as `{hop, id, name}` (the
//!   root is never a hop; `hop` is the walk depth + 1) and the derived
//!   `ids`.
//! - `direction: "related"` — `related(seed, max_hops)` (the neighborhood
//!   walk with the root removed). Prints `ids`/`names`.
//!
//! Kind spellings are the taxonomy's own `Display`/`FromStr` ones; anything
//! unrecognized is `Custom(s)`, which is how `SameAs`, `Session`,
//! `AnchoredTo` and friends ride through. Two runs are byte-identical: the
//! BFS emission order is fixed by `relationships_for`'s scan order on an
//! identically-built ledger, and nothing random or timestamped is printed.

use std::str::FromStr;

use crate::Item;
use ekos_kir::{KirId, KirObject, KirRelationship, ObjectKind, RelationshipKind};
use ekos_ledger::Ledger;
use ekos_runtime::{ImpactDirection, RuntimeError, Runtime};
use serde_json::{json, Value};
use uuid::Uuid;

/// `Runtime::DEPENDENT_KINDS` (runtime/src/lib.rs:464) — a private const, so
/// the panel spells the list and the control recognizes it to call the named
/// `dependents()` wrapper rather than trace_impact directly.
const DEPENDENT_KINDS: [&str; 4] = ["DependsOn", "Calls", "ForeignKey", "References"];

fn field_str(v: &Value, key: &str) -> Result<String, String> {
    v[key]
        .as_str()
        .map(str::to_string)
        .ok_or_else(|| format!("{key} is not a string"))
}

fn parse_id(v: &Value) -> Result<KirId, String> {
    let s = v.as_str().ok_or("id is not a string")?;
    Ok(KirId(Uuid::parse_str(s).map_err(|e| format!("id {s}: {e}"))?))
}

fn parse_kind(v: &Value) -> Result<ObjectKind, String> {
    serde_json::from_value(v.clone()).map_err(|e| format!("kind: {e}"))
}

fn parse_rel_kind(v: &Value) -> Result<RelationshipKind, String> {
    let s = v.as_str().ok_or("kind is not a string")?;
    // FromStr's error is Infallible — anything unrecognized is Custom(s).
    Ok(RelationshipKind::from_str(s).expect("FromStr on RelationshipKind is infallible"))
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

fn relationship_of(v: &Value) -> Result<KirRelationship, String> {
    let mut rel = KirRelationship::new(
        parse_rel_kind(&v["kind"])?,
        parse_id(&v["from"])?,
        parse_id(&v["to"])?,
    );
    rel.id = parse_id(&v["id"])?;
    if let Some(props) = v["properties"].as_object() {
        for (k, val) in props {
            rel.properties.insert(k.clone(), val.clone());
        }
    }
    Ok(rel)
}

fn err_of(e: RuntimeError) -> String {
    format!("runtime: {e}")
}

/// The neighborhood walk's control line: everything the bounded and
/// unbounded tests assert, in walk order where order is the assertion and as
/// counts where the test counts.
fn neighborhood_out(item: &Item, graph: &ekos_kir::KirGraph, truncated: bool) -> Value {
    let objects: Vec<Value> = graph
        .objects
        .iter()
        .map(|o| json!({"id": o.id.to_string(), "name": o.name}))
        .collect();
    let object_ids: Vec<String> = graph.objects.iter().map(|o| o.id.to_string()).collect();
    let relationship_ids: Vec<String> = graph
        .relationships
        .iter()
        .map(|r| r.id.to_string())
        .collect();
    let kept: std::collections::HashSet<&String> = object_ids.iter().collect();
    let no_dangling = graph
        .relationships
        .iter()
        .all(|r| kept.contains(&r.from.to_string()) && kept.contains(&r.to.to_string()));
    json!({
        "item": item.item,
        "truncated": truncated,
        "objects": objects,
        "relationships": graph.relationships.len(),
        "object_ids": object_ids,
        "relationship_ids": relationship_ids,
        "no_dangling": no_dangling,
    })
}

pub fn control_for(item: &Item) -> Value {
    let run = || -> Result<Value, String> {
        let dir = std::env::temp_dir().join(format!("verekos-impact-{}", std::process::id()));
        std::fs::create_dir_all(&dir).map_err(|e| format!("tempdir: {e}"))?;
        let result = (|| {
            let ledger =
                Ledger::open(&dir.join("ledger.db")).map_err(|e| format!("open: {e}"))?;
            for spec in item.input["objects"]
                .as_array()
                .ok_or("objects is not a list")?
            {
                let obj = object_of(spec)?;
                ledger
                    .append_object(&obj)
                    .map_err(|e| format!("append_object: {e}"))?;
            }
            for spec in item.input["relationships"]
                .as_array()
                .ok_or("relationships is not a list")?
            {
                let rel = relationship_of(spec)?;
                ledger
                    .append_relationship(&rel)
                    .map_err(|e| format!("append_relationship: {e}"))?;
            }
            let query = &item.input["query"];
            let seed = parse_id(&query["seed"])?;
            let max_hops = query["max_hops"].as_u64().unwrap_or(0) as u32;
            let direction = field_str(query, "direction")?;
            let kinds: Vec<RelationshipKind> = query["kinds"]
                .as_array()
                .ok_or("kinds is not a list")?
                .iter()
                .map(parse_rel_kind)
                .collect::<Result<_, _>>()?;
            let kind_names: Vec<&str> = query["kinds"]
                .as_array()
                .ok_or("kinds is not a list")?
                .iter()
                .map(|k| k.as_str().unwrap_or_default())
                .collect();
            let runtime = Runtime::new(&ledger);
            Ok(match direction.as_str() {
                "neighborhood" => {
                    let (graph, truncated) = match query["max_objects"].as_u64() {
                        Some(n) => runtime
                            .load_neighborhood_bounded(&seed, max_hops, n as usize)
                            .map_err(err_of)?,
                        None => (
                            runtime.load_neighborhood(&seed, max_hops).map_err(err_of)?,
                            false,
                        ),
                    };
                    neighborhood_out(item, &graph, truncated)
                }
                "related" => {
                    let objects = runtime.related(&seed, max_hops).map_err(err_of)?;
                    json!({
                        "item": item.item,
                        "ids": objects.iter().map(|o| o.id.to_string()).collect::<Vec<_>>(),
                        "names": objects.iter().map(|o| o.name.clone()).collect::<Vec<_>>(),
                    })
                }
                trace @ ("Dependents" | "Dependencies") => {
                    let dir = if trace == "Dependents" {
                        ImpactDirection::Dependents
                    } else {
                        ImpactDirection::Dependencies
                    };
                    if trace == "Dependents" && kind_names == DEPENDENT_KINDS {
                        // The test called dependents() — that wrapper IS
                        // trace_impact with exactly these kinds
                        // (runtime/src/lib.rs:488). Run both and require them
                        // to agree: the ids come from the named walk, the hop
                        // numbers from the trace it wraps.
                        let objects = runtime.dependents(&seed, max_hops).map_err(err_of)?;
                        let hops = runtime
                            .trace_impact(&seed, ImpactDirection::Dependents, &kinds, max_hops)
                            .map_err(err_of)?;
                        let from_wrapper: Vec<String> =
                            objects.iter().map(|o| o.id.to_string()).collect();
                        let from_trace: Vec<String> =
                            hops.iter().map(|h| h.object.id.to_string()).collect();
                        if from_wrapper != from_trace {
                            return Err("dependents() disagrees with its own trace_impact".into());
                        }
                        json!({
                            "item": item.item,
                            "hops": hops.iter().map(|h| json!({
                                "hop": h.hop,
                                "id": h.object.id.to_string(),
                                "name": h.object.name,
                            })).collect::<Vec<_>>(),
                            "ids": from_wrapper,
                            "names": objects.iter().map(|o| o.name.clone()).collect::<Vec<_>>(),
                        })
                    } else {
                        let hops = runtime
                            .trace_impact(&seed, dir, &kinds, max_hops)
                            .map_err(err_of)?;
                        json!({
                            "item": item.item,
                            "hops": hops.iter().map(|h| json!({
                                "hop": h.hop,
                                "id": h.object.id.to_string(),
                                "name": h.object.name,
                            })).collect::<Vec<_>>(),
                            "ids": hops.iter().map(|h| h.object.id.to_string()).collect::<Vec<_>>(),
                        })
                    }
                }
                other => return Err(format!("unknown direction {other}")),
            })
        })();
        let _ = std::fs::remove_dir_all(&dir);
        result
    };
    match run() {
        Ok(v) => v,
        Err(e) => json!({"item": item.item, "error": e}),
    }
}

/// A JSON array of strings as a plain `Vec<String>`, order preserved.
fn str_list(v: &Value) -> Vec<String> {
    v.as_array()
        .map(|a| {
            a.iter()
                .map(|s| s.as_str().unwrap_or_default().to_string())
                .collect::<Vec<_>>()
        })
        .unwrap_or_default()
}

/// The expected file (W11's layout, `controls/impact.expected.jsonl`) carries
/// `expect` per line; each key is one of the tests' own assertion shapes:
/// the exact hop list, the exact id vec, ordered id vecs for the bounded
/// equality test, object sets/counts for neighborhoods, includes/excludes
/// membership, `excluded_ids` (session memory), `ids_all_equal`, and
/// `every_hop_at_most`.
pub fn check_assert(control: &Value, assert: &Value) -> Vec<String> {
    let mut failures = Vec::new();
    let Some(pairs) = assert.as_object() else {
        return vec!["assert is not an object".into()];
    };
    for (key, want) in pairs {
        let ok = match key.as_str() {
            // The exact object set: sorted-by-id element equality.
            "objects" if want.is_array() => {
                let mut got: Vec<(String, String)> = control["objects"]
                    .as_array()
                    .map(|a| {
                        a.iter()
                            .map(|o| {
                                (
                                    o["id"].as_str().unwrap_or_default().to_string(),
                                    o["name"].as_str().unwrap_or_default().to_string(),
                                )
                            })
                            .collect()
                    })
                    .unwrap_or_default();
                let mut wanted: Vec<(String, String)> = want
                    .as_array()
                    .map(|a| {
                        a.iter()
                            .map(|o| {
                                (
                                    o["id"].as_str().unwrap_or_default().to_string(),
                                    o["name"].as_str().unwrap_or_default().to_string(),
                                )
                            })
                            .collect()
                    })
                    .unwrap_or_default();
                got.sort();
                wanted.sort();
                got == wanted
            }
            // A count.
            "objects" => control["objects"].as_array().map(|a| a.len()) == want.as_u64().map(|n| n as usize),
            "relationships" => control["relationships"].as_u64() == want.as_u64(),
            "truncated" | "no_dangling" => control[key] == *want,
            // Ordered id vecs (the bounded-equality test compares two calls).
            "object_ids" | "relationship_ids" | "ids" => str_list(&control[key]) == str_list(want),
            "names" => str_list(&control[key]) == str_list(want),
            // Membership over whatever id list this walk's control line
            // carries: neighborhoods print object_ids, traces print ids.
            "includes" => {
                let have = control
                    .get("object_ids")
                    .or_else(|| control.get("ids"))
                    .map(str_list)
                    .unwrap_or_default();
                str_list(want).iter().all(|w| have.contains(w))
            }
            "excludes" | "excluded_ids" => {
                let have = control
                    .get("object_ids")
                    .or_else(|| control.get("ids"))
                    .map(str_list)
                    .unwrap_or_default();
                str_list(want).iter().all(|w| !have.contains(w))
            }
            "ids_all_equal" => {
                let want_id = want.as_str().unwrap_or_default();
                let ids = str_list(&control["ids"]);
                ids.iter().all(|i| i == want_id)
            }
            // The exact hop list: {hop, id, name} per element, in order.
            "hops" => control["hops"] == *want,
            "every_hop_at_most" => control["hops"]
                .as_array()
                .map(|hs| hs.iter().all(|h| h["hop"].as_u64().unwrap_or(u64::MAX) <= want.as_u64().unwrap_or(0)))
                .unwrap_or(false),
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
