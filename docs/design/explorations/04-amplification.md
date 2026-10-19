# 04. What each side gains from the other: a catalogue

Design lane, 2026-10-19. Read-only except this file. Nothing was built or run.

## Summary

1. The cheapest real amplification needs no change to minidregg: a **reader-local compile**. A friend's own client reads their documents with their own signed reads, runs EKOS over the copies, and gets answers whose evidence pins are re-checked against the node (same bytes or "moved").
2. Catalogue A has ten entries (one per minidregg surface). Only three can be used on the public node today, because it runs documents and boards only (README.md:69, FRIENDS.md:20-37). The rest ride on things that are integrated on scratch worlds or compiled.
3. Catalogue B has fourteen entries. About half have a Rust shadow EKOS could take with no minidregg at all (filed issues #12, #13, #14, #16 and three new proposals). The ones that need the world are the ones about who may do what.
4. Ranking: build first the reader-local compile with pinned answers. Then a stored branch conflict (new, upstream), the read-only trait (#13), reviewer identity on review decisions (#16), and resident grounding with session memory.
5. Traps: writing EKOS passes in Objective Bend, putting the ledger on the agreement mesh, and one grain per connector.
6. What I could not verify is at the end (section 6). The largest item: nobody has run any EKOS analyzer over minidregg's Markdown, so every "EKOS would find X" below is a prediction.

## 0. How to read this

Evidence class for the minidregg side uses the README's five words: authored, compiled, executed, integrated, deployed (README.md:63-65). Cost uses S (days), M (a few weeks), L (more). "New" marks a proposal that does not exist yet. A path with a line number is something I opened today. Statements taken from the scout memos carry "(B)" for `notes/B-minidregg-map.md` or "(F)" for `notes/F-revision-system.md`, with the memo's own line numbers; I did not re-open the Lean files they cite.

Paths, shortened: `MD` = `/Users/ember/dev/minidregg`, `EK` = `/Users/ember/dev/EKOS`, `VK` = `/Users/ember/dev/verekos`.

One fact shapes everything. The public node runs candidate `5688775a`. Its documents have `new`, `show`, `append`, `edit`, `link`, `backlinks`; it has no rooms, no chat, no Hermes, no Studio route, no search, no `--at`, and on 2026-10-03 no friend was enrolled (MD/README.md:69; MD/deploy/shell/FRIENDS.md:20-37). So "what a friend can do today" is small, and EKOS's value there is mostly on the reading side.

Two design choices from `VK/docs/design/VEREKOS-DESIGN-2026-10-19.md` are assumed, not re-argued:

- The compiled layer is published unsealed or kept reader-local; sealing stays for imported sources (design 2.1, mismatch 2).
- Patch merge never applies to compiled output; a branch merge re-runs the compile over merged sources (design 2.1, mismatch 3; F section 5).

## 1. Catalogue A: what minidregg gains from a knowledge compiler

Each entry gives: the capability; the EKOS mechanism; the minidregg mechanism it rides on; cost; evidence class of the minidregg side.

### A1. Documents and the docuverse

**Capability.** Compile a friend's documents into a queryable graph: sections, defined terms, stated facts, links. Then give three things the node does not have: ranked search (`ekos_search`, lexical plus vector, rank-fused), multi-hop "what depends on this document" (`ekos_impact`), and a conflicts view where two documents state different values for the same named fact. Every answer cites a revision pin.

**EKOS mechanism.**
- `localdocs` plugin reads Markdown, text and more (EK/CLAUDE.md, Connectors paragraph); `document_semantics_analyzer` and `Section` objects (EK/CLAUDE.md:107).
- SEARCH/QUERY/REASON engine, RFC 0118 (EK/ekos/docs/rfcs/0118-compiled-knowledge-query-engine.md:1-9).
- Impact traversal and `ekos_conflicts`, RFC 0172 (EK/CLAUDE.md:109, :168-185).

**Rides on.** `DocumentRecord`, `AtomRecord.revision`, `LinkRecord`, snapshot transclusion (F:122-126; B rows 1-3). Backlinks are already deployed (MD/README.md:69). The new part is an importer that turns a signed read into EKOS's observation artifacts.

**Cost.** M for the reader-local version (an importer plus a pin checker, no world change). L for the in-world version (a law package and import family, design 2.1). An honest wrinkle: EKOS's conflict detector compares *stated attributes* of objects (a SQL column type, a seed row); prose has none until an LLM pass or a field convention extracts them. So the conflicts view works on structured fields at first (documents with `FieldRecord`s, B row 1) and on prose only through an opt-in LLM pass, which EKOS already treats as a proposal.

**Evidence class.** Documents `new/show/append/edit/link/backlinks`: deployed. Transclusion, `--at`, search, marks in the shell: main only; JDV and J12W have no recorded run (F:220, :294).

### A2. Rooms and chat

**Capability.** A room carries a corpus. A room-scoped compile gives the room a "what do we know" page and a durable record of which messages were corrections of earlier statements. Chat messages are not documents the compiler should trust; they enter as `T0` claims (below), never as facts.

**EKOS mechanism.** Session memory's inbox-then-pipeline split and trust tiers (EK/ekos/docs/rfcs/0151-agent-session-memory.md:11-25); `ReadScope` per source for "this room only" (EK/CLAUDE.md:110).

**Rides on.** Rooms and the workroom template; chat verbs `say`, `tail`, `topic`, `pin` (README.md:70-71).

**Cost.** M on top of A1, but blocked: nothing joins chat to a native Host in any recorded run.

**Evidence class.** Rooms: integrated on development worlds, not the public node; the private-rooms driver is red on main (0 of 88 rows) (README.md:70). Chat: compiled, no recorded PASS (README.md:71).

### A3. Residents and Hermes

**Capability.** A resident answers from compiled objects, each with an evidence pin, and says "I cannot tell" when the pin is stale. It writes what it learns as session notes anchored to objects; the notes go stale when the object changes, and only a human promotes them. The answer to "why did you say that" is a list of pins, not a transcript.

**EKOS mechanism.**
- `ekos_query` / `ekos_retrieve` return a compiled answer and an inspectable plan without a model (EK/CLAUDE.md:168-175).
- Session memory: inbox, `T0` claims, anchors with per-kind fingerprints reporting `fresh / changed / orphaned / unanchored` (RFC 0151:11-25).
- Human-only promotion: `ekos session review` has no MCP twin (RFC 0151:17).

**Rides on.** Resident context is "selected from current participant-authorized signed document reads", with summaries carrying exact source/root/capability pins that invalidate on revocation or source change (MD/docs/RESIDENT-CONTEXT.md:3-18). "External model output is authored prose or a proposal, never proof of truth" (RESIDENT-CONTEXT.md:39). The two systems already agree on the rule; EKOS adds the retrieval and the typed staleness. `ResidentActivityRevision` is the closest minidregg model of EKOS's supersession (F:274).

**Cost.** M. The seam is small: a resident's tool list gains the read-only EKOS tools through the same authorized view, and notes go through `doc review`-style proposals (RESIDENT-CONTEXT.md:31-35).

**Evidence class.** Context projection: compiled (scoped Lean, three narrow Rust tests); "do not establish live recovery behavior" (RESIDENT-CONTEXT.md:41-53). Hermes in a room: executed with a scripted provider, off on the public node (README.md:78). `ResidentActivityRevision`: authored, opt-in `ResearchWip` (F:224).

### A4. Seats and invitations

**Capability.** Mostly none directly. The one real gain: a contract package's *offers* become compiled objects you can query ("which open seats want what I hold"), with the seat law shown in words beside each. Not a reason to build anything.

**EKOS mechanism.** `ekos_state` / `ekos_ekl` over imported seat records (EK/CLAUDE.md:113).

**Rides on.** `Kernel/Seat.lean`, `Invitation.lean`, `SeatStore.lean` (MD/docs/SEATS.md:10-16).

**Cost.** M for an importer, low value. Listed for completeness.

**Evidence class.** Integrated on scratch worlds, Host ops 215-219 (README.md:75; SEATS.md:14-16).

### A5. SPK hosted apps (grains)

**Capability.** A grain's declared dependencies and the documents it reads become edges in the same graph, so "what breaks if I stop this app" is one `ekos_impact` call. Also: an EKOS grain, that is an EKOS compile run as a sandboxed app under Mini authority whose only output is admitted declarations. This is the heavy way to do A1 and is discussed under traps (section 5, T3).

**EKOS mechanism.** `dependency_analyzer`, `cicd_analyzer`, `crate_topology_analyzer` for a grain's own manifest (EK/CLAUDE.md:107).

**Rides on.** The application state machine and its four counters (F:185-188; MD/docs/SPK-LIFECYCLE.md:13-30).

**Cost.** M for the graph; L for the grain.

**Evidence class.** Compiled; install, start, supervised restart and export integrated on development worlds, 44 of 44 rows; no application has yet served a browser session (README.md:76).

### A6. Objective Bend packages and `.obend` sources

**Capability.** A compiled map of a package: definitions, `compose`/`requires`, which package pins which. Studio-style questions become queries: "what composes ReviewBase", "which objects pin this package", "what changes if I edit this definition". EKOS's `Calls` and `DependsOn` edges are exactly this shape.

**EKOS mechanism.** The Rust, Python and Elixir analyzers recover a symbol graph with `Calls` edges (EK/CLAUDE.md:107). There is **no Lean or Bend analyzer** in `EK/ekos/plugins` (I listed it). So an `.obend` analyzer is **new**. It would be an untrusted parser: the real front end is a Lean program and a "named trusted boundary" (MD/README.md:98-101). The sound design reads the front end's own output (the `objective-front` command, MD/docs/STUDIO-SOURCE-WORKSPACE.md:29-30) instead of reparsing source.

**Rides on.** `ObjectRecord` with its package `pin` (MD/docs/OBJECTIVE-BEND.md:394-420), package ancestry and `SpecMeta` metadata (OBJECTIVE-BEND.md:104-135).

**Cost.** M. Value is real only once someone else writes `.obend`; today the example is two files (README.md:103-104).

**Evidence class.** Core4 semantics and checker: compiled. Native admission: integrated on scratch worlds, not deployed (README.md:73-74).

### A7. Studio

**Capability.** Beside the editor, a panel showing what depends on the module you are editing (importers, objects pinned to it), and which of your saved revisions an earlier answer was pinned to. Forks keep ordinary document references, so the panel works across a fork.

**EKOS mechanism.** A6, plus `ekos_diff` / `AS OF` for "what changed between these two composition revisions" (EK/CLAUDE.md:113, :170).

**Rides on.** Composition revisions, exact-revision comparison, retained stale drafts (MD/docs/STUDIO-SOURCE-WORKSPACE.md:16-20, 33-37).

**Cost.** M on top of A6. Also a prerequisite the Studio doc states: its prototype declarations "feed nothing" until rewritten against the Objective front end (STUDIO-SOURCE-WORKSPACE.md:39-45).

**Evidence class.** Authored; executed on lane builds only; no member-reachable route (README.md:72).

### A8. The agreement mesh

**Capability.** None worth claiming. EKOS can show the mesh's own docs and Lean modules as a graph (A6 applies). Replicating an EKOS ledger over the mesh is a trap (section 5, T2).

**Evidence class.** Compiled safety theorem; four replicas on one host, one failure domain; liveness not established (README.md:80).

### A9. The durable store and history

**Capability.** A shared "what changed since" for a world: `ekos_diff` and `AS OF` read as a timeline of admitted operations, with receipts as the evidence on each entry. EKOS's own ledger keeps `TxId` as ordering authority with wall-clock as metadata (F:229-231), which matches a linear hash-chained log indexed by height (F:205-207).

**EKOS mechanism.** `ledger` versions as assert/retract fact ops; `diff` as footprint union (F:229-231; design P2).

**Rides on.** `durable_log(height, record, tag)`, checkpoints, `VersionEventRecord` (F:205-207; B row 4).

**Cost.** S/M as a read-only importer of the event log. Gain is modest while the public node has four test keys.

**Evidence class.** I found no separate row for the durable store in the README table I read (rows 69-84); `docs/DURABLE-STORE.md` exists. Treat as: used by the deployed Host, not separately classed. Unverified.

### A10. The public node, for friends

**Capability.** Three things, all on the reading side:
1. A **find** that works across everything the friend can read (the node has no `search`; FRIENDS.md:25).
2. A **what-would-change** before an edit: the documents that link here, two hops out, with the stale-pin count (`backlinks` is one hop).
3. A **disagreement list** between the friend's own documents on named fields.

**EKOS mechanism.** `ekos_search`, `ekos_impact`, `ekos_conflicts`, run on the friend's machine over their own reads. No node change, no new authority. Proxy mode (keeps the key on the friend's machine) exists only on main (FRIENDS.md:27); on the public node the friend's key lives on the box (FRIENDS.md:46-60), so the first version reads through the shell.

**Cost.** M. See section 4.

**Evidence class.** Deployed for documents and boards (README.md:69); no outside member enrolled.

## 2. Catalogue B: what EKOS gains from minidregg's world

"Upstream" means: a Rust change EKOS could make without minidregg. "Inside" means: only meaningful in a world with the mechanism.

### B1. Principals with capability lineage

**Addresses.** P10 (human-only decisions) and issue #14 (string scans a rename evades), #16 (review decision records no actor, id is random).

**What it gives.** A review verdict names who made it, under which grant, valid at which height, revocable. EKOS's "human" is a session flag; here it is a credential path and "human" is an issuance policy (B row 13).

**Upstream?** Partly. #14 already proposes a `Reviewer` capability type with a private constructor; #16 proposes recording reviewer and note on the evidence a decision event cites (VK/notes/upstream-issues.md, items 5 and 7). That is a Rust change. The revocation, epochs and lineage are **inside** only.

**Cost.** S for #16, M for #14's type; L for lineage.

### B2. Receipts and retained outcomes

**Addresses.** P1/P3: EKOS evidence says where a fact came from; it does not say which admitted operation wrote it. A receipt is "evidence of the particular admitted operation" (MD/docs/README.md:57).

**Upstream?** Half. EKOS could write the commit's content signature and `TxId` into each fact's provenance (new, S). The exactly-once, replayable property needs the world.

### B3. Admission laws (decidable predicates over old state, new state and the request)

**Addresses.** P3 (evidence for every conclusion does not hold: items 3 in the issue list, #12) and P9.

**What it gives.** "Every `Custom` object and every relationship carries non-empty evidence" stops being a convention and becomes a refusal at write time. Whether `Pred` can say "this list field is non-empty" I could not verify; B warns the enforced fragment is small (no nested paths, fixed reference shapes, OBJECTIVE-BEND.md:755-757).

**Upstream?** Yes, and cheaper: #12 proposes a helper plus a semantic-crate test; an append-time check in `ledger` (new, S/M) makes the same rule a refusal. The world adds nothing except moving the check out of the writer's hands.

**Not this:** a regex redaction law. It does not fit `Pred`; redaction stays in the import family (B section 3, row "Admission laws").

### B4. Sealed fragments (encrypted, rewrappable)

**Addresses.** P9, from the other side. EKOS drops secrets at the door; minidregg seals them and keeps them.

**What it gives.** Source material that must be kept (regulated text) could stay as sealed evidence a reader with the right key can reopen, instead of being lost to redaction.

**Upstream?** No. Inside only. B judges it the wrong default for a corpus built to be queried broadly (B section 3, last row). **Not recommended**; listed because it sounds like a fit.

### B5. `ObserverLens` views

**Addresses.** P5 (Runtime read-only is a convention) and #13.

**What it gives.** Read-onlyness as the type of a lens, with `project_eq_of_clean` and `underDeclared_lens_impossible` (B section 2, row 14).

**Upstream?** Yes. #13: split a `KnowledgeReader` out of `KnowledgeStore`, have `Runtime`, EKL, graph export, docs-gen and MCP read tools take `&dyn KnowledgeReader` (VK/notes/upstream-issues.md, item 4). That is the Rust shadow of the lens. The theorem stays inside.

**Cost.** S/M. Already filed.

### B6. `ConflictRecord` (stored conflicts with provenance)

**Addresses.** P7 and P13. EKOS prints a branch divergence and does not persist it (F:235; upstream-issues.md, "Noted, not filed").

**What it gives.** A stored record: field, base, alternatives each with author and operation, regime (F:129).

**Upstream?** Yes: persist `merge_branch` divergences as `Custom("ConflictingEvidence")`-style objects with `Disputes` edges (new, M). Three things to copy as requirements, not code: a coverage obligation (minidregg's merge has none, F:175; EKOS's `compare_members` is more complete), alternatives stored as references not inline values, so a restricted reader does not see a source it may not (F:248), and a resolve action (neither has one, F:166).

### B7. Revision-pinned transclusion (`transclusion_pinned`)

**Addresses.** P3 and P12: an evidence pin that shows the same bytes or says `moved`, never other bytes (F:180, :275).

**What it gives.** EKOS evidence is `SourceLocation{path,line}` plus a fragment (F:245). A line number drifts under unrelated edits. A pin that stores the revision and compares at read time says "this evidence has moved" honestly.

**Upstream?** An approximation, yes: store a fragment hash with each evidence record and have the read path report `unchanged / moved / gone` (new, M). Whether EKOS's evidence read paths already compare fragments, I did not check. The stronger version (stable atom identity so pins survive unrelated edits) needs the importer from A1 and is inside.

### B8. `PlanBinding` footprints and commutation

**Addresses.** P2 (`diff` is the union of write footprints) and concurrent `commit`s.

**What it gives.** `independent_commute`: two plans that do not read what the other writes can land in either order (F:112, :273).

**Upstream?** Weakly. EKOS takes a writer lock (`fact_ledger::hold_write_lock`, EK/CLAUDE.md:120) and serializes. A footprint check could let two disjoint-source commits proceed together (new, L). Low value until EKOS has concurrent committers. Inside for the theorem.

### B9. The causal version DAG

**Addresses.** P13 and P2.

**What it gives.** Versions with parent lists; a frontier instead of "the latest" (F:114-121).

**Upstream?** EKOS's `TxId` is linear; adding parents is a model change (new, L), and F notes `object_at` on a DAG becomes a frontier question (F:244). Keep EKOS linear and state branches separately, as the design already does. Mostly inside.

### B10. Seats and invitations (single-use, assayable right to play a role)

**Addresses.** P10, shape only. A pending `SameAs` review is an offer; the reviewer holds the one invitation that can spend it; spending is once (`spend_once`, SEATS.md:22-26).

**Upstream?** The idea, yes: a review ticket with one holder and one use (new, M). The offer-safety law (`give` refunded or `want` met) has no EKOS counterpart; do not import it.

### B11. Pricing (the public tariff and funded admission)

**Addresses.** EKOS's metered-call switch per tenant (RFC 0183, EK/CLAUDE.md:120).

**What it gives.** A refusal when a compile runs away, with a stated envelope.

**Upstream?** EKOS already caps calls per tenant and by `chat_max_tool_calls` (EK/ekos/docs/rfcs/0187-chat-with-ekos-tools.md:13-17). A tariff over *passes* is new (M) but needs a unit of work EKOS's whole-corpus passes do not have (B section 4, mismatch 3). Low value.

### B12. Objective Bend activities (yield a Plan, resume with a Response)

**Addresses.** The review lifecycle. A resolver yields "propose SameAs for X, Y at score s" and waits; a human response resumes it (B section 5; OBJECTIVE-BEND.md:334).

**Upstream?** No; it is a language feature. Inside, and blocked: Core4 has no digest term, no cross-package reference, no termination bound (OBJECTIVE-BEND.md:810-836).

### B13. The agreement mesh

**Addresses.** Nothing EKOS has promised. See T2.

### B14. Durable receipt continuity ("a lost reply keeps the original operation and its exact retry")

**Addresses.** Retry of a failed `commit` or `ekos_identity_review`. EKOS appends review events with random ids (#16), so a retried review is a second event.

**Upstream?** Yes, in spirit: deterministic event ids for review decisions (already in #16's proposal). Cost S.

## 3. Ranking

Ratio of value to cost, as I judge it. Five picks, then the first build.

**1. Reader-local compile with pinned answers (A1 + A10 + B7's approximation).**
The value is the most visible one: a friend gets find, impact and a disagreement list over documents they already own. The cost is a Rust importer and a pin checker on the friend's own machine, with no change to the node or the kernel. It also dissolves the biggest mismatch in the design (compiled corpus versus sealed-by-default): the ledger is the reader's, built from their own authorized reads, so nothing is published that the world did not already let them read.

**2. Persist branch conflicts (B6, upstream, new).**
EKOS prints a divergence and drops it; storing it is a contained change in `merge_branch` that fixes a stated gap in P13. It borrows three requirements from minidregg's record (provenance on each alternative, references not inline values, a coverage rule) without borrowing its code. It also gives the VerEKOS `Branch` kernel something real to state.

**3. Read-only trait (B5, #13, already filed).**
It turns "the Runtime is read-only" from a convention into a type for the price of splitting one trait. It helps every later feature in this note, because a resident-facing tool surface (A3) is only safe if the read surface cannot write. Maintainers already have the draft.

**4. Reviewer identity and deterministic review events (B1 + B14, #16).**
Small change, large honesty gain: a review decision says who and why, and a retry is not a second decision. It is the first step toward a credential-based human-only rule inside a world.

**5. Resident grounding with anchored session notes (A3).**
This is the entry that makes the world feel amplified: a resident that answers from pins and says when they are stale. It ranks fifth because it is blocked on Hermes being on a real node and on the resident context having a live receiving run, neither of which exists (README.md:78; RESIDENT-CONTEXT.md:41-53). The seam is small once those exist.

**Build first: number 1.** It needs the least permission from anyone (the friend, their key, their machine), it works on what is deployed (documents and backlinks), and it produces the scoreboard material the design asks for: a control (EKOS's own output on the same documents) and a pin check that can be wrong in measurable ways. Entries 2 to 4 are independent upstream work that can proceed in parallel but do not show anyone anything.

## 4. A sketch: what a friend would see (entry 1)

This is a proposal ("new"). Nothing here exists. It assumes proxy mode or a hosted-shell session, a friend already enrolled (none are today), and EKOS installed on their machine.

Mira has about forty documents on the node: a trip plan, a budget, notes for a game she runs, and a few drafts that link to each other. She types:

    mini ekos sync

The tool reads her documents with her own signed reads, one at a time, and records for each paragraph the document, its revision and its atom. It runs EKOS over the copies, in a folder on her laptop. It says: "40 documents, 312 sections, 96 links, 11 named facts. 0 documents I could not read."

She types `mini ekos find "ferry"`. She gets six hits, ranked. Each line ends with a short pin: `trip-plan r14 atom 8`. Under the third hit it says: **moved**. The paragraph the answer came from has been edited since; here is the current text, here is what the answer said. Nothing is shown from a document she cannot read.

She types `mini ekos before "trip-plan"`. It lists what links to the trip plan, one hop and two: the budget, two drafts, and the game notes through a draft. Next to each, how many of its own pins would go stale if she rewrote the plan's second section.

She types `mini ekos disagree`. It finds one: the trip plan says the ferry leaves at 9:40 and the budget draft says 10:15. Both are shown with their pins, side by side. It does not say which is right, and it does not edit anything. If she fixes the plan with `doc edit`, the next `sync` shows the disagreement gone and records that the budget still says 10:15.

What she cannot do: she cannot publish this graph to anyone, and her friend Jo cannot ask her laptop a question. If she wants Jo to see it, the way is a document she writes herself on the node. Later, a resident could be given the same read tools (A3), through the same authorized view.

What this sketch deliberately leaves out: any summary written by a model. If she opts in, a model's text arrives marked as a proposal with its cited pins, and the tool refuses to show a summary whose pins do not all check (this is EKOS's cite-or-drop rule, EK/CLAUDE.md:109, `semantics_llm.rs`, and minidregg's own rule, RESIDENT-CONTEXT.md:15-18).

## 5. Three entries that sound exciting and are traps

**T1. Write the EKOS passes in Objective Bend so every compile is an admitted, re-executed program.**
It sounds like the whole point of both projects. It is blocked by the language's own open list: no digest term callable from source (so content signatures cannot be computed), no cross-package or dynamic reference (so a resolver cannot walk arbitrary objects), no termination or resource bound for a well-typed program, and the front end is a trusted boundary (B section 5, citing OBJECTIVE-BEND.md:810-836). A pass written there would be a reconstruction of the resolver in a language that cannot address the corpus it resolves. The cheaper path is a Lean function behind a law, which is where redaction already lives. If we pay for it, we pay for the same thing twice.

**T2. Put the compiled ledger on the agreement mesh.**
It sounds like "replicated knowledge." The mesh has a safety theorem over a Lean model, four replicas on one host (one failure domain), and liveness not established (README.md:80). It orders *semantic receipts*; it does not define document merge (F:197). EKOS's own cluster work (RFC 0111/0113) already has partitioned and distributed storage with a gateway. And compiled output is a function of sources, so replicating it adds nothing that replicating the sources does not. We would be paying consensus costs to carry a derived value.

**T3. One SPK grain per connector (and the EKOS compile as a grain).**
It sounds like the cleanest isolation story, and it is the one the first design reading proposed. It is heavy: root broker, systemd units, generations, recovery protocols (B row 8; SPK-LIFECYCLE.md:115-130), a tenancy defect on hbox where the broker runs as root (SPK-LIFECYCLE.md:8-10), and no application has yet served a browser session (README.md:76). A fetch-and-parse step needs a fraction of that isolation. It also moves parsing out of admission's sight, which is the entry-trust problem the design already named. Do it last, after a reader-local version has shown what the compile needs from the world.

Honorable mention (not in the top three, same family): sealing the compiled corpus (B4), and letting a resident auto-resolve conflicts (it breaks the human-only rule both sides keep).

## 6. What I could not verify

- **No EKOS analyzer has been run over minidregg's Markdown or `.obend`.** Every claim of the form "EKOS would find X" is a prediction from the crate map and RFCs.
- **EKOS on prose.** The conflicts view needs stated attributes. I read the `conflicts.rs` description in CLAUDE.md and the memo; I did not open the document-semantics pass to see what facts it extracts from plain paragraphs.
- **Whether `Pred` can express "non-empty list"** or the other laws proposed in B3.
- **Whether EKOS evidence read paths compare fragments** (B7). I did not open them.
- **The durable store's evidence class** (A9). Not in the README rows I read.
- **Proxy mode on the node.** FRIENDS.md says the public node's 5688775a source has none (FRIENDS.md:27). So the sketch needs main or a later candidate for the key to stay on the friend's machine; in a hosted shell the first version reads through the shell and the operator can read the key (FRIENDS.md:46-60).
- **Lean citations in section 1 and 2** come from memos B and F. I opened the READMEs, SEATS, RESIDENT-CONTEXT, STUDIO-SOURCE-WORKSPACE, the heads of OBJECTIVE-BEND, SPK-LIFECYCLE, DISTRIBUTED-DESIGN, the performance plan and FRIENDS, and the EKOS RFC heads. I did not open any `.lean` file.
- **Cost labels** are my judgment, not measured.
- **`OBJECTIVE-BEND-EVENTS.md` and the performance plan** I read only at the head; I use the performance plan only for its target "merge/settlement proportional to compared frontier/delta, not full history" (MD/docs/HYPERDOCUMENT_PERFORMANCE_PLAN.md, intended-shape table), which a reader-local compile should respect when it re-syncs: re-read changed revisions only.

A small poem, since this note is about two projects reading each other:

    one keeps every fact it was told,
    one keeps every promise it could price;
    the pin says "same bytes, or I moved."  ( ˘▾˘ )
