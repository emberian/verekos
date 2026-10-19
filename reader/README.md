# The reader-local compile: a friend's own copy of what they can read

You have some documents on the node. This folder lets you ask questions about them on your
own machine, with answers you can check.

It works in three moves.

1. **Sync.** The tool reads every document you are allowed to read, one signed read at a time,
   using your own key. It notes, for each paragraph, which document it came from, which paragraph
   it is, and which revision it was at. It writes the documents out as files in a folder on your
   machine and runs EKOS (the knowledge compiler) over that folder.
   It says how many documents it read, how many paragraphs, and how many it could not read.
2. **Ask.** `find`, `before` and `disagree` answer from that local copy.
3. **Check.** Every answer line ends with a *pin*: the document, the paragraph and the revision the
   answer came from. Before it prints the answer, the tool reads that document again, from the
   node, with your key. The pin then says **same bytes** (the paragraph is exactly as the answer
   saw it) or **moved** (someone has edited it since; the tool shows what the answer said and what
   the paragraph says now).

## Run it

You need `python3`, `ssh` access to the node's machine (your key lives there for now), and the EKOS
binary named in `reader.conf.json`. Nothing here needs a package install.

```
python3 -I reader/sync.py                  # read, render, compile
python3 -I reader/find.py customers        # what do I know about "customers"?
python3 -I reader/before.py customers      # what links to it, one and two steps out
python3 -I reader/disagree.py              # where do my documents disagree?
python3 -I reader/leakcheck.py             # prove nothing from a document I cannot read is here
python3 -I reader/scene.py OUTDIR          # the whole demo, with receipts (it edits the world; see below)
```

Your local copy is under `var/lane-a/reader/<you>/<time>/` (set `VEREKOS_READER_STATE` to move it).
Run `sync.py` again whenever you like. If nothing anywhere on the node has changed, it stops after
one read. If something has, it reads everything again: the node has no way to say *which* document
changed without being asked to read it.

## What you get, in words

- `find` lists what the compiler found for your words, in its own rank order, each with its pin.
- `before` lists what links to a thing one step away and two steps away, and counts how many
  pins in the compiled documents you can read would go stale if you rewrote it.
- `disagree` lists places where two documents *you can read* say different things. It also says
  what it cannot see. A zero from someone who was refused a document is not a zero for the world,
  and a compiled document you can read may mention a source you cannot. The tool says so and does
  not guess what the unseen document holds.

## What it will not do

- It never shows you anything from a document you cannot read. `leakcheck.py` looks for the text of
  the refused document in every file on this machine, with a planted copy as proof the scan works.
- It does not publish your graph. Your friend cannot ask your laptop a question. If you want them
  to see something, write it as a document on the node.
- It does not write to the node. The scene script does, as a different person (the importer), to
  show a pin going `moved`.

## Things to know before you trust a pin

The pin to a paragraph is found by a **guess**: EKOS says which *file* an answer came from, not
which statement, so the tool matches the answer's table name to a statement by its structural key
(`create-table:customers#0`). Every pin line says `[guess: structural key]`. If two statements in
a file define the same thing, the tool lists every candidate. Nothing about EKOS itself is checked
here: where the tool compares two things, both are EKOS (or EKOS's own export) on the same copies.
