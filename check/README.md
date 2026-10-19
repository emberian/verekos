# check/ — the Lean model run on the panels

`verekos-check` runs `world/` definitions on panel inputs; `run.py` scores
the answers against EKOS's controls and writes the receipts in
`controls/check/`. What is trusted and what is not is in each module's
docstring and in `notes/B-check.md`.

    cd check && nice -n 10 lake build        # verekos-check (imports WorldCore only)
    python3 -I check/run.py                  # from the repo root; never builds

## Exit codes

| Command | 0 | 1 | 2 |
|---|---|---|---|
| `verekos-check scope [--mutant deny-ignored] < panel.jsonl` | every line was read and answered (a refused scope is an answer: `{"error":"parse"}` or `{"error":"rule"}`) | — | a panel line is not JSON, or bad arguments |
| `verekos-check conflicts [--clash] < panel.jsonl` | same as `scope` (`--clash`: `World.detectListBy` with `World.labelClash`) | — | same as `scope` |
| `verekos-check laws [--mutant author-from-payload] <run-root>` | every law holds (pin law `AdmLog`, compiled pins nonempty, tx increasing) **and** every expectation in `expect.json` is met | a law fails, or an expectation is not met; `expect.json` can add requirements but never excuse a failed law | the run root cannot be read: a file is missing or not JSON, a log line is malformed, or a signer is not in `principals.json` or has a role that may not write |
| `python3 -I check/run.py` | every run below exited as expected, every panel and regression scored 0 unexplained and 0 verekos_defect, and the deny-ignored mutant scored worse than the faithful mapping | any of those failed | — |

What `run.py` expects of each laws run:

| Run root | Expected exit | Why |
|---|---|---|
| `check/fixtures/synthetic-run` | 0 | keeps every law; statuses and timelines as in its `expect.json` |
| `check/fixtures/synthetic-run-bad` | 1 | a compiled claim with no pins, a pin to an absent claim, tx out of order |
| `check/fixtures/synthetic-run` with `--mutant author-from-payload` | 1 | believing the payload admits a compiler's review, so the timeline misses `expect.json` |
| `check/fixtures/slice1-run-2` (slice 1's real run, via `slice1_log.py`) | 0 | the email conflict ends `needsReview`, the columns conflict `open` |
| the same log with the review re-signed by the compiler (`var/check/…`) | 1 | the review is not admitted; the conflict never leaves `open` |

`score.py` itself exits 1 on anything unexplained or classified
`verekos_defect`, 2 on malformed input; `run.py` records that as
`score_exit` in each verdict.
