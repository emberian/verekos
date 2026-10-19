#!/usr/bin/env python3
"""Render docs/parity/BOARD.md (exploration 03 §4), never hand-edited.

One row per panel: items, agree, classified, unexplained, the assurance
label, what the panel measures and — mandatory — what it does not. Both
prose cells and the label come from panels/LABELS.json; the numbers come
from a control-vs-control run through score.py's own diff code (the §3.5-1
positive control, re-run on every render, so a broken diff code can never
produce a board) plus the classification manifest controls/classified.jsonl.

The classified column counts differences of *this* run that a manifest entry
classified, so agree + classified + unexplained = items always holds (§3.1);
at M0.5 the self-score run has no differences, so it is 0. The manifest
itself is never hidden: entries on record that no difference of this run
matched are still listed in the detail section, labelled as such.

Run with python3 -I from anywhere (paths resolve from the repo layout):

    python3 -I tools/scoreboard/board.py [--out docs/parity/BOARD.md]
"""

import argparse
import importlib.util
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent

STANDING = ("Counts are agree / classified / unexplained. Agree with the control is not "
            "correctness: EKOS can be wrong (see classified ekos_defect rows). Classified "
            "differences are not hidden; they are counted.")
NO_CANDIDATE = ("No VerEKOS candidate is scored yet. Until one is, the Agree column is the control "
                "scored against itself (exploration 03 §3.5-1): it shows the diff code runs, nothing "
                "more. The column that measures something today is **Test asserts**: EKOS's own "
                "function, run on the transcribed input, reproduced what the Rust test asserts "
                "(from the last `regen_controls.py` run recorded in controls/MANIFEST.json).")


CANDIDATE_NOTE = ("The **Candidate** column is the Lean model itself answering the panel: "
                  "`check/` runs a `world/` definition on each item (`check/run.py`), and "
                  "`score.py` scores it against EKOS's control. A row whose verdict is fresh "
                  "(candidate, panel and control hashes match the files) with 0 unexplained and "
                  "0 verekos_defect shows the label it earned, `executable property`, in place of "
                  "`design target`; panels/LABELS.json is not edited. Rows without a verdict in "
                  "controls/check/ have no candidate.")


def candidate_verdict(key, score, panel_file=None):
    """controls/check/<panel>.verdict.json, checked against the files it names
    and against the row's current panel file.

    Returns (verdict, stale reason or None), or (None, None) when there is none."""
    path = ROOT / "controls/check" / f"{key}.verdict.json"
    if not path.is_file():
        return None, None
    v = json.loads(path.read_text())
    for field, rel in (("candidate_sha256", v.get("candidate")),
                       ("control_sha256", v.get("control")),
                       ("panel_sha256", panel_file)):
        f = ROOT / rel if rel else None
        if f is None or not f.is_file():
            return v, f"{field}: {rel} is missing"
        if score.sha256_of(f.read_text()) != v.get(field):
            return v, f"{rel} changed since the verdict"
    return v, None


def candidate_cell(v, stale):
    if v is None:
        return "—"
    if stale:
        return f"stale ({esc(stale)})"
    return (f"{v['agree']} / {v['items']} agree, {v['classified']} classified, "
            f"{v['unexplained']} unexplained")


def earned_label(label, v, stale):
    if v is None or stale or v["unexplained"] or v["verekos_defect"]:
        return label
    if label == "design target":
        return "executable property"
    return label


def load_score():
    spec = importlib.util.spec_from_file_location("verekos_score", HERE / "score.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def manifest_head():
    path = ROOT / "controls/MANIFEST.json"
    if not path.is_file():
        return None, None, None, {}
    text = path.read_text()
    m = json.loads(text)
    commit = m.get("ekos", {}).get("commit")
    tree = m.get("ekos", {}).get("tree")
    runs = {r["control"]: r for r in m.get("runs", []) if "control" in r}
    return commit, tree, load_score().sha256_of(text), runs


def panel_item_count(path: Path, name: str):
    """Items of panel `name` in a panel file (several panels share a file)."""
    if not path.is_file():
        return None
    n = 0
    for line in path.read_text().splitlines():
        if line.strip() and json.loads(line).get("panel") == name:
            n += 1
    return n


def asserts_cell(run, expected_file):
    """The control's reproduction of the transcribed test assertions."""
    if run and run.get("items") is not None:
        return f"{run.get('agree')} / {run['items']}"
    if expected_file:
        return "no control yet"
    return "—"


def load_manifest_entries():
    path = ROOT / "controls/classified.jsonl"
    if not path.is_file():
        return []
    return [json.loads(line) for line in path.read_text().splitlines() if line.strip()]


def check_labels(labels):
    for key, row in labels.get("panels", {}).items():
        for field in ("assurance", "measures", "does_not_measure"):
            if not str(row.get(field, "")).strip():
                sys.exit(f"panels/LABELS.json: {key}.{field} is empty (both prose cells and the label are mandatory, §4)")
        if row["assurance"] not in labels.get("assurance_labels", {}):
            sys.exit(f"panels/LABELS.json: {key}.assurance {row['assurance']!r} is not a known label")
    for row in labels.get("placeholders", []):
        for field in ("assurance", "measures", "does_not_measure"):
            if not str(row.get(field, "")).strip():
                sys.exit(f"panels/LABELS.json: placeholder {row.get('panel')}.{field} is empty")


def esc(text):
    return str(text).replace("|", "\\|").replace("\n", " ")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--out", type=Path, default=ROOT / "docs/parity/BOARD.md")
    args = ap.parse_args()

    score = load_score()
    labels = json.loads((ROOT / "panels/LABELS.json").read_text())
    check_labels(labels)
    classified = load_manifest_entries()
    commit, tree, manifest_sha, runs = manifest_head()
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    lines = []
    lines.append("# The VerEKOS parity board (M0.5)")
    lines.append("")
    lines.append(f"Generated {now} by `tools/scoreboard/board.py` from the committed control and "
                 "classification files. Hand edits are overwritten on the next render.")
    lines.append("")
    if commit:
        lines.append(f"- EKOS pin: `{commit}`"
                     + (f" (tree `{tree}`)" if tree else "")
                     + (f", control manifest `sha256:{manifest_sha[:12]}…`" if manifest_sha else ""))
    scored = sum(1 for r in labels["panels"].values() if r.get("control_file"))
    lines.append(f"- Panels: {scored} rows with an item-keyed control, "
                 f"{len(labels['panels']) - scored} rows with inputs but no item-keyed control, "
                 f"{len(labels['placeholders'])} placeholder rows (no panel yet)")
    lines.append(f"- {STANDING}")
    with_candidate = [k for k in labels["panels"] if candidate_verdict(k, score)[0] is not None]
    if with_candidate:
        lines.append(f"- Candidates scored: {', '.join(f'`{k}`' for k in with_candidate)}. "
                     "On every other row " + NO_CANDIDATE[0].lower() + NO_CANDIDATE[1:])
        lines.append(f"- {CANDIDATE_NOTE}")
    else:
        lines.append(f"- {NO_CANDIDATE}")
    lines.append("")

    lines.append("| Kernel | Panel | Items | Test asserts | Agree | Candidate (check/) | Classified (E / V / N) | Unexplained | Assurance | Scope: what this panel measures | Does NOT measure |")
    lines.append("|---|---|---|---|---|---|---|---|---|---|---|")
    detail = []
    for key, row in labels["panels"].items():
        if row.get("control_file"):
            panel_path = ROOT / row["panel_file"]
            control_path = ROOT / row["control_file"]
            r = score.score(row["kernel"].lower(), panel_path, control_path, control_path, classified)
            if r["unexplained"] or r["mismatch"] or r["missing"] or r["extra"]:
                sys.exit(f"{key}: the control self-score is not clean: {r}")
            classes = [e["class"] for _, _, e, _ in r["_classified"]]
            n_e, n_v, n_n = (classes.count(c) for c in ("ekos_defect", "verekos_defect", "non_goal"))
            cv, stale = candidate_verdict(key, score, row.get("panel_file"))
            label = earned_label(row["assurance"], cv, stale)
            lines.append(f"| {row['kernel']} | `{key}` | {r['items']} | "
                         f"{asserts_cell(runs.get(row['control_file']), row.get('expected_file', True))} | {r['agree']} | "
                         f"{candidate_cell(cv, stale)} | "
                         f"{n_e} / {n_v} / {n_n} | {r['unexplained']} (law: 0) | {label} | "
                         f"{esc(row['measures'])} | {esc(row['does_not_measure'])} |")
            matched = [e for _, _, e, _ in r["_classified"]]
            detail.append((key, row, r, matched))
        else:
            n = panel_item_count(ROOT / row["panel_file"], key) if row.get("panel_file") else None
            lines.append(f"| {row['kernel']} | `{key}` | {n if n is not None else '—'} | "
                         f"{asserts_cell(None, row.get('expected_file'))} | — | — | — | — | {row['assurance']} | "
                         f"{esc(row['measures'])} | {esc(row['does_not_measure'])} |")
            detail.append((key, row, None, []))
    for row in labels["placeholders"]:
        items = row.get("items")
        items_cell = str(items) if items is not None else "—"
        lines.append(f"| {row['kernel']} | `{row['panel']}` ({esc(row['status'])}) | {items_cell} | — | — | — | — | — | "
                     f"{row['assurance']} | {esc(row['measures'])} | {esc(row['does_not_measure'])} |")

    lines.append("")
    lines.append("## Per-panel detail")
    lines.append("")
    for key, row, r, matched in detail:
        lines.append(f"### `{key}`")
        lines.append("")
        if r:
            lines.append(f"Self-score (the control is the candidate, §3.5-1) run at render time: "
                         f"{r['items']} items, {r['agree']} agree, {r['mismatch']} mismatch, "
                         f"{r['missing']} missing, {r['extra']} extra, {r['unexplained']} unexplained.")
            cv, stale = candidate_verdict(key, score, row.get("panel_file"))
            if cv is not None:
                lines.append("")
                b = cv.get("check_build", {})
                lines.append(
                    f"Candidate (`{cv['candidate']}`, `sha256:{cv['candidate_sha256'][:12]}…`) "
                    f"scored against `{cv['control']}` (`sha256:{cv['control_sha256'][:12]}…`), "
                    f"panel `sha256:{cv['panel_sha256'][:12]}…`, recorded {cv['recorded']}: "
                    f"{cv['items']} items, {cv['agree']} agree, {cv['mismatch']} mismatch, "
                    f"{cv['missing']} missing, {cv['extra']} extra, {cv['classified']} classified, "
                    f"{cv['verekos_defect']} verekos_defect, {cv['unexplained']} unexplained. "
                    f"Built by `verekos-check` `sha256:{b.get('exe_sha256', '?')[:12]}…` from "
                    f"`check/` tree `{b.get('check_tree', '?')[:12]}`"
                    + (" (dirty)" if b.get("check_dirty") else "")
                    + f", world `{(b.get('world_rev') or '?')[:12]}`."
                    + (f" **Stale:** {stale}." if stale else ""))
        else:
            lines.append(f"Placeholder: {row.get('status', 'no control yet')}.")
        lines.append("")
        entries = [e for e in classified if e["panel"] == key]
        matched_ids = {e["diff_id"] for e in matched}
        on_record_only = [e for e in entries if e["diff_id"] not in matched_ids]
        if matched:
            lines.append("Classified differences of this run:")
            lines.append("")
            for e in matched:
                lines.append(f"- `{e['item']}` — **{e['class']}** — {e['reason']} "
                             f"(`diff_id {e['diff_id'][:12]}…, signed: {e.get('signed', '—')})")
            lines.append("")
        if on_record_only:
            lines.append("Classification manifest entries on record for this panel that no "
                         "difference of this run matched (they belong to other recorded runs):")
            lines.append("")
            for e in on_record_only:
                lines.append(f"- `{e['item']}` — **{e['class']}** — {e['reason']} "
                             f"(`diff_id {e['diff_id'][:12]}…, signed: {e.get('signed', '—')})")
        if not entries:
            lines.append("No classified differences on record.")
        lines.append("")

    lines.append("## Assurance labels")
    lines.append("")
    lines.append("From `panels/LABELS.json`, the one copy of these definitions. A label describes "
                 "the kernel's claim, never the panel result.")
    lines.append("")
    lines.append("| Label | Meaning |")
    lines.append("|---|---|")
    for name, meaning in labels.get("assurance_labels", {}).items():
        lines.append(f"| `{name}` | {esc(meaning)} |")
    lines.append("")

    lines.append("## Not measured")
    lines.append("")
    for item in labels.get("never_measured_here", []):
        lines.append(f"- {item}")
    lines.append("")

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text("\n".join(lines))
    out = args.out.resolve()
    print(json.dumps({"board": str(out.relative_to(ROOT)) if out.is_relative_to(ROOT) else str(out),
                      "rows": len(labels["panels"]),
                      "placeholders": len(labels["placeholders"]),
                      "classified_entries": len(classified)}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
