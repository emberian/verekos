//! The Ledger versions control: EKOS's own `FactLedger`, opened READ-ONLY on
//! a real fixture workspace (W18's `var/w18/<name>/ws`, or W20's copy for the
//! EKOS#10 reproduction), answering one panel item per invocation.
//!
//! What the control line pins, per object (sorted by id): id, kind, name, the
//! number of versions (`object_history` length), a locally recomputed content
//! signature of every version (current one called out), and every version's
//! evidence id list — the exact field EKOS#10 moves. Plus the workspace
//! totals (`object_count`, `relationship_count`, `evidence_count`,
//! `entry_count`) and `diff(epoch, now)` as a sorted id list (design §1 rows
//! P1, P2, P4).
//!
//! `content_signature` is `pub(crate)` in ekos-ledger (lib.rs:47-53): SHA-256
//! of canonical JSON with the top-level `created_at` removed. This dump
//! recomputes it locally — the volatile-field strip is three lines here, the
//! canonicalization and hash are EKOS's own exported `ArtifactId::compute`,
//! so only the strip could drift — and self-checks the recomputation two
//! ways, both printed on the control line:
//!
//! * `adjacent_versions_differ`: FactLedger appends a version only when the
//!   signature moves (fact_ledger.rs:722-724), so two adjacent versions of
//!   one object with equal recomputed signatures means the recomputation is
//!   wrong, not the ledger.
//! * `current_is_last_history`: `get_object`'s signature must equal the last
//!   history version's.
//!
//! Usage: `control-dump ledger <workspace-dir> [--panel <panel.jsonl>]`.
//! The positional is the workspace directory (its `.ekos/ledger/facts` is
//! exactly where the CLI's `facts_dir` points, store.rs:42-44); `--panel`
//! names the W18 fixture panel whose `fixture_sha256` the workspace's own
//! `schemas/*.sql` copy must still hash to — the control's provenance check.
//! Nothing is ever written: the read-only open takes no locks and creates no
//! segments (fact_ledger.rs:500-520).

use std::path::Path;

use chrono::{DateTime, Utc};
use ekos_artifact::ArtifactId;
use ekos_ledger::fact_ledger::FactLedger;
use ekos_kir::KirObject;
use serde_json::{json, Value};

use crate::{Item, Report};

/// The local half of ekos-ledger's `pub(crate) content_signature`
/// (lib.rs:47-53): strip the volatile top-level `created_at`, then hash via
/// EKOS's own canonical-JSON `ArtifactId::compute`.
fn content_signature_of(obj: &KirObject) -> Result<String, String> {
    let mut payload = serde_json::to_value(obj).map_err(|e| format!("serialize object: {e}"))?;
    if let Value::Object(ref mut map) = payload {
        map.remove("created_at");
    }
    Ok(ArtifactId::compute(&payload).as_str().to_string())
}

/// One object row of the control line.
fn object_row(ledger: &FactLedger, obj: &KirObject) -> Result<Value, String> {
    let id = obj.id.0.to_string();
    let history = ledger
        .object_history(&obj.id)
        .map_err(|e| format!("object_history({id}): {e}"))?;
    if history.is_empty() {
        return Err(format!("object {id} is current but has no history"));
    }
    let kind = serde_json::to_value(obj)
        .map_err(|e| format!("serialize object: {e}"))?["kind"]
        .as_str()
        .unwrap_or("?")
        .to_string();
    let mut version_signatures = Vec::with_capacity(history.len());
    let mut version_evidence = Vec::with_capacity(history.len());
    for version in &history {
        version_signatures.push(content_signature_of(version)?);
        version_evidence.push(
            version
                .evidence
                .iter()
                .map(|ev| ev.0.to_string())
                .collect::<Vec<String>>(),
        );
    }
    let current = history.last().expect("checked non-empty above");
    Ok(json!({
        "id": id,
        "kind": kind,
        "name": current.name,
        "versions": history.len(),
        "signature": version_signatures.last().cloned().expect("non-empty"),
        "evidence": current.evidence.iter().map(|ev| ev.0.to_string())
            .collect::<Vec<String>>(),
        "version_signatures": version_signatures,
        "version_evidence": version_evidence,
    }))
}

/// Dump one workspace. Prints exactly one control line to stdout and returns
/// the report; any failure is an `Err` (nothing printed, exit 2 in main).
pub fn run(workspace: &Path, panel: Option<&Path>) -> Result<Report, String> {
    let workspace = workspace.canonicalize().map_err(|e| format!("workspace: {e}"))?;
    let facts = workspace.join(".ekos").join("ledger").join("facts");
    if !facts.join("manifest.json").is_file() {
        return Err(format!(
            "{}: no fact-engine manifest — not a built workspace (store.rs::uses_fact_engine)",
            facts.display()
        ));
    }

    // The fixture: the single .sql under schemas/ (W18's layout). Its stem is
    // the item id; its bytes must still hash to the panel's fixture_sha256.
    let mut sqls: Vec<_> = std::fs::read_dir(workspace.join("schemas"))
        .map_err(|e| format!("read schemas/: {e}"))?
        .filter_map(|e| e.ok().map(|e| e.path()))
        .filter(|p| p.extension().is_some_and(|x| x == "sql"))
        .collect();
    sqls.sort();
    let fixture = {
        let path = sqls.pop().ok_or("schemas/ holds no .sql fixture")?;
        if !sqls.is_empty() {
            return Err("schemas/ holds more than one .sql; item id would be ambiguous".into());
        }
        path
    };
    let item_id = fixture
        .file_stem()
        .and_then(|s| s.to_str())
        .ok_or("fixture stem is not UTF-8")?
        .to_string();
    let fixture_sha = sha256_file(&fixture)?;

    let mut panel_entry: Option<Item> = None;
    if let Some(path) = panel {
        for item in crate::read_panel(path)? {
            if item.item == item_id {
                panel_entry = Some(item);
            }
        }
    }
    let mut fixture_matches_panel = Value::Null;
    if let Some(item) = &panel_entry {
        let want = item.input["fixture_sha256"]
            .as_str()
            .ok_or("panel item has no input.fixture_sha256")?;
        fixture_matches_panel = Value::Bool(want == fixture_sha);
        if want != fixture_sha {
            return Err(format!(
                "fixture {fixture_sha} does not hash to the panel's {want} — \
                 the workspace is not the panel's input"
            ));
        }
    }

    let ledger = FactLedger::open_read_only(&facts)
        .map_err(|e| format!("open_read_only({}): {e}", facts.display()))?;

    let mut objects = ledger
        .all_objects()
        .map_err(|e| format!("all_objects: {e}"))?;
    objects.sort_by(|a, b| a.id.0.to_string().cmp(&b.id.0.to_string()));

    let mut rows = Vec::with_capacity(objects.len());
    let mut adjacent_differ = true;
    let mut current_is_last = true;
    for obj in &objects {
        let row = object_row(&ledger, obj)?;
        // Self-check 1: a version exists only because its signature differed
        // from the previous one's, so equal adjacent recomputed signatures
        // falsify the recomputation.
        let sigs = row["version_signatures"].as_array().expect("just built");
        for pair in sigs.windows(2) {
            if pair[0] == pair[1] {
                adjacent_differ = false;
            }
        }
        // Self-check 2: the current view must be the last history version.
        let current = ledger
            .get_object(&obj.id)
            .map_err(|e| format!("get_object({}): {e}", obj.id.0))?;
        match current {
            Some(o) if content_signature_of(&o)? == row["signature"].as_str().expect("string") => {}
            Some(_) => current_is_last = false,
            None => return Err(format!("object {} vanished mid-dump", obj.id.0)),
        }
        rows.push(row);
    }

    let epoch = DateTime::<Utc>::from_timestamp(0, 0).ok_or("the epoch is not a timestamp")?;
    let d = ledger.diff(epoch, Utc::now()).map_err(|e| format!("diff: {e}"))?;
    let mut touched = d.touched;
    touched.sort();
    let mut added: Vec<i64> = d.added.iter().map(|e| e.0).collect();
    added.sort_unstable();

    let line = json!({
        "item": item_id,
        "workspace": workspace.display().to_string(),
        "fixture": {"name": fixture.file_name().and_then(|s| s.to_str()).unwrap_or("?"),
                    "sha256": fixture_sha,
                    "matches_panel": fixture_matches_panel},
        "totals": {
            "objects": ledger.object_count().map_err(|e| format!("object_count: {e}"))?,
            "relationships": ledger.relationship_count()
                .map_err(|e| format!("relationship_count: {e}"))?,
            "evidence": ledger.evidence_count().map_err(|e| format!("evidence_count: {e}"))?,
            "entries": ledger.entry_count().map_err(|e| format!("entry_count: {e}"))?,
        },
        "objects": rows,
        "diff_epoch_now": {"touched": touched, "added": added, "unchanged": d.unchanged},
        "selfcheck": {
            "adjacent_versions_differ": adjacent_differ,
            "current_is_last_history": current_is_last,
            "content_signature": "local: strip created_at + ekos_artifact::ArtifactId::compute",
        },
    });
    if !adjacent_differ || !current_is_last {
        return Err(format!(
            "signature recomputation failed its self-check: \
             adjacent_versions_differ={adjacent_differ} \
             current_is_last_history={current_is_last}"
        ));
    }
    println!(
        "{}",
        serde_json::to_string(&line).map_err(|e| format!("serialize control line: {e}"))?
    );
    // No transcribed assertions exist for this control (the workspace IS the
    // expectation source), so `agree` counts items that printed without
    // failure — the same agree==items-or-exit-nonzero contract as the rest.
    Ok(Report {
        panel: "ledger.versions".into(),
        items: 1,
        agree: 1,
        mismatch: 0,
        missing: 0,
    })
}

fn sha256_file(path: &Path) -> Result<String, String> {
    use sha2::{Digest, Sha256};
    let bytes = std::fs::read(path).map_err(|e| format!("{}: {e}", path.display()))?;
    let mut hasher = Sha256::new();
    hasher.update(&bytes);
    Ok(hex::encode(hasher.finalize()))
}
