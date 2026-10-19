# W12. Controls for the identity, branch and impact panels

2026-10-19. Lane W12 (claude-glm) built and committed the three dumps, then died with "Prompt
is too long" before its memo; the root verified the work and wrote this.

**Summary.**
1. `control-dump` now answers every panel that had none: `identity` (58/58, `af41085`),
   `branch` (3/3, `fee0d89`), `impact` (26/26, `b8308d5`), through EKOS's real
   `DefaultResolver::resolve`, `merge_branch` and `Runtime` walks.
2. `regen_controls.py --ekos` runs all six dumps: every control reproducible and identical to
   the committed file; six drift checkers, 0 drifted (root's run, this commit).
3. `docs/parity/BOARD.md` has 8 measured rows and 4 placeholders (ledger controls exist from
   W18 but are not registered in regen; time, fusion, ekl and redact have panels or nothing yet).
4. The lane's last uncommitted edits (an 8-line identity_dump fix, the regen registration of
   the three dumps, the manifest) are committed here as a checkpoint after the root's run.
5. Not verified: the lane's own mismatch analysis, since no memo survived; the registry
   entries' "does not measure" prose is W9's and W11's.
