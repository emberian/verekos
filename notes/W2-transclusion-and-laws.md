# W2 — transclusion on a real Host, and how a law is installed

**Summary (5 lines).**
1. Transclusion is **untestable on this machine today**: the only host binary (`minidregg/.lake/build/bin/minidregg-host`) was built 2026-09-19 at `66d74dd0` — its strings contain 3× `authorityCatalogueId` and **0× `transclude`** — while the kernel `transclude` action landed 2026-10-01 (`6402be4b`, `eb44a043`) and the genesis vocabulary changed to `authorityCellId` on 2026-09-30 (`f8579579`).
2. Both journey runs died at J0 bootstrap with the host's own refusal `Minidregg.Host.Settings.authorityCatalogueId: Natural number expected`; K12T, JDV and J12W are recorded FAIL (blocked). The briefing's "host built 2026-10-08 at dcab86da" is wrong: `dcab86da` is the checked-out commit; the binary's provenance (sha256 `3107faf3…`, matches on disk) says 2026-09-19/`66d74dd0`.
3. What is missing to run any transclusion step: a host built at ≥ `6402be4b` via `scripts/build-native-host.sh` in a snapshot — outside this lane's sanction (no `lake build` in minidregg; only the Rust client build was allowed, which I did: `mini` release from HEAD, 1m 29s).
4. Custom laws **can** be installed from the client, no client change: `law ID REF <CLAUSES|PREDICATE-JSON|@FILE>` and `doc new NAME <draft|note|index|LAW-JSON|@FILE>` (the 4th word is the law). The design doc's §5 step-1 blocker ("could not find the client command") is resolved at HEAD.
5. Until a fresh host exists, slice 1 step 0 should take the §4 fallback (evidence as a `link` with a `.range` target), exactly as the design doc anticipated.

## What a journey needs (task 1)

- A run is `journey.sh MANIFEST.json NEW_RUN_ROOT` (absolute, fresh, not existing). The manifest names absolute `host`, `mini`, `store`, `verifier` (+ optional `shell`, `hermes`, `spkHost`, `candidate`, and sha256 pins). It stands up a **fresh private Store** from those binaries; nothing pre-existing is probed. `JOURNEY_STEPS="…"` selects a subset **that must carry its dependencies** (journey.sh:96-100, `run_step ID DEP…` at journey.sh:407).
- Binary roles, from the 2026-09-30 recorded manifest (`docs/evidence/2026-09-30-shell-docs/manifest.json`): `host` = the Lean `minidregg-host`; `mini` = the resource client (also `shell`); `store` = `minidregg-link-sqlite-store`; `verifier` = `minidregg-credential-signature-verifier`.
- On this Mac all four existed (`find native -maxdepth 4 -perm -u+x -name 'mini*'`): host `.lake/build/bin/` (Sep 19), `mini` debug (Sep 28), sqlite store release (Sep 17) + debug, verifier debug (Sep 19). **Missing was a client that can express transclusion**: the Sep-28 debug `mini` has 0 `transclude` strings and answers `mini: unexpected argument transclude`; client-side transclusion landed 2026-10-01. I built `minidregg-resource-client` release from HEAD (the one sanctioned write into minidregg's tree, `native/resource-client/target/`, gitignored). No other package needed building.
- macOS portability: the header says "Requires: Linux", but everything worked up to bootstrap — `date +%N`, `sha256sum`, homebrew `timeout`, `pgrep`, `xxd` all present; `/proc/loadavg` and `nproc` reads are `2>/dev/null`-tolerated. Only `setsid` is absent, so I put a shim (`#!/bin/sh; exec "$@"`) at `var/w2/bin/setsid` on PATH: safe because the journey stops its service **only by the PID recorded in `world/public/server.pid`** (journey.sh:484-505), never by pattern or process group.

## Commands run (task 2), and results

```sh
# 1. client rebuild (backgrounded, PID file, log):
nice -n 10 cargo build --release --offline --locked \
  --manifest-path /Users/ember/dev/minidregg/native/resource-client/Cargo.toml
#   > /Users/ember/dev/verekos/var/w2/build.log   (pid 34968)   [1m 29s]

# 2. K12T (the transclusion lane; deps J0→J1/J2→J3→J4→J5):
env PATH="/Users/ember/dev/verekos/var/w2/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  XDG_RUNTIME_DIR=/Users/ember/dev/verekos/var/w2/run/xdg \
  JOURNEY_STEPS="J0 J1 J2 J3 J4 J5 K12T" HOOK_TIMEOUT_S=1200 \
  bash /Users/ember/dev/minidregg/native/resource-client/journey.sh \
  /Users/ember/dev/verekos/var/w2/manifest.json /Users/ember/dev/verekos/var/w2/run/k12t

# 3. the steps the brief named (JDV, J12W; both dep only on J0):
env PATH=… XDG_RUNTIME_DIR=… JOURNEY_STEPS="J0 J12W JDV" HOOK_TIMEOUT_S=1200 \
  bash …/journey.sh …/manifest.json /Users/ember/dev/verekos/var/w2/run/jdvw
```

Manifest (`var/w2/manifest.json`): host = `.lake/build/bin/minidregg-host`; mini = `native/resource-client/target/release/mini` (fresh); store = `native/hyperdocument-link-sqlite-store/target/release/minidregg-link-sqlite-store`; verifier = `native/credential-signature-verifier/target/debug/minidregg-credential-signature-verifier`; shell = mini.

| Run / step | Status | Wall | Refusal / detail |
|---|---|---|---|
| run/k12t — total | frontier **J0** | 1.951 s | rc 1 |
| J0 clean start | **FAIL** | 1.573 s | `bootstrap exit 1: minidregg-host: Minidregg.Host.Settings.authorityCatalogueId: Natural number expected` |
| J1–J5 | FAIL | 0.000 s | `blocked: <previous> did not pass` |
| **K12T** range transclusion | FAIL | 0.000 s | `blocked: J5 did not pass` (never reached a transclusion action) |
| run/jdvw — total | frontier **J0** | 1.682 s | rc 1 |
| J0 | **FAIL** | 1.480 s | same `authorityCatalogueId` refusal |
| J12W doc pull/push stale-by-line | FAIL | 0.000 s | `blocked: J0 did not pass` |
| JDV J-DOCUVERSE | FAIL | 0.000 s | `blocked: J0 did not pass` |

Result files: `var/w2/run/k12t/journey-result.json`, `var/w2/run/jdvw/journey-result.json`; logs `var/w2/journey-k12t.log`, `journey-jdvw.log`. No service was ever started (empty `services.log`), so nothing needed stopping; no processes remain.

**Why, precisely.** Three independent barriers, all vintage:

1. **The binary predates the action.** `Kernel/ContentResource.lean` gained annotate/quote on 2026-09-30 (`ddbdbae`) and range transclusion on 2026-10-01 (`6402be4b` "range transclusion with disclosure at transclusion time", `eb44a043` element tree). The binary is from 2026-09-19: `strings minidregg-host | grep -ci transclude` → **0**. Even with a perfect boot, every transclusion would refuse as on 2026-09-30: *"this store's content cell has no transclusion action (Kernel/ContentResource.lean Action has no transclude…); needs K-CONTENT-ACTIONS"* (docs/evidence/2026-09-30-shell-docs/journey-result.json, step J12C).
2. **The binary predates the genesis rearchitecture.** `authorityCatalogueId` → `authorityCellId` landed 2026-09-30 (`f8579579`, `752f9eb0` "One genesis template"). The HEAD client writes `authorityCellId` (see `run/k12t/world/genesis-params.json`); the old host's decoder demands `authorityCatalogueId` and refuses before a sponsor exists. `strings` shows 3 `authorityCatalogueId` in the binary; the string exists nowhere at HEAD.
3. **No pairing escapes it.** The only other client build (Sep-28 debug) also predates transclusion (0 strings) and its commit `bae39a8d` already lacks `authorityCatalogueId` client-side — and it could not express a transclusion anyway.

**What is missing (exact):** a `minidregg-host` built from any commit ≥ `6402be4b` (2026-10-01; HEAD `dcab86da` qualifies), matched to a same-vintage `mini`, `store`, `verifier`. The sanctioned route is `scripts/build-native-host.sh` in an independent snapshot (README "Build and verify"). Building it was outside this lane's permissions (`lake build` inside `/Users/ember/dev/minidregg` is forbidden; only the single Rust package build was allowed).

Note on the brief's premise: **J12W exercises no transclusion** (0 references in `journey.d/j12w.sh`; it is pull/push/stale-by-line). The transclusion carriers are **K12T** (`journey.d/j12t-kernel.sh`, 24 references — snapshot pinned, live follows, placeholder, `sourceNotCovered`, `staleOpening` refusals are its rows) and **JDV** (`journey.d/jdocuverse.sh`, 9 references, row J19). K12T is the narrowest.

## How a custom law is installed from the client (task 3)

**Yes — an arbitrary `Pred` JSON can be installed; the three templates are only defaults.** Two paths, both already in the client:

1. **`law` verb** (usage `shell.rs:79`, handler `shell.rs:2280-2295`):
   ```
   law ID REF "CLAUSE; CLAUSE; …"|PREDICATE-JSON|@FILE [--allow-unsatisfiable] [--i-lock-myself-out] [--freeze-roster]
   law show REF | law export … | law check "CLAUSE; …"|PREDICATE-JSON|@FILE|-
   ```
   It authors `{"type":"minidregg-workspace-proposal-v1","action":"install-policy","name":REF,"predicate":…}` and submits it via `mini workspace --action propose`. The install-time satisfiability check is Host op 150 (`lawsat.rs:347`): a law no step can satisfy is not proposed unless `--allow-unsatisfiable` (deliberate for `sealed`).
2. **`doc new`'s fourth word** (`shell.rs:1360-1372`): usage is `doc new NAME [draft|note|index|LAW] [--in ROOM]`; when the word is not a stock template it goes through `law_argument` (`shell.rs:1059-1078`), which accepts the law **as one quoted word of JSON, or `@FILE`** (JSON file, or file in the clause grammar), and is sent as `mini workspace --action doc-new --predicate @FILE`. So the brief's `doc new --law <file.json>` does not exist as a flag; the spelling is positional: `doc new mydoc @law.json` or `doc new mydoc '{"type":"any","predicates":[]}'`.

**JSON spelling** (from the templates `shell.rs:148-159` and `:182`; the host decodes with exact-key objects, `Host/Json.lean:282-321`):

| Pred | JSON |
|---|---|
| `eq` | `{"type":"eq","slot":"request/verb","value":"2"}` |
| `le` | `{"type":"le","slot":"content/payload-bytes/after","value":"16384"}` |
| `memberOf` | `{"type":"memberOf","slot":"request/verb","values":["1","3","4","5"]}` |
| `not` | `{"type":"not","predicate":{ … }}` |
| `all` | `{"type":"all","predicates":[ … ]}` |
| `any` | `{"type":"any","predicates":[ … ]}` |

Full atom set (`Pred/Core.lean:170-211`): `eq, le, memberOf, writeOnce, monotone, eqSlots, leSlots, leSlotsOff, sumEq, witnessed, hashEq, ran`, closed under `not`/`allL`/`anyL` (JSON `all`/`any`). There is also a one-line text grammar (`src/shell/law.rs:1-40`): `slot == value | slot <= value | slot in {v,…} | not (…) | any […] / all […] | field N monotone|writeOnce | slot == slot | slot <= slot [+k] | slot opens (…) with … | ran N | sealed | open`, verbs named `read write delegate install revoke append place`. The design doc's §6 unknown ("the exact JSON spelling of `not`") is thereby `{"type":"not","predicate":{…}}`.

## Wall-clock

| What | Time |
|---|---|
| `minidregg-resource-client` release build (nice 10, offline, locked) | **1 m 29 s** |
| run/k12t (J0…K12T, died at J0) | 1.951 s (J0 1.573 s) |
| run/jdvw (J0, J12W, JDV, died at J0) | 1.682 s (J0 1.480 s) |

## What I could not verify

- **Any live transclusion behavior** — the actual point of the run. Needs a host ≥ `6402be4b`; see above.
- **Actually installing a law on a real document** (the task-3 answer is from source + unit tests, not a landed receipt — same J0 block).
- The Host's op-150 satisfiability gate in practice, `doc show --at H`, the JDV golden compare, `mini web` byte-equality — all behind the same boot block.
- Whether the Sep-17 sqlite store build is protocol-compatible with a future host build (it was never reached).
- Whether `journey.sh` runs to completion on macOS past bootstrap (everything up to the host's refusal worked; the `setsid` shim is untested against a live `stop_server`, though that path is PID-file-only by construction).
