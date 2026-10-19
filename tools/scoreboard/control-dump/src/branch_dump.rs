//! The Branch kernel control (W6's panel): EKOS's own `merge_branch`, per
//! panel item.
//!
//! Item input shape (no `kind` envelope field; `main.rs` hands every branch
//! item here):
//!
//! ```json
//! {"main":  [{"id", "name", "kind", "properties"?}],
//!  "branch": [{"id", "name", "kind", "properties"?}]}
//! ```
//!
//! The control builds two temp SQLite ledgers exactly as the transcribed
//! tests do (`temp_ledger()`, ledger/src/lib.rs:2091: a fresh dir, one
//! `Ledger::open` per side), appends each side's objects through the public
//! `append_object` (fixed panel ids standing in for `KirObject::new`'s
//! random ones; `created_at` is whatever `new` stamps — `content_signature`
//! strips it, so any stamp is signature-equivalent, W6), then calls
//! `merge_branch(&main, &branch)` and prints the report:
//!
//! ```json
//! {"item": ..., "objects_merged": N, "relationships_merged": N,
//!  "conflicts": ["<id>", ...], "main_object_count": N,
//!  "branch_object_count": N}
//! ```
//!
//! `conflicts` is sorted by id (the report's own order is the branch scan
//! order, which is deterministic, but sorting costs nothing and pins the
//! bytes). `main_object_count` is the add test's own ledger side effect
//! (`main.object_count() == 2`); it is extra information — the expected file
//! asserts only the three report fields.

use crate::Item;
use ekos_kir::{KirObject, ObjectKind};
use ekos_ledger::{Ledger, merge_branch};
use serde_json::{json, Value};
use uuid::Uuid;

fn field_str(v: &Value, key: &str) -> Result<String, String> {
    v[key]
        .as_str()
        .map(str::to_string)
        .ok_or_else(|| format!("{key} is not a string"))
}

fn parse_kind(v: &Value) -> Result<ObjectKind, String> {
    serde_json::from_value(v.clone()).map_err(|e| format!("kind: {e}"))
}

fn object_of(v: &Value) -> Result<KirObject, String> {
    let mut obj = KirObject::new(field_str(v, "name")?, parse_kind(&v["kind"])?);
    obj.id = ekos_kir::KirId(
        Uuid::parse_str(v["id"].as_str().ok_or("id is not a string")?)
            .map_err(|e| format!("id: {e}"))?,
    );
    if let Some(props) = v["properties"].as_object() {
        for (k, val) in props {
            obj.properties.insert(k.clone(), val.clone());
        }
    }
    Ok(obj)
}

/// The tests' `temp_ledger()`: one fresh dir, one `ledger.db`, one handle.
fn ledger_of(dir: &std::path::Path) -> Result<Ledger, String> {
    Ledger::open(&dir.join("ledger.db")).map_err(|e| format!("open: {e}"))
}

pub fn control_for(item: &Item) -> Value {
    let run = || -> Result<Value, String> {
        let dir = std::env::temp_dir().join(format!("verekos-branch-{}", std::process::id()));
        std::fs::create_dir_all(&dir).map_err(|e| format!("tempdir: {e}"))?;
        let result = (|| {
            let main_dir = dir.join("main");
            let branch_dir = dir.join("branch");
            std::fs::create_dir_all(&main_dir).map_err(|e| format!("tempdir: {e}"))?;
            std::fs::create_dir_all(&branch_dir).map_err(|e| format!("tempdir: {e}"))?;
            let main = ledger_of(&main_dir)?;
            let branch = ledger_of(&branch_dir)?;
            for (side, key) in [(&main, "main"), (&branch, "branch")] {
                for spec in item.input[key]
                    .as_array()
                    .ok_or_else(|| format!("{key} is not a list"))?
                {
                    let obj = object_of(spec)?;
                    side.append_object(&obj)
                        .map_err(|e| format!("append_object: {e}"))?;
                }
            }
            let report = merge_branch(&main, &branch).map_err(|e| format!("merge_branch: {e}"))?;
            let mut conflicts: Vec<String> = report
                .conflicts
                .iter()
                .map(|c| c.object_id.clone())
                .collect();
            conflicts.sort();
            Ok(json!({
                "item": item.item,
                "objects_merged": report.objects_merged,
                "relationships_merged": report.relationships_merged,
                "conflicts": conflicts,
                "main_object_count": main.object_count().map_err(|e| format!("count: {e}"))?,
                "branch_object_count": branch.object_count().map_err(|e| format!("count: {e}"))?,
            }))
        })();
        let _ = std::fs::remove_dir_all(&dir);
        result
    };
    match run() {
        Ok(v) => v,
        Err(e) => json!({"item": item.item, "error": e}),
    }
}

/// The expected file (W6's layout) carries the report fields at the top
/// level (`read_expected` strips `item`/`test`/`expect_from_test`); each is
/// compared for exact equality, `conflicts` as a sorted id list.
pub fn check_assert(control: &Value, assert: &Value) -> Vec<String> {
    let mut failures = Vec::new();
    let Some(pairs) = assert.as_object() else {
        return vec!["assert is not an object".into()];
    };
    for (key, want) in pairs {
        let ok = match key.as_str() {
            "objects_merged" | "relationships_merged" => control[key].as_u64() == want.as_u64(),
            "conflicts" => {
                let mut got: Vec<&str> = control["conflicts"]
                    .as_array()
                    .map(|a| a.iter().filter_map(Value::as_str).collect())
                    .unwrap_or_default();
                let mut wanted: Vec<&str> = want
                    .as_array()
                    .map(|a| a.iter().filter_map(Value::as_str).collect())
                    .unwrap_or_default();
                got.sort_unstable();
                wanted.sort_unstable();
                got == wanted
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
