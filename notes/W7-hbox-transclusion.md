# W7 — transclusion journeys on hbox: K12T 24/24, JDV 143/143

**Summary (5 lines).**
1. **Transclusion is proven live on hbox.** The tipbin host (`~/kn-gate/fix/tipbin/`, sha256 `a045ace1…`, all 5 checksums verified) boots past J0 — the `authorityCellId` genesis block that killed every W2 run locally is gone — and **K12T PASSes with 24/24 transclusion rows** (174.3 s), including the kernel refusals `sourceNotCovered` and `staleOpening` by name.
2. **JDV PASSes with 143/143 rows** (368.9 s): shell-level `doc transclude` snapshot + live, the no-grant placeholder, backlinks, and the pulled-transclusion marker all `ok` (rows 81–122, J19/J21).
3. **Slice 1 step 0 of the design doc (§5) is GREEN**: "run the existing JDV transclusion journey" passes on this build, so the §4 fallback (evidence as a plain `link`) is **not** needed.
4. J12W FAILed for a reason unrelated to transclusion: the journey.d scripts at kn-gate's checkout `d94a8817` (Oct 5) call `enroll plan NAME KEYFILE`, while the tipbin `mini` is newer and demands `enroll plan NAME KEYFILE NEXT-PUBLIC-KEY-HEX COSIGN-HEX` (key pre-rotation) — 68/81 rows failed at setup row 3. J12W contains no transclusion anyway; K12T and JDV enroll via `--new-key` and are unaffected.
5. Both services stopped themselves via their own `world/public/server.pid`; run roots are 14 M and 29 M; hbox root disk **30 GB free (94%) before and after** — unchanged.

## The exact manifest (`~/verekos-runs/w7/manifest.json` on hbox; copy in `var/w7/manifest.json`)

```json
{
  "host": "/home/hbox/kn-gate/fix/tipbin/minidregg-host",
  "mini": "/home/hbox/kn-gate/fix/tipbin/mini",
  "store": "/home/hbox/kn-gate/fix/tipbin/minidregg-link-sqlite-store",
  "verifier": "/home/hbox/kn-gate/fix/tipbin/minidregg-credential-signature-verifier",
  "shell": "/home/hbox/kn-gate/fix/tipbin/mini",
  "sha256": {
    "host": "a045ace1ec6206a1c49adeb77bd24eb617c5a0491da667d5d1540839b87020aa",
    "mini": "de52f5e74d4ba399eb3e232203d11ef691c3474d2e17b67bda2e9de134e3a0c0",
    "store": "03d843dda4b32df86e5cacad2f81bc242716f3f2687bc2f078e5ee5b01686af0",
    "verifier": "ff0ec57e85484392b89b1cf0eb75c955512220bb5e26dd8d8378cd499436cad6",
    "shell": "de52f5e74d4ba399eb3e232203d11ef691c3474d2e17b67bda2e9de134e3a0c0"
  }
}
```

Checksums verified before anything ran: `cd ~/kn-gate/fix/tipbin && sha256sum -c SHA256SUMS` → all 5 OK. The journey also re-checks every pin before J0 and records them in `<run>/inputs.sha256`.

## The commands

```sh
# run-1 — K12T (deps J0→J1/J2→J3→J4→J5 carried; JOURNEY_STEPS is the step filter, journey.sh:97):
cd ~/verekos-runs/w7 && nohup env JOURNEY_STEPS="J0 J1 J2 J3 J4 J5 K12T" HOOK_TIMEOUT_S=1200 \
  nice -n 10 bash /home/hbox/kn-gate/src/native/resource-client/journey.sh \
  /home/hbox/verekos-runs/w7/manifest.json /home/hbox/verekos-runs/w7/run-1 \
  > /home/hbox/verekos-runs/w7/k12t.log 2>&1 & echo $! > ~/verekos-runs/w7/k12t.pid

# run-2 — JDV + the cheap J12W control (both dep only on J0):
… JOURNEY_STEPS="J0 J12W JDV" … run-2 … > jdvw.log … ; echo $! > ~/verekos-runs/w7/jdvw.pid
```

Argument form confirmed from the header: `journey.sh MANIFEST.json NEW_RUN_ROOT` (2 args, no positional step); the subset filter is the `JOURNEY_STEPS` env var and "a subset must carry its deps" (journey.sh:96-100, `run_step` at :423; `run_step K12T J5`, `run_step J12W J0`, `run_step JDV J0`). Journey scripts were used read-only in place at `~/kn-gate/src/native/resource-client/` (`d94a8817`, contains `6402be4b`).

## Results

| Run / step | Status | Seconds | Transclusion rows | Refusal names seen |
|---|---|---|---|---|
| run-1 J0 clean start | **PASS** | 4.300 | — | — |
| run-1 J1–J5 | **PASS** | 6.432 / 2.604 / 4.749 / 5.989 / 19.267 | — | — |
| run-1 **K12T** range transclusion | **PASS** | **174.301** | **24/24** (`transclusion-rows.tsv`) | `sourceNotCovered`, `staleOpening`, `no-grant` (observation) ×2, placeholder text, late-joiner `moved` |
| run-1 FRONTIER | **END** (exit 0) | Σ 217.6 | accepted records 5; audit: 26 re-admitted | |
| run-2 J0 clean start | **PASS** | 5.942 | — | — |
| run-2 J12W doc pull/push | **FAIL** | 63.569 | 13/81 (0 transclusions in this step) | none — setup died on `enroll plan` usage (see summary line 4) |
| run-2 **JDV** J-DOCUVERSE | **PASS** | **368.893** | **143/143 ok** (J19/J21 transclusion rows all `ok`) | `no-grant`-shaped: "cal (no grant on notes) sees the placeholder for both quotes" — `ok` |
| run-2 FRONTIER | **J12W** | Σ 438.4 | | |

### The transclusion actions (run-1 `steps/K12T/transclusion-rows.tsv`, all `expect == got`)

Accepted (installed): `c-transcludes-snapshot` (T1, snapshot/keepTombstone), `c-transcludes-live` (T2 preferNext, T3 invalidate — ids `53110414071878089654180886350467263626` / `37164751112218074868680460958679495679`), `a-edits-inside`, `a-edits-outside`, `a-deletes-endpoint`.

Refused, by name:
- `c-no-read-refused` → `Minidregg.Kernel.ContentResource.Reject.sourceNotCovered` (transclude sent without the read target),
- `c-stale-opening-refused` → `Minidregg.Kernel.ContentResource.Reject.staleOpening` (pin names a revision wall never held),
- `b-cannot-transclude` → `no-grant` (phase observation; key holds no grant on the source),
- `d-follow-refused` → `follow refused: no read of source` (no-grant, observation).

Disclosure rows: `page-holds-no-bytes` absent (no wall bytes in page's own view); `d-placeholder-text` = `[transclusion: 3 atoms of wall, not readable by you]`; `late-joiner-placeholder` = `moved:27:live` ("its lines moved since height 27, and your grant did not cover wall then"); `restart-identical` identical; `audit` re-admitted ("audited 26 accepted records: every signed ingress re-admitted at its original prefix"). The old-world refusal *"this store's content cell has no transclusion action"* did **not** occur — the host carries the action.

JDV (run-2 `steps/JDV/jdocuverse.tsv`): rows 81/84 `doc transclude paper notes 2 3` (snapshot; live at 4) both `ok`; checks at 86 (live stands at line 4, snapshot at 6), 102 (snapshot keeps the transcluded line), 103 (live shows the new line, revised), 105 (no-grant reader sees the placeholder for both quotes), 108 (backlinks: link mark + two transclusions), 122 (J21: a pulled transclusion is one marker line) — all `ok`.

## Disk and load (hbox)

- Root `/` before: 455G, 402G used, **30G avail (94%)** — after both runs: **30G avail (94%)**, unchanged (run roots 14 M + 29 M; nothing else written; binaries used in place, never copied).
- Load during run-1 start/end: 14.41→20.12 (1-min) on 24 CPUs; another tenant's build was running the whole time. Journey ran under `nice -n 10`, one run at a time.

## What I could not run, and why

- **J12W's full 81 rows** — its setup uses the pre-prerotation `enroll plan` syntax; the tipbin `mini` (newer than the `d94a8817` checkout of journey.d) rejects it. Not fixable from this lane (journey.d is another lane's read-only tree). It exercises no transclusion, so nothing transclusion-related is lost.
- **WEB** (`run_step WEB K12C K12T K12M K12H`) — outside the brief's steps; would need four more K-lanes' deps and `mini web` byte-equality. K12T itself passed, which was the question.
- **Binaries newer than scripts**: the tipbin `mini`/`host` provenance commit is not recorded in `~/kn-gate/fix/tipbin/` beyond SHA256SUMS; the J12W usage error is the evidence they postdate `d94a8817`. If a later lane wants J12W green it needs journey.d ≥ the prerotation change or `--no-prerotation` in `j12w.sh`.

## Artifacts

Local: `var/w7/{manifest.json, k12t.log, jdvw.log, run-1/journey-result.json, run-1/steps/K12T/transclusion-rows.tsv, run-2/journey-result.json, run-2/steps/JDV/{jdocuverse.tsv, transcript.txt}, run-2/steps/J12W/j12w.tsv}` (120 K total). On hbox: `~/verekos-runs/w7/` (run roots kept; PID files `k12t.pid`, `jdvw.pid` — both processes exited on their own; both `server.pid`s verified dead).
