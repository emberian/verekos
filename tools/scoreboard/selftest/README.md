# score.py self-test manifest

`classified.selftest.jsonl` holds the deliberately planted difference W9 used to prove
`score.py` reports an unexplained difference and then accepts a classification. It was
moved here from `controls/classified.jsonl` (review R1, finding S1): a classification
is keyed by the hash of (panel, item, control, candidate), so a planted test entry in
the real manifest would silently excuse a real candidate making the same mistake.
Pass this file with `--classified` only when re-running the self-test; never merge it
into `controls/classified.jsonl`.
