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
//!   control-dump selftest
//!
//! `--expected` reads the transcription of the EKOS unit-test assertions
//! (`{"item": ..., "assert": {...}}` per line) and checks every assertion
//! against the control just computed: the transcribed test must reproduce, or
//! the transcription is wrong or EKOS has drifted (exploration 03 §5.4). The
//! control JSONL is written either way; mismatches go to stderr and set the
//! exit code.

use std::collections::HashMap;
use std::path::{Path, PathBuf};

mod conflicts_dump;
mod scope_dump;

/// One panel line: the envelope of exploration 03 §1.2 plus a `kind` that says
/// which shape `input` has and which control line it becomes.
pub struct Item {
    pub item: String,
    pub kind: String,
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
        let kind = v["kind"]
            .as_str()
            .ok_or_else(|| format!("line {number}: no kind"))?
            .to_string();
        if !v["input"].is_object() {
            return Err(format!("line {number}: input is not an object"));
        }
        Ok(Item {
            item,
            kind,
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

/// `{"item": ..., "assert": {...}}` per line, keyed by item id.
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
        if !v["assert"].is_object() {
            return Err(format!("{} line {i}: assert is not an object", path.display()));
        }
        out.insert(item, v["assert"].clone());
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
    let items = read_panel(panel_path)?;
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

fn parse_args() -> Result<(String, PathBuf, Option<PathBuf>), String> {
    let args: Vec<String> = std::env::args().collect();
    if args.len() < 3 {
        return Err(format!(
            "usage: {} <scope|conflicts> <panel.jsonl> [--expected <expected.jsonl>] | selftest",
            args.first().map(String::as_str).unwrap_or("control-dump")
        ));
    }
    let sub = args[1].clone();
    let mut panel: Option<PathBuf> = None;
    let mut expected: Option<PathBuf> = None;
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
    ))
}

fn main() {
    let mut args = std::env::args();
    let me = args.next().unwrap_or_else(|| "control-dump".into());
    let sub = args.next().unwrap_or_default();
    if sub == "selftest" {
        println!(
            "{{\"kernel\":\"control-dump\",\"ekos_pin\":\"{EKOS_PIN}\",\"panels\":[\"scope.decision\",\"conflicts.unit\"],\"oracles\":0}}"
        );
        return;
    }
    let (sub, panel, expected) = match parse_args() {
        Ok(x) => x,
        Err(e) => {
            eprintln!("{me}: {e}");
            std::process::exit(2);
        }
    };
    let result = match sub.as_str() {
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
        other => {
            eprintln!("{me}: unknown subcommand {other}");
            std::process::exit(2);
        }
    };
    match result {
        Ok(report) => {
            eprintln!(
                "{{\"panel\":{},\"items\":{},\"agree\":{},\"mismatch\":{},\"missing\":{}}}",
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
