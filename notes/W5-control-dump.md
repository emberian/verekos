# W5: the control dump — lane memo (2026-10-19)

What was built, what compiled, what got in the way, and what I could not
verify. Spec: `docs/design/explorations/03-scoreboard.md` (§2.2 the dump
binary, §5.4 the drift checker), design §6. Tasks 1–4 of the W5 brief.
README with day-to-day commands: `tools/scoreboard/README.md`.

## The pin

EKOS at `/Users/ember/dev/EKOS`, commit `8e3c178fc457…` (short `8e3c178`,
"fix(localdocs): read DOCX with roxmltree + zip 9…"), tree clean
(`git status --porcelain` empty) at build time. Recorded with binary, source
and panel hashes in `controls/MANIFEST.json`. The dump binary's Cargo.toml
points at the five crates by absolute path, on purpose: the control names the
tree it was built against.

## What was built

1. **The workspace** (`tools/scoreboard/control-dump/`, its own Cargo
   workspace): path deps on `ekos-{ledger,kir,semantic,identity,common}`,
   EKOS's `rust-toolchain.toml` (1.98.0) copied in, `Cargo.lock` committed.
2. **The `scope` dump**: `control-dump scope <panel> [--expected <file>]`
   reads items `{scope JSON text, origins as (source,path) pairs — or the
   object's sources + evidence paths, crossed by EKOS's own `origins()`}`,
   optional `id` for object rules, and answers by calling
   `ReadScope::from_json` → `Compiled::new` → `Compiled::visible`. Parse
   items answer `{"error":"parse"|"rule"}` (the two `ScopeError` variants);
   `unrestricted` and `origins` item kinds cover the remaining tests.
3. **The `conflicts` dump**: `duplicate_definitions` (with an
   `also_reversed` flag that measures the permutation-invariance the test
   asserts), `merge_losses` (with `MergeProposal`s built from panel keys),
   `label_mismatches`, `normalize_type` pairs. Output: surviving objects,
   conflict objects `(id, attribute, conflict_type, status, chosen, claims,
   signature, subject_id, evidence_count)` and their `Disputes` links.
4. **Panels + expected + drift records** for both, generated from
   `panels/transcribed/{scope,conflicts}_tests.py` (inputs to
   `panels/{scope/decision,conflicts/unit}.jsonl`, the tests' own assertions
   to `controls/*.expected.jsonl`). `drift_check.py` (run `python3 -I`)
   hashes each transcribed test function's source text, located by name in
   the pinned checkout, and fails when the hash moves.
5. `controls/MANIFEST.json` (partial, see below), `tools/scoreboard/README.md`,
   this memo.

## Numbers (2026-10-19)

- Build: 163 unique crates, ~5.4 min wall from empty `target/` to the final
  binary including three fix-rebuilds of my crate only (each ~0.5 s
  incremental); deps dominate (tantivy, rusqlite, zstd come in via
  ekos-ledger). Log: `var/w5/build.log` (git-ignored).
- scope.decision: **59 items** from **17 test functions**, control run
  **59 agree / 0 mismatch / 0 missing**; two runs byte-identical.
- conflicts.unit: **16 items** from **8 test functions**, control run
  **16 agree / 0 mismatch / 0 missing**; two runs byte-identical.
- Drift checker: 17 + 8 functions hashed, 0 drifted (verify mode).
- Planted defects: one flipped scope expectation → `mismatch:1`, exit 1;
  `conflicts_count: 0→1` on three conflicts items → all three caught, exit 1.
  (Ad-hoc, run in `/tmp`; the standing stand-in machinery of §3.5-2 is not
  built.)
- Both panels' conflict/object ids are UUIDv5 over panel keys and stable
  across runs — the determinism the EKOS tests themselves assert
  (`detection_is_independent_of_input_order_and_ids_are_stable` reproduces as
  `permuted_stable: true`).

## pub(crate) obstacles

- **None for these two dumps.** Everything called is exported:
  `ekos_ledger::scope::{ReadScope, Compiled, Origin, origins}` (all `pub`,
  fields `pub`), `ekos_semantic::conflicts::{duplicate_definitions,
  merge_losses, label_mismatches, normalize_type}`, `ekos_identity::
  {MergeProposal, DefaultResolver}` (`resolve` is a method of the `pub trait
  IdentityResolver`, so callable from outside), `ekos_kir::{KirId, KirObject,
  KirGraph, KirEvidence, SourceLocation, ObjectKind, KirRelationship}`.
- **`kid()` in conflicts.rs is private**: the UUIDv5-over-URL-namespace id
  rule. Reimplemented locally (6 lines) — the self-check is that the control's
  conflict ids and signatures are exactly the stable ones the EKOS tests
  assert (the `detection_is_independent…` test compares ids, claims and
  signature across permutations; our control reproduces all three equal).
- **`content_signature` (ledger/src/lib.rs:47) is `pub(crate)`** — the known
  one from the spec. Not needed by scope/conflicts; still an obstacle for the
  future Ledger/Branch controls, which per the recorded decision recompute it
  locally and self-check against stored signatures. Nothing done here.
- `signature()` inside conflicts.rs is private, but it only runs inside
  `emit`; the control carries EKOS's own signature output, so no local copy
  is needed.

## Decisions and near-misses worth knowing

- Parse-item error *variants* (`parse` vs `rule`): only two are pinned by the
  tests' own assertions (`a_scope_without_a_default…`'s first input asserts
  `ScopeError::Parse`; the object+source rule asserts `Rule { index: 0 }`).
  The rest are the tests' `.is_err()` plus the variant predicted from
  `from_json` (= serde + `check()`, i.e. `Compiled::new`). The 59/59 run
  confirms every prediction — but they are predictions, marked as such in
  `scope_tests.py`'s docstring.
- `ObjectKind::Custom` is `#[serde(untagged)]`: panel kinds are plain strings
  (`"Table"`, `"EnumMeaning"`), not `{"Custom": …}`. First run caught my
  wrong guess.
- The scope tests' random `KirId::new()` ids are replaced by fixed UUIDs
  (`object_rules_name_one_object`'s "wanted" id); the decision compares ids
  for equality only, so any fixed uuid is the same test. Noted in the panel
  generator.
- `only_default_allow_without_a_deny_is_unrestricted`'s first line asserts
  about `ReadScope::unrestricted()` (a constructor, not a JSON input) — not
  transcribed; the three JSON lines are.
- Not transcribed at all, deliberately: the `ScopedStore` family
  (`scope.rs:1041` on — needs a real store; that is the leak-suite panel and
  the fixture pipeline, neither exists yet) and the conflicts review workflow
  (`resolve`, `carry_forward`, `column_links` — reviewing, not detecting).
- `controls/MANIFEST.json` is a **partial** W5 manifest (ekos pin, binary and
  file hashes). The full §2.1 manifest (ekos binary, fixtures, reproducibility
  self-check) is `regen_controls.py`'s job; that script does not exist yet.

## What I could not verify

- That EKOS's *scopes* behave the same inside a real store: the panel measures
  `Compiled::visible` and `ReadScope` parsing only. The store family
  (`ScopedStore`, both-ends-visible relationships, search filtering) is
  unmeasured until the fixture pipeline exists.
- `DefaultResolver::resolve` is linked and builds (it is how `MergeProposal`
  gets in), but the Identity panel itself was not built — `resolve` is
  exercised by zero items in this wave.
- The parse-variant predictions above (confirmed by one run, not by the
  tests' assertions).
- Long-run drift behaviour: the checker has only ever run against the tree it
  was recorded from. Its failure mode (hash mismatch on edit) is exercised by
  construction, not by a real EKOS edit.
- `cargo build` warnings: the build is warning-clean for my crate; I did not
  run clippy or `cargo fmt` (the shared gate is EKOS's, and this is not
  EKOS).

## Next lane, in order of value

1. The leak-suite scope family (needs `run_fixture.py`): the store tests are
   the ones the markers/`SECRET_DIR_MARKERS` control hangs on.
2. `regen_controls.py` + the real §2.1 MANIFEST (binary hashes, fixture
   pipeline, reproducibility self-check §3.5-3).
3. Identity panel (the `exact_name_match` families; `resolve` is already
   linked), then Branch with the local `content_signature` + self-check.
