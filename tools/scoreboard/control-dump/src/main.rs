//! `control-dump` — the VerEKOS scoreboard control (exploration 03 §2.2).
//!
//! Reads a panel JSONL (inputs only, never an answer) and writes EKOS's own
//! answer for every item, one JSON line per item, same order, to stdout. No
//! store is ever opened: each answer comes from calling the EKOS library
//! function behind the kernel directly, in the pinned checkout this crate has
//! path dependencies on.
//!
//! Usage:
//!
//!   control-dump scope     <panel.jsonl> [--expected <expected.jsonl>]
//!   control-dump conflicts <panel.jsonl> [--expected <expected.jsonl>]
//!   control-dump redact    <panel.jsonl> [--expected <expected.jsonl>]
//!   control-dump ekl       <panel.jsonl> [--expected <expected.jsonl>]
//!                           [--which ekl.parser|ekl.interpreter]
//!   control-dump ledger    <workspace-dir> [--panel <panel.jsonl>]
//!   control-dump selftest
//!
//! `--expected` reads the transcription of the EKOS unit-test assertions
//! (`{"item": ..., "expect": ..., "expect_from_test": ...}` per line) and
//! checks every assertion against the control just computed: the transcribed
//! test must reproduce, or the transcription is wrong or EKOS has drifted
//! (exploration 03 §5.4). The control JSONL is written either way; mismatches
//! go to stderr and set the exit code.

use std::collections::HashMap;
use std::path::{Path, PathBuf};

mod branch_dump;
mod conflicts_dump;
mod ekl_dump;
mod identity_dump;
mod impact_dump;
mod ledger_dump;
mod redact_dump;
mod scope_dump;
mod scope_store_dump;

/// One panel line: the envelope of exploration 03 §1.2 plus a `kind` that says
/// which shape `input` has and which control line it becomes.
pub struct Item {
    pub item: String,
    pub kind: String,
    /// The envelope's `panel` name when the file holds more than one panel
    /// (`panels/ekl/items.jsonl` is both `ekl.parser` and `ekl.interpreter`);
    /// empty for single-panel files.
    pub panel: String,
    pub input: serde_json::Value,
}

impl Item {
    fn parse(line: &str, number: usize) -> Result<Self, String> {
        let v: serde_json::Value =
            serde_json::from_str(line).map_err(|e| format!("line {number}: not JSON: {e}"))?;
        let item = v["item"]
            .as_str()
            .ok_or_else(|| format!("line {number}: no item"))?
            .to_string();
        // The scope/conflicts/store panels carry a `kind` envelope field; the
        // identity/branch/impact panels (other lanes' layouts) dispatch on
        // their input's own shape instead, so `kind` may be absent.
        let kind = v["kind"].as_str().unwrap_or_default().to_string();
        let panel = v["panel"].as_str().unwrap_or_default().to_string();
        // Most panels' inputs are objects; the EKL parser panel's input is the
        // query string itself, so any present, non-null value is accepted and
        // each dump validates its own shape.
        if v.get("input").map(|x| x.is_null()).unwrap_or(true) {
            return Err(format!("line {number}: no input"));
        }
        Ok(Item {
            item,
            kind,
            panel,
            input: v["input"].clone(),
        })
    }
}

fn read_panel(path: &Path) -> Result<Vec<Item>, String> {
    let text = std::fs::read_to_string(path)
        .map_err(|e| format!("{}: {e}", path.display()))?;
    let mut out = Vec::new();
    for (i, line) in text.lines().enumerate() {
        if line.trim().is_empty() {
            continue;
        }
        out.push(Item::parse(line, i + 1)?);
    }
    Ok(out)
}

/// One expected line per item, keyed by item id. The one shape is
/// `{"item": ..., "expect": ..., "expect_from_test": ...}` where `expect` is
/// whatever the transcribed test asserts (an object of assertion fields for
/// the scope-shaped panels, the call's whole return value for redact, an AST
/// or error field set for EKL). Two older spellings still read, until their
/// files are moved to the one shape (lane C's migration): `assert` for
/// scope/conflicts/store, and the branch panel's flat top-level fields.
fn read_expected(path: &Path) -> Result<HashMap<String, serde_json::Value>, String> {
    let text = std::fs::read_to_string(path)
        .map_err(|e| format!("{}: {e}", path.display()))?;
    let mut out = HashMap::new();
    for (i, line) in text.lines().enumerate() {
        if line.trim().is_empty() {
            continue;
        }
        let v: serde_json::Value = serde_json::from_str(line)
            .map_err(|e| format!("{} line {}: {e}", path.display(), i + 1))?;
        let item = v["item"]
            .as_str()
            .ok_or_else(|| format!("{} line {}: no item", path.display(), i + 1))?
            .to_string();
        let assert = if let Some(expect) = v.get("expect") {
            expect.clone()
        } else if let Some(assert) = v.get("assert") {
            if !assert.is_object() {
                return Err(format!("{} line {}: assert is not an object", path.display(), i + 1));
            }
            assert.clone()
        } else {
            let mut kept = serde_json::Map::new();
            for (k, val) in v.as_object().into_iter().flatten() {
                if !matches!(k.as_str(), "item" | "test" | "expect_from_test") {
                    kept.insert(k.clone(), val.clone());
                }
            }
            if kept.is_empty() {
                return Err(format!("{} line {}: no assertions found", path.display(), i + 1));
            }
            serde_json::Value::Object(kept)
        };
        out.insert(item, assert);
    }
    Ok(out)
}

/// How one panel fared against its transcribed expectations.
pub struct Report {
    pub panel: String,
    pub items: usize,
    pub agree: usize,
    pub mismatch: usize,
    pub missing: usize,
}

impl Report {
    fn failures(&self) -> usize {
        self.mismatch + self.missing
    }
}

/// Drive one panel: compute the control per item, print it, and when an
/// expected file is given check every assertion against it.
fn run_panel(
    panel_path: &Path,
    expected_path: Option<&Path>,
    panel_name: &str,
    control_for: impl Fn(&Item) -> serde_json::Value,
    check: impl Fn(&serde_json::Value, &serde_json::Value) -> Vec<String>,
) -> Result<Report, String> {
    let mut items = read_panel(panel_path)?;
    // One items file can hold several panels (`panels/ekl/items.jsonl` is both
    // ekl.parser and ekl.interpreter): when the envelopes name their panel,
    // answer only this run's own items.
    if items.iter().any(|i| !i.panel.is_empty()) {
        items.retain(|i| i.panel == panel_name);
        // A subcommand whose name matches no envelope would otherwise answer
        // nothing and "agree" on zero items.
        if items.is_empty() {
            return Err(format!("{}: no item names panel {panel_name}", panel_path.display()));
        }
    }
    let expected = match expected_path {
        Some(p) => Some(read_expected(p)?),
        None => None,
    };
    let mut report = Report {
        panel: panel_name.to_string(),
        items: items.len(),
        agree: 0,
        mismatch: 0,
        missing: 0,
    };
    let mut out = String::new();
    for item in &items {
        let control = control_for(item);
        out.push_str(
            &serde_json::to_string(&control).map_err(|e| format!("{}: {e}", item.item))?,
        );
        out.push('\n');
        if let Some(expected) = &expected {
            match expected.get(&item.item) {
                None => {
                    report.missing += 1;
                    eprintln!("{{\"item\":{:?},\"no_expected\":true}}", item.item);
                }
                Some(assert) => {
                    let failures = check(&control, assert);
                    if failures.is_empty() {
                        report.agree += 1;
                    } else {
                        report.mismatch += 1;
                        eprintln!(
                            "{{\"item\":{:?},\"control\":{},\"assert\":{},\"failed\":{}}}",
                            item.item, control, assert, failures.join("; ")
                        );
                    }
                }
            }
        }
    }
    print!("{out}");
    Ok(report)
}

fn parse_args() -> Result<(String, PathBuf, Option<PathBuf>, Option<PathBuf>, Option<String>), String> {
    let args: Vec<String> = std::env::args().collect();
    if args.len() < 3 {
        return Err(format!(
            "usage: {} <scope|conflicts|store|identity|branch|impact|redact|ekl> <panel.jsonl> \
             [--expected <expected.jsonl>] [--which <panel-name>] | ledger <workspace-dir> \
             [--panel <panel.jsonl>] | selftest",
            args.first().map(String::as_str).unwrap_or("control-dump")
        ));
    }
    let sub = args[1].clone();
    let mut panel: Option<PathBuf> = None;
    let mut expected: Option<PathBuf> = None;
    let mut panel_flag: Option<PathBuf> = None;
    let mut which: Option<String> = None;
    let mut i = 2;
    while i < args.len() {
        match args[i].as_str() {
            "--expected" => {
                i += 1;
                expected = Some(
                    args.get(i)
                        .ok_or("--expected needs a path")?
                        .clone()
                        .into(),
                );
            }
            "--panel" => {
                i += 1;
                panel_flag = Some(
                    args.get(i)
                        .ok_or("--panel needs a path")?
                        .clone()
                        .into(),
                );
            }
            "--which" => {
                i += 1;
                which = Some(
                    args.get(i)
                        .ok_or("--which needs a panel name")?
                        .clone(),
                );
            }
            other => {
                if panel.is_some() {
                    return Err(format!("unexpected argument {other}"));
                }
                panel = Some(other.into());
            }
        }
        i += 1;
    }
    Ok((
        sub,
        panel.ok_or("no panel file given")?,
        expected,
        panel_flag,
        which,
    ))
}

fn main() {
    let mut args = std::env::args();
    let me = args.next().unwrap_or_else(|| "control-dump".into());
    let sub = args.next().unwrap_or_default();
    if sub == "selftest" {
        println!(
            "{{\"kernel\":\"control-dump\",\"ekos_pin\":\"{EKOS_PIN}\",\"panels\":[\"scope.decision\",\"conflicts.unit\",\"scope.store\",\"identity.unit\",\"branch.unit\",\"impact.unit\",\"redact.unit\",\"ekl.parser\",\"ekl.interpreter\",\"ledger.versions\"],\"oracles\":0}}"
        );
        return;
    }
    let (sub, panel, expected, panel_flag, which) = match parse_args() {
        Ok(x) => x,
        Err(e) => {
            eprintln!("{me}: {e}");
            std::process::exit(2);
        }
    };
    let result = match sub.as_str() {
        // The ledger control takes a workspace directory, not a panel file:
        // the workspace IS the input (a real W18 fixture build); --panel only
        // supplies the fixture-sha provenance check.
        "ledger" => {
            if expected.is_some() {
                eprintln!("{me}: ledger takes --panel, not --expected (no transcribed assertions)");
                std::process::exit(2);
            }
            ledger_dump::run(&panel, panel_flag.as_deref())
        }
        _ if panel_flag.is_some() => {
            eprintln!("{me}: --panel is a ledger-subcommand option (did you mean a positional?)");
            std::process::exit(2);
        }
        "scope" => run_panel(
            &panel,
            expected.as_deref(),
            "scope.decision",
            scope_dump::control_for,
            scope_dump::check_assert,
        ),
        "conflicts" => run_panel(
            &panel,
            expected.as_deref(),
            "conflicts.unit",
            conflicts_dump::control_for,
            conflicts_dump::check_assert,
        ),
        "store" => run_panel(
            &panel,
            expected.as_deref(),
            "scope.store",
            scope_store_dump::control_for,
            scope_store_dump::check_assert,
        ),
        "identity" => run_panel(
            &panel,
            expected.as_deref(),
            "identity.unit",
            identity_dump::control_for,
            identity_dump::check_assert,
        ),
        "branch" => run_panel(
            &panel,
            expected.as_deref(),
            "branch.unit",
            branch_dump::control_for,
            branch_dump::check_assert,
        ),
        "impact" => run_panel(
            &panel,
            expected.as_deref(),
            "impact.unit",
            impact_dump::control_for,
            impact_dump::check_assert,
        ),
        "redact" => run_panel(
            &panel,
            expected.as_deref(),
            "redact.unit",
            redact_dump::control_for,
            redact_dump::check_assert,
        ),
        // Both EKL panels live in one items file; `--which` (or its default)
        // picks the panel, and run_panel keeps only that panel's items.
        "ekl" => {
            let name = match which.as_deref() {
                None | Some("ekl.parser") => "ekl.parser",
                Some("ekl.interpreter") => "ekl.interpreter",
                Some(other) => {
                    eprintln!("{me}: --which {other} is not ekl.parser or ekl.interpreter");
                    std::process::exit(2);
                }
            };
            match name {
                "ekl.parser" => run_panel(
                    &panel,
                    expected.as_deref(),
                    name,
                    ekl_dump::parser_control_for,
                    ekl_dump::parser_check,
                ),
                _ => run_panel(
                    &panel,
                    expected.as_deref(),
                    name,
                    ekl_dump::interpreter_control_for,
                    ekl_dump::interpreter_check,
                ),
            }
        }
        other => {
            eprintln!("{me}: unknown subcommand {other}");
            std::process::exit(2);
        }
    };
    match result {
        Ok(report) => {
            eprintln!(
                "{{\"panel\":\"{}\",\"items\":{},\"agree\":{},\"mismatch\":{},\"missing\":{}}}",
                report.panel, report.items, report.agree, report.mismatch, report.missing
            );
            if report.failures() > 0 {
                std::process::exit(1);
            }
        }
        Err(e) => {
            eprintln!("{me}: {e}");
            std::process::exit(2);
        }
    }
}

/// The EKOS commit the path dependencies point at, as recorded by whoever
/// built the control (controls/MANIFEST.json is the authority; this is the
/// selftest's reminder of what the pin was when the source was written).
const EKOS_PIN: &str = "8e3c178";
