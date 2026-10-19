# 01. EKOS inside the docworld: a law package, a schema, an import family

Design lane, 2026-10-19. I only read files; nothing was built or run. Names marked
**(new)** are my proposals. Every other name is quoted from source and cited as
`path:line` against today's checkouts. Short forms: `HD` = `/Users/ember/dev/minidregg/Theory/Hyperdocument.lean`,
`HDO` = `.../Theory/HyperdocumentOperations.lean`, `CR` = `.../Kernel/ContentResource.lean`,
`CRV` = `.../Theory/CanonicalReactiveView.lean`, `OB` = `.../docs/OBJECTIVE-BEND.md`.

**Summary.**
1. EKOS fits in a minidregg world with **no kernel change**. Each compiled object becomes one content cell under a schema. Properties live in `inlineObject` atoms, evidence is snapshot transclusions of imported source statements, and edges are `LinkRecord`s. The laws are written as document laws in the deployed `doc new --law` shape.
2. Four scout claims are wrong in ways that change the design. No deployed action writes a `FieldRecord`. An annotation cannot anchor to another document's atom. "Sealed by default" governs what a receipt discloses, not encryption. A grain does not submit declarations.
3. The compile cannot be *admitted* by re-execution without a kernel change. Without one, the world admits it on the compiler's authority and laws limit what it may write. Re-execution becomes a signed attestation that a lens reports as `replayedDeterministic`. Read scope is enforced twice: by observe grants (admission) and by a lens property that follows in one line from `ObserverLens.locality`.
4. minidregg gains six things. It can answer "what depends on this" with evidence, and Hermes can read compiled knowledge with exact pins. Its `claim`s stay separate from its `law`s, docs report their own staleness, its README evidence table is checked against journey results, and resident notes are isolated from every query lens.
5. Real costs: one cell per object, every imported byte kept forever, redaction outside admission, no resolve action, and transclusion with no recorded run on a real Host.
6. First slice: `ecommerce.sql` plus a 6-line conflicting fixture on a scratch world, three laws and seven receipts. It is laid out in §5, so a lane can build it.

---

## 0. Four corrections that change the design

These are disagreements with the scout memos and with design revision 2. Each one cites a line.

1. **Properties cannot be `FieldRecord`s in the deployed world.** Design §2.1 row 1 and lane B row 1 put typed properties in `FieldRecord`s. Neither action grammar can write one:
   - `HDO` `Action` is `create | editAtom | link | transclude | mark | annotate` (`HDO:80-86`).
   - The deployed `CR` `Action` has fourteen constructors, and none of them touches `.fields` (`CR:249-285`). A grep of `CR` for `.fields` or `.conflicts` finds nothing.
   - The only writer of `.fields` is the compiled merge, through `FieldPlan.ops` (`/Users/ember/dev/minidregg/Kernel/HyperdocumentMerge.lean:165-175`), and no Host code calls it (lane F §4).
   - Also, `FieldOwner` is `document | element` only (`HD:447-450`), so an annotation cannot own a "confidence" field (lane B row 3).

   **So properties go in an `AtomKind.inlineObject (schema : Digest)` atom (`HD:294-298`)**, which the deployed `createAtom` writes (`CR:1023-1028`).
2. **Evidence cannot be an annotation on the source.** Deployed `annotate` anchors to an atom *of the document being written*. `pinCheck progress.1 document atom revision` (`CR:1044-1047`) refuses any other document's atom. A compiled object therefore cannot annotate the source it came from. **Evidence is a snapshot transclusion**, which is the one cross-document pin (`CR:1050-1059`). On this point design §2.1 row "KirEvidence" was right and lane B row 3 was not.
3. **"Sealed by default" does not mean "encrypted by default".** `DisclosureDecision` is "what this accepted effect actually discloses" (`/Users/ember/dev/minidregg/Theory/AcceptedCellEffect.lean:57-66`), and the hyperdocument family fixes it to `sealedOnly` (`HDO:462-465`, `:487`).
   - That says what a receipt reveals. Readers still read cells through observe grants.
   - Encryption is opt-in for each atom or annotation (`sealedObject`, `AnnotationBody.sealed`; `HD:297`, `:610`).
   - So the Runtime needs observe grants, not key custody. Lane B §3 row "Encryption" and design §2.1 mismatch 2 overstate the conflict. A compiled corpus of plain text atoms is readable by whoever holds grants on its cells.
4. **A grain does not "submit admitted declarations".** Lane B row 8 says it does. I found no path by which a grain signs a Mini command:
   - SPK RPC is Sandstorm's Cap'n Proto session protocol, and "There is no listener, app launcher, HTTP facade, or Mini admission rule here" (`/Users/ember/dev/minidregg/native/spk-rpc/README.md:1-10`).
   - What exists is a *resident calling a grain*: `mini_application_api` needs "A fresh Mini agent dispatch permit and separate purse settlement … for every call" (`/Users/ember/dev/minidregg/native/grain-runtime/src/mcp.rs:389-390`).

   So a connector grain's output is a response that a principal's client may turn into a command. That makes it a proposal by structure, which is what we want, but it is not admission.

Two smaller facts used throughout:
- **One document per cell.** `ContentLaw` requires "every record that names a document names the same one" (`/Users/ember/dev/minidregg/Compiler/CanonicalCellRegistry.lean:615-621`; `CR:15-16`).
- **The client chooses the `AtomId`.** `createAtom` takes `atom : AtomId` from the command, and `allocate` refuses an address that is already present (`CR:489-495`, `:1023-1027`). This is what makes stable re-import identity possible without a kernel change.

---

## 1. Where it lives

**Recommendation: a separate Lean project, `~/dev/verekos/world/` (new), that requires minidregg as a Lake dependency pinned to one commit. It adds nothing to minidregg's tree.**

| Piece | Where | Why |
|---|---|---|
| Schema digests, codecs for the `inlineObject` payloads, atom-id derivation | `verekos/world`, Lean | Pure data and functions; they import `Theory.Hyperdocument` only |
| Import family (bytes → redacted statements → a `ContentResource.Command`) | `verekos/world`, Lean, emitting command bytes the `mini` client signs | `CR`'s `Command` type is the target. Importing `Kernel.ContentResource` pulls in `Compiler` (`CR:58-60`), which is heavy but allowed |
| Laws | `verekos/world` as Lean `Pred` values with `#guard` evaluations, rendered to the JSON the client installs | Writing the JSON by hand drifts; the shell's own templates are JSON (`/Users/ember/dev/minidregg/native/resource-client/src/shell.rs:142-162`) |
| Runtime lenses and their theorems (scope, session isolation, conflict visibility) | `verekos/world`, Lean | `ObserverLens` lives in `Theory/` (`CRV:46-54`), and "Theory/ imports only Mathlib and Theory" (`/Users/ember/dev/minidregg/README.md`, Layout table) |
| The decision kernels (`Scope`, `Identity`, `Conflicts`, `Redact`) | Isabelle, design §2.2, run as binaries by the importer, the compiler and the lens host | The seam of design §3 |
| A compile effect family, a resolve action for `ConflictRecord`, a field-write action | **minidregg's call, later** | Each is a kernel change. §4 says what each would buy. Slice 1 needs none of them |

Why not in-tree:
- minidregg says "nothing here has users or a compatibility obligation, so a format change is a rebuild" (README, Contributing). A pinned dependency makes that churn visible instead of silent.
- minidregg builds under a two-seat discipline with snapshots (README, "Build and verify"). A world package has no reason to occupy its gate.
- Nothing in slice 1 needs a new `Kind` in `LogicalLaw` (`CanonicalCellRegistry.lean:692-720`). Content cells already carry the one law every final cell runs.

---

## 2. The integration

### 2.1 Records

All schemas are `Digest`s in `DocumentRecord.schema` (`HD:844-849`). Every one below is **(new)**. The digest is derived like `CR`'s own constants (`contentDigest`, `CR:688-692`), with a fixed tag such as `"VEREKOS/SCHEMA" "ekos/object/v1"`.

**`ekos/source/v1`, one imported file.** Root container children (`ElementBody.container`, `HD:356-362`) are `atom` leaves, one per statement or definition, in file order.
- Each atom is `AtomKind.text` with the **redacted** statement bytes.
- A header atom first, `inlineObject "ekos/source-header/v1"`, carries `{source_key, path, redaction_table_digest, importer_version, pipeline_logic_version}`.

**`ekos/object/v1`, one compiled `KirObject`.** One cell, because `ContentLaw` allows one document per cell. Root children in this order:

| Child | Record | Contents |
|---|---|---|
| header | `inlineObject "ekos/header/v1"` atom | canonical bytes of `{kind, name, logical_key, compiler_version, sources}`. `logical_key` is the v5 seed EKOS already uses, e.g. `sql-analyzer-table:customers` (`/Users/ember/dev/EKOS/ekos/crates/recovery/src/sql_analyzer.rs:302-307`) |
| properties | `inlineObject "ekos/properties/v1"` atom | canonical JSON of `KirObject.properties` (`/Users/ember/dev/EKOS/ekos/crates/kir/src/lib.rs:193-202`): sorted keys, no floats (a confidence is milli-units, an integer) |
| evidence container | `ElementBody.container`, one per evidence record | an `inlineObject "ekos/evidence-meta/v1"` atom `{confidence_milli, pass, fragment_kind}` and an `embed` leaf: a **snapshot** `TransclusionRecord` (`HD:557-564`) whose opening pins `(AtomId × OperationId)` of the source statement(s) (`CR:92-97`) |
| one container per outgoing relationship | container | an `inlineObject "ekos/edge/v1"` atom `{kind, properties, valid_from, valid_until, status}`, that edge's evidence containers, and a `LinkRecord` (`HD:544-552`) with `source := some range-over-the-edge-atom`, `target := .document <to-object doc>` and `relation := digest(kind)` |

This answers a gap the scouts did not raise. `LinkRecord` has no properties and no evidence, while `KirRelationship` has both (`kir/src/lib.rs:382-403`). Anchoring the link's `source` range on a per-edge atom inside a per-edge container gives the edge its own properties and evidence, and it costs no extra cell. Backlinks come free: `Kernel/LinkIndex.lean` keeps `reverse : target ↦ [(cell, entry)]` "SERVED in a canonical order" (`/Users/ember/dev/minidregg/Kernel/LinkIndex.lean:1-25`). **That makes depth-1 `ekos_dependents` a deployed kernel index today** (`doc backlinks` is in the deployed shell, README Honest state row 1).

**`KirEvidence` (`kir/src/lib.rs:355-361`) maps as follows:**
- `location.path` comes from the source cell's header atom.
- `location.line` is **derived**: document order (`documentOrder`, `CR:918`) plus the pinned atoms' line counts. It is a view and is never stored, so line drift disappears.
- `fragment` is `renderSnapshot` of the opening.
- `confidence` is the meta atom.
- **The evidence id is derived** as `(object logical_key, pins)` and never minted. That neutralizes upstream issue #10 (random v4 evidence ids, `kir/src/lib.rs:364-366`) at the boundary.

**`KirEvent`.** For an object's own versions, use the derived `VersionEventRecord` (`HD:628-640`; derived by `Accepted.versionEventRecord`, `HDO:557-576`). EKOS-authored events (e.g. session `DeadEnd`) become an `ekos/event/v1` document whose header atom carries `{kind, subject_logical_key, payload}` and whose subject is a link.

**`ekos/manifest/v1`, the compile's current set (new).** One index document per project. It holds an external link per compiled cell with scheme `ekos-object`, authority = logical key, and path = cell id. This copies the room-index convention, where "an ordinary external link with scheme `mini-name` … is a binding" (`/Users/ember/dev/minidregg/docs/SHARED-NAMES.md:35-38`). It replaces `.ekos/semantics/current.json`. **It also fixes a defect design §1 names:** today "an object that a later compile no longer emits stays current forever". In the world, the compile `unlink`s its manifest entry (`CR:273-274`, tombstone kept), so it stops being current while its history stays.

**`ekos/conflict/v1` (new).** One per (subject, attribute), as in RFC 0172 (`/Users/ember/dev/EKOS/ekos/docs/rfcs/0172-conflicting-evidence.md:20-37`).
- The header atom is `{subject_key, attribute, conflict_type, signature}`.
- There is one container per claim: a meta atom with the normalized value, plus a snapshot transclusion of that claim's own statement.
- A `disputes` link points to the subject cell.

There is **no `chosen` field**. EKOS's "last read wins" survivor (`conflicts.rs:310-323`) is the input-order dependence design P7 flags. The world keeps minidregg's discipline: there is no survivor, and resolution is a separate act.

**`ekos/review/v1` (new), the human-only decisions.** This covers `SameAs` confirm/reject, conflict resolve/dismiss, semantics confirm, and session-claim promotion. Each decision is one appended container holding:
- a decision atom `{verb, pick, note}`;
- a snapshot transclusion of the reviewed thing's header atom.

**The transclusion is the carry-forward rule.** By `transclusion_pinned` (`CR:2565-2579`), the pinned snapshot "shows those same bytes or says `moved` — never other bytes". The compiler edits a conflict header atom only when its signature changes, so a resolution holds exactly while the signature is unchanged. When the signature changes, the resolution reads `moved` and the conflict reopens. RFC 0172's `carry_forward` stops being code and becomes a theorem we already have. The same pattern serves RFC 0151 anchors: `moved` is `changed`, and a tombstoned pin target is `orphaned`.

**`ekos/compile-run/v1` (new).** One per compile, append-only. It holds:
- input pins: one snapshot transclusion of each source header plus the read heights;
- the compiler identity (EKOS commit, `PIPELINE_LOGIC_VERSION`, `PREDICATES_VERSION`, redaction table digest);
- the output list `(cell, post root)`;
- the SHA-256 of the exact command bytes submitted.

### 2.2 The import family

One function, `importFile (new) : SourceKey → Path → Bytes → CurrentSourceDoc → Command`, runs in the importer's client before signing:

1. **Exclusion** before reading, with EKOS's built-in globs (`is_excluded_path`, A row 52).
2. **Redaction** of the whole file with the RFC 0043 table, the Isabelle `Redact` kernel's binary. The table digest is recorded in the source header.
3. **Split into statements** (DDL statements for `.sql`; definitions for code; sections for Markdown).
4. **Atom identity by structural key, never by content.** The atom id is `deriveIdentifier` over `IdPreimage .v1 .atom` (`HD:166-169`). Its payload is `(source_key, path, structural_key, occurrence)`, where `structural_key` is the same key EKOS uses for the object (`create-table:customers`). A statement with no name gets `anon:<sha256(normalized text)>` plus an occurrence index.
5. **Diff against the current document** (a signed read):
   - an unchanged statement emits nothing;
   - a changed statement under the same key becomes `editAtom` with the exact `before` (`HDO:36-42`), which moves its `revision`, so every pin on it renders `moved`;
   - a new key becomes `createAtom` plus an `editElement` move;
   - a vanished key becomes `editAtom … tombstone := true`;
   - a reordering becomes `editElement .move`.

   An empty command is refused (`empty_command_rejected`, `CR:1638`), so **a re-import of an unchanged file appends nothing**. That is EKOS's P1 idempotence, kept by the client not submitting rather than by a no-op law (lane F §5 row P1).

Two consequences:
- Pins on unchanged statements survive a re-import. A pin moves exactly when its statement changed, which answers design §2.1's "every re-import moves every pin".
- If the redaction table adds a pattern, the affected atoms change bytes under the same ids, so their pins move and the next compile re-pins. This reproduces EKOS RFC 0135 Part A's "a later redaction pattern … re-redacts unchanged source" (A row 54) with no extra mechanism.

**What admission sees, and what it cannot see.** Admission sees that the importer subject wrote these atoms (law L-src below). It does **not** see that redaction ran: `Pred` reads `Int` slots only (`/Users/ember/dev/minidregg/Pred/Core.lean:62-80`), and the content projection is counts and byte totals (`CR:1787-1820`). P9 therefore stays a client obligation, as it is in EKOS today. The difference is that there is now **one entry**. RFC 0043 counted two, and D2 found two more (`git blame` summaries and crate doc comments, design §5 items 9-10). In the world, a pass that reads anything not imported produces output that a re-execution from in-world pins cannot reproduce (§2.3). The fourth-entry-point class of bug becomes detectable, not just reviewable.

### 2.3 The compile as an admitted computation

**The declaration.** With no kernel change, a compile is:
- a batch of ordinary `CR` commands signed by the **compiler subject (new principal)**, one multi-target transaction per group of cells. Each transclusion carries an observe-only read of its source cell, or it is refused with `sourceNotCovered` (`CR:452-453`, `:1050-1052`);
- one `ekos/compile-run/v1` append.

Two properties follow from admission alone:
- *The compiler can cite only what it was granted to read.* Transclusion requires an observe read "against the transcluder's grant and the source's own policy at this height" (`CR:50-56`).
- *The evidence was current at admission.* `openingHolds` is checked, or the command is refused with `staleOpening` (`CR:454-455`).

**The laws** use the deployed shape: a cell has one law, it judges every verb, and content clauses sit under `request/verb == 2` (`shell.rs:142-162`). Slots come from `CR.project` (`CR:1787-1820`) and the common request slots (`/Users/ember/dev/minidregg/Kernel/ObjectRecord.lean:450-454`). Verb codes are as in the shell: observe 1, mutate 2, delegate 3, installPolicy 4, revoke 5.

| Law (new) | On | Clauses (all are `Pred` constructors, `Pred/Core.lean:169-211`) | EKOS promise |
|---|---|---|---|
| **L-src** | `ekos/source` cells | mutate ⇒ `memberOf request/subject [importers]`; installPolicy ⇒ `memberOf request/subject [owners]` | single raw-content entry (P9 shape) |
| **L-obj** | `ekos/object`, `ekos/conflict`, `ekos/manifest` | mutate ⇒ `memberOf request/subject [compiler]` ∧ `eq content/annotations 0` ∧ `eq content/marks 0` ∧ (`eq content/document-creates 0` ∨ `not (le content/transclusions 0)`); installPolicy ⇒ owners only | writes only by the compiler; **a birth must carry ≥ 1 transclusion** (a count form of P3); no agent can annotate compiled state |
| **L-rev** | `ekos/review` | mutate ⇒ `memberOf request/subject [human reviewers]` ∧ `eq content/atom-edits 0` ∧ `eq content/tombstones 0` | human-only (P10); decisions append and are never rewritten (the shell's `note` law, `shell.rs:153-154`) |
| **L-run** | `ekos/compile-run`, `ekos/replay-attestation` | `note` law ∧ subject ∈ [compiler] or [verifiers] respectively | an append-only audit trail |

The installPolicy clause matters. The shell's templates let verbs 1, 3, 4 and 5 pass (`shell.rs:157-160`), which means **whoever holds installPolicy on a review cell can replace its law**. The human-only guarantee rests on the compiler and residents never holding that capability.

**What the laws cannot say, stated plainly:**
- "≥ 1 transclusion" is a count. A compiler could transclude an irrelevant range. `Pred` cannot see a link's `relation` or an atom's bytes.
- Full P3 (every edge cites evidence that supports it) and P4 (determinism) are checked by re-execution.

**Determinism by re-execution, as an attestation (new).**
- A **verifier** principal, different from the compiler (a second machine, or the Isabelle-checked kernels), reads the compile-run's input pins `at` their heights and re-runs the compile. It compares the SHA-256 of the command bytes and appends an `ekos/replay-attestation/v1` that transcludes the compile-run header.
- A lens labels each compiled cell with minidregg's own `Liveness`: `live | replayedDeterministic | reconstructedApproximate` (`/Users/ember/dev/minidregg/Theory/ReactiveReceipt.lean:160-165`). The label is `replayedDeterministic` only when a matching attestation by a principal other than the compiler exists.
- A replay that differs is a counterexample to P4. These are the cases upstream issues #10 and #12 found by reading.

**The upgrade that would make it admission (a kernel change, not proposed for slice 1).** minidregg already admits one computation by re-execution: publication "re-runs the Lean front end on the package and publishes exactly `publishedCore`", and admission re-runs it again (`OB:671-697`). An `EkosCompile` family in the same style would have the Host re-run the Lean compile over the read sources and admit only byte-identical output. It needs the compile in Lean, not Rust.

There is also a law atom already in place: `ran (program : Nat)`, "this step's writes ARE the product of the Nock program … re-executed by the kernel on its own sample" (`Pred/Core.lean:199-203`). If a small pass (relation-id derivation, evidence-count) were a Nock program, `L-obj` could require `ran p` with no kernel change. That is speculative, and I have not checked any Nock program's size or cost.

Objective Bend is not the vehicle yet. Core4 has no digest term, no generic object reads and no termination bound (`OB:810-836`; lane B §5).

### 2.4 The Runtime as an `ObserverLens`

`ObserverLens L Observer View` has `dependencies : Observer → Finset (Address L)`, a pure `project` and a `locality` premise (`CRV:46-54`). The dependencies are a **finite set fixed per observer and independent of state**. A corpus that grows cannot be "all objects", so the observer must name the corpus. The definitions:

- `Observer` **(new)** = `{reader : PrincipalRef, scope : ReadScope, manifest : (cell id, height), query}`.
- `dependencies` = the addresses of the cells the manifest lists *and* the reader's scope admits (§2.5), plus the manifest cell's own addresses.
- `project` is EKOS's read path (`ekos_state`, `ekos_dependents`, `ekos_impact`, EKL) over that finite store. Pending `SameAs` edges and hypothesis edges are filtered as EKOS does (A row 17), with "pending" defined as "no confirming `ekos/review` decision".

What minidregg already proves, applied here:
- **`ObserverLens.project_eq_of_clean`** (`CRV:98-110`): a compile that writes none of a reader's visible cells provably leaves that reader's answers unchanged. EKOS's MCP result cache keyed by scope (`StoreCache`) becomes `Cache.advance` (`CRV:142-157`), which is correct by construction.
- **Read-only by type.** A lens has no write. Design P5 ("convention only") holds here by construction.
- **Completeness domain.** The manifest height in the observer is the completeness domain D-0005 asks for: "backlinks and query answers disclose their completeness domain" (`/Users/ember/dev/minidregg/docs/decisions/D-0005-hyperdocument-semantic-family.md:65-66`, `:114-115`).

**Session isolation as a theorem (new; a one-liner).** Exclude every cell whose schema is `ekos/session-note` from `dependencies`. By `locality`, no session note can change any Runtime answer. This replaces EKOS's guard test `every_object_returning_read_path_has_an_audited_session_decision` (EKOS CLAUDE.md, `session` row) with a proof that cannot miss a new read path, because a new read path is a new `project` under the same `dependencies`.

### 2.5 Read scope: admission first, lens second

**Admission layer (no lens needed).** A reader sees transcluded bytes "only through its own read of the source" (`CR:52-56`). So **evidence text is already scope-enforced by the kernel**: without an observe grant on the source cell there is no fragment.

To cover compiled properties too, put each source's import cells in one room, and give each single-source compiled cell exactly the audience of that room. Then P8's "everything follows the object" is enforced at admission for every single-source object. Targets carry `audienceEpoch, audienceRoster` (`/Users/ember/dev/minidregg/Kernel/DeclaredResourceController.lean:1149-1152`). I did not trace how rooms set them.

**Lens layer, for what admission cannot express.** EKOS's decision has four parts that need a lens:
- an object in two sources needs both;
- unattributed objects are hidden;
- deny wins over a path pattern;
- a per-call scope only removes (`/Users/ember/dev/EKOS/ekos/docs/rfcs/0181-read-scope.md:54-69`).

Grants have no intersection operator. An object's **origins** are the source cells named in its transclusion records (`StoredSourceIdentity`, `HD:486-491`) crossed with the source header's path, which is the RFC 0181 definition. Define `Vis(reader)` from those origins with the Isabelle `Scope` kernel, and require `dependencies observer ⊆ Vis(reader)`.

**Theorem `scope_noninterference` (new).**

```
∀ s₁ s₂, (∀ a ∈ Vis r, s₁ a = s₂ a) → project r s₁ = project r s₂
```

It is `locality` specialized. The proof obligation is the inclusion `dependencies ⊆ Vis`, and that is a finite check per observer. Composition, "a per-call scope only removes", follows because `Vis` under two scopes is an intersection. `PrivacyPortal.compose_noninterference` (`/Users/ember/dev/minidregg/Theory/PrivacyProfile.lean:94`) is the precedent shape.

**The honest limit.** Computing `Vis` reads the *origin* addresses of hidden objects, just as EKOS's `decide` reads evidence paths through the inner store (A row 43). So the theorem is noninterference **relative to origin metadata**. It is not breadstuffs' `FogOfWar` standard, where "a hidden cell is STRUCTURALLY ABSENT" (lane F §6). Reaching that standard needs origins stored somewhere a restricted reader's lens does not depend on, for example a per-source manifest. That is open.

### 2.6 Conflicts with references, not values

**Deployed shape (slice 1):** the `ekos/conflict/v1` document of §2.1. Its alternatives are transclusions, so **a restricted reader cannot read a claim's bytes without a grant on that claim's source**, even if the conflict cell were visible to them. The lens goes further: a conflict is visible iff *every* alternative's origin is in `Vis`. A reader who sees one source sees no conflict, so the conflict is structurally absent for that reader.

This is stricter than EKOS today, and it is a correction to EKOS rather than a mapping. Under RFC 0181, conflicts have no source and are simply "hidden from a restricted reader" (`0181-read-scope.md:83-88`), so a reader who can see both sources still sees no conflict.

**Target shape, once the merge is deployed:** `ConflictRecord` (`HD:473-481`) with **`ConflictAlternative.valueType := .reference .transclusion`**. `FieldType.reference (domain : IdDomain)` exists (`HD:427`) and its value is `Identifier .v1 domain` (`HD:436`). The value stored inline is then a `TransclusionId` in the same cell, not the claim. This is exactly "alternatives as references" with no new type.

Two things are needed before this shape can be used:
- **A coverage obligation.** `FieldPlan.two_sources_not_conflict_free` makes *two equal* sources a conflict too (lane F §2.2). The compile must therefore normalize first (EKOS's `normalize_type`, A row 31) and declare one source for agreeing values. VerEKOS's `Conflicts` kernel must state coverage, because the merge does not (lane F §3).
- **A resolve action.** None exists (lane F §2.3).

### 2.7 Identity

Lane F §5 has the right shape and I adopt it:
- An exact merge is a `SameAs`-relation `LinkRecord` with `status: confirmed` in its edge atom, canonicalized by the lens, so it can be reversed.
- A fuzzy match is the same link with `status: unconfirmed`, plus an `ekos/review` decision that confirms it.
- Traversal ignores a `SameAs` link with no confirming decision.

Atoms never change identity (`/Users/ember/dev/minidregg/Theory/StableRanges.lean:36-38`), so a re-key is impossible by construction. That settles design §2.2's "say whether an exact merge is a re-key or an overlay": in the world it is an overlay.

### 2.8 Connectors as SPK grains

The grain's job is **fetch and parse, never write**. The pipeline:
1. A Hermes resident (or the importer's client) calls the grain through `mini_application_api` (permit and purse per call, `mcp.rs:389-390`).
2. The grain returns candidate source bytes.
3. The **importer's** client runs §2.2 on them and signs.

Where this fits each kind of source:
- **Live sources** (GitHub, Confluence, ClickHouse) fit this pattern. The grain holds the external credential inside its sandbox, which is the custody story the SPK boundary was built for (`/Users/ember/dev/minidregg/docs/SPK-RESIDENT-PRIVILEGE-BOUNDARY.md:3-37`).
- **Filesystem sources** need no grain. The importer reads the files.
- **One grain per connector is wrong.** Each grain brings a root broker, generations and a recovery protocol (`/Users/ember/dev/minidregg/docs/SPK-LIFECYCLE.md:13-31`, `:115-130`). One "ekos-connectors" grain with several API routes is right. Lane 04 calls one grain per connector a trap, and I agree.

The tenancy defect is a precondition for any grain on a shared box: the broker runs as root, and unit names collide across Stores (`SPK-LIFECYCLE.md:115-130`).

---

## 3. The amplification: what minidregg gains

Lane 04 catalogues more. These are the six that follow directly from §2. Each names the surface it touches and whether that surface is deployed (README Honest state).

| Gain | minidregg surface touched | What exists today | What the integration adds |
|---|---|---|---|
| **"What depends on this?" with evidence**, for documents, Lean modules, `.obend` packages, grains and laws | `doc backlinks` (deployed), `Kernel/LinkIndex.lean`; Studio's source workspace (authored) | Depth-1 backlinks, complete over the accepted log (`LinkIndex.lean:1-25`). Studio "imports are composition choices; they grant no access" (`docs/STUDIO-SOURCE-WORKSPACE.md:3-7`) | Multi-hop `ekos_impact` as a lens over `LinkIndex.reverse`, with every hop citing a pinned span. Scouts today hand-grep claims such as "ViewMerge and LaceMerge are imported only by Theory.lean" (lane F §3) and KERNEL-TWIN-AUDIT's "Consumed only inside `Kernel/`". These become an `ekos_dependents` query over compiled Lean `import` edges, each edge transcluding its import line |
| **Objective Bend packages as knowledge**, keeping `law` and `claim` apart | Objective publication (integrated on scratch worlds); 126 `.obend` files (`find`, today) | `law` is ENFORCED; `claim` "elaborates to a hidden knot field … status `unchecked`. Nothing evaluates or discharges it" (`OB:722-746`) | An `obend` analyzer (new) that reads the **front end's own output** (the published core), never a re-parse, so the trusted boundary stays where minidregg put it (`OB:812-817`). Specs, methods, `compose` ancestry (`Extends`), `requires` (`DependsOn`), calls and sends (`Calls`). Package `law`s become facts and `claim`s become `status: hypothesis`, so a resident cannot present an unchecked claim as a law: traversal excludes hypotheses (A row 17) |
| **Residents grounded in compiled knowledge** | Hermes tools `mini_doc_context`, `mini_doc_show`, `mini_read_resource` (executed, J14); `mini-context-summary-v1` | "Whole-source-root invalidation is conservative; unrelated changes in the same cell can invalidate a summary" (`docs/RESIDENT-CONTEXT.md:58-59`) | Compiled objects are documents, so the **existing** tools read them with exact pins and need no new tool. A summary that pins a compiled object's properties atom is invalidated only when *that object's* compiled content changes. That is per-object staleness instead of per-root, without changing the summary format |
| **Conflicts across rooms, with provenance** | rooms (integrated), `ekos/conflict` cells | Nothing compares claims between rooms | The README's own "Honest state" table vs `docs/evidence/*/journey-result.json` is an RFC 0172 Phase 3 `doc_vs_data` case. Example: lane F found transclusion recorded as **FAILED** (J12C, 2026-09-30) while `CR:267` says the action has landed, and no later run is recorded. A compiled "evidence class" attribute per component, extracted from both, yields a conflict document whose two alternatives transclude the README row and the journey row |
| **Session memory anchored to revisions** | resident private notes; `Kernel/ResidentActivityRevision.lean` (ResearchWip, authored) | Same-author append revisions; "a malformed/stale/other-author revision … cannot change the current context projection" (lane F §6) | RFC 0151's tiers (T0 by default, T1 human-only) as an `ekos/review` decision, anchors as snapshot transclusions (`moved` = changed), and the session-isolation theorem of §2.4 instead of a guard test |
| **docs-gen of the world's own architecture, staleness built in** | rooms, documents (deployed) | "Dated design documents sometimes describe gaps that subsequent source has closed" (`docs/README.md:96-97`) | `ekos docs generate --layout curated` output published as hyperdocuments whose every claim is a snapshot transclusion. A rendered page *says `moved`* on the sentence whose source moved. Concentration risks (objects with 3+ `DependsOn` dependents) over the Lean import graph give the Executive Summary something real to say about `Kernel/` |

Two smaller gains:
- **Seats and invitations as the human review right.** An `Invitation` is single-use (`spend_once`, `/Users/ember/dev/minidregg/docs/SEATS.md:18-26`). Minting one "review this conflict" invitation to a named reviewer would make each review a spendable, assayable right, not just a subject check. This is a design target: invitations belong to Objective contract instances, and I did not check whether a review document could be one.
- **A compile account in the Book** funds compiles under the public tariff. Runaway compiles are then refused, not tragic (lane B §3).

---

## 4. What breaks or costs

| Cost | Resolution, or "open" |
|---|---|
| **One cell per object.** `ContentLaw` allows one document per cell (`CanonicalCellRegistry.lean:615-621`). A 6-table fixture is about 20 cells (objects, sources, manifest, conflict, reviews). The 95-partition Elixir workspace (EKOS devlog_144) would need 10⁵-10⁶ | Edges and evidence live *inside* object cells (§2.1), so the count is objects, not objects plus edges plus evidence. **Open:** how the Host behaves at 10⁵ cells. "room-scoped actions take seconds to minutes (… 224–270 s …)" (README Honest state) is the only latency number I found |
| **Storage of imported sources.** The content cell is RAM (`HD:901-908`), the durable log keeps every version (lane F §3, DURABLE-STORE), and an `editAtom` keeps the old bytes in history | EKOS already stores redacted observation artifacts in its `ArtifactStore`, so the bytes are not new, only their home. Statement-level atoms keep record overhead per statement, not per line. **Consequence, not a fix:** because history keeps old bytes, a secret that slips past redaction can never be removed. That is EKOS's own posture ("a prevention control, not a cleanup step", EKOS CLAUDE.md Key invariants) |
| **Pricing a whole-corpus compile.** Admission prices per command (`RequestEnvelope.cost`, `HDO:242-250`) | Incremental compile submits commands only for changed cells (§2.2 step 5). Cost is proportional to the delta, matching minidregg's own target, "proportional to compared frontier/delta, not full history" (lane F §6). **Open:** the price of the first full compile, and whether a multi-hundred-target transaction is accepted (I found no stated maximum target count) |
| **Sealed-by-default disclosure** | Mostly not a cost; see §0 item 3. Plain-text import atoms are read by grant. Only a source deliberately imported as `sealedObject` makes the compiler a keyholder, and only for that source |
| **Redaction does not fit `Pred`** | Accepted, as design §2.1 already says. Three mitigations: a single import entry (L-src); provenance (the table digest in every source header); and re-execution attestation, which detects passes that read outside the world. **Open:** admission-checked redaction. It needs either Core4 byte-string processing plus an Objective import method gated by `Pred.objectivePin` (`OB:713-718`), whose existence for content cells I did not verify, or a kernel family |
| **No `object_at`** | Per object it is a read of the cell "current or `at`" a height (`CR:52-56`). `all_objects_at(t)` reads the manifest at that height and then each listed cell at that height. **Open:** (a) mapping wall-clock time to a height (a clock cell exists, `ClockCell.slots` in the law projection, `DeclaredResourceController.lean:242-249`; I did not trace it); (b) `doc show --at H` has no recorded run (lane F §7); (c) on a causal DAG with two tips "the version at t" is a frontier, so P13 branches stay out of slice 1 |
| **No domain-time carrier** (`valid_from`/`valid_until`) | Stored in the edge atom and filtered by the lens. `Pred` cannot read atom bytes, so no law enforces it. That matches EKOS, which has "no query surface for validity windows yet" (design P11) |
| **No resolve action for `ConflictRecord`** | The deployed shape does not need one: resolution is an `ekos/review` decision, and reopening is `transclusion_pinned` (§2.1). **Open, minidregg's call:** a resolve action is a kernel change, and it is the only route by which `ConflictRecord` itself, not a document carrying its shape, becomes usable for EKOS |
| **Human-only depends on key custody** | The hosted shell's banner: "your signing key is a file on this box; root can read and sign" (`shell.rs:138`). So L-rev's reviewer must sign with `mini --remote`. Residents prepare and never land: "Preparing a proposal is never reported as installing its effects" (`RESIDENT-CONTEXT.md:97-99`; also `:37-39`). If Hermes runs "each line as the friend's account" under split tenancy (README Honest state), a subject check cannot tell the human from the agent. The reviewer subject must then be a different account from the one the resident uses. **Open:** confirm which subject a resident's landed command carries |
| **Transclusion on a real Host** | J12C **FAILED** on 2026-09-30, the action landed later, and the JDV/J12W drivers have no recorded run (lane F §4). Slice 1 step 0 checks it. Fallback: evidence as a `link` with a `.range` target (`HD:536`), with `(AtomId, revision)` kept in the meta atom and staleness compared by the lens. That loses the kernel-proved pin and keeps everything else |

---

## 5. The first slice

**The claim it demonstrates:** an EKOS compile of a real fixture lands as admitted cells with pinned evidence; the laws refuse the three wrong writes; a source edit makes the evidence say `moved`; a restricted reader cannot read a claim from a source they lack; and an independent replay reproduces the compile byte for byte.

**Fixtures.**
- `/Users/ember/dev/EKOS/tests/fixtures/ecommerce.sql`, used as is: 70 lines, 6 `CREATE TABLE`.
- A new file `~/dev/verekos/world/fixtures/legacy_customers.sql` (new, in the VerEKOS repo; EKOS is untouched):

```sql
CREATE TABLE customers (
    id     INT PRIMARY KEY,
    email  TEXT NOT NULL,
    name   VARCHAR(255) NOT NULL
);
```

The two `customers` tables share the id `sql-analyzer-table:customers` (`sql_analyzer.rs:302-307`) and disagree on `email`'s type (`VARCHAR(255)` vs `TEXT`). EKOS's `duplicate_definitions` emits exactly one conflict (`conflicts.rs:294-325`; RFC 0172 "Compared attributes"). `UNIQUE` differs too; whether that is compared is for the lane to observe, not assume.

**World.** A fresh private Store from a pinned manifest (`native/resource-client/journey.sh MANIFEST.json NEW_RUN_ROOT`, README "Build and verify"). Everything below runs from a driver in `~/dev/verekos/world/slice1/` and uses the `mini` client. Nothing is written into minidregg.

| Principal (new) | Holds |
|---|---|
| `importer` | mutate on source cells |
| `compiler` | mutate on object, conflict and manifest cells; observe on source cells; no installPolicy anywhere |
| `reviewer` | mutate on review cells; signs with `--remote` |
| `verifier` | observe on everything; mutate on attestation cells |
| `reader-shop` | observe on the `shop` room only |

Rooms: `shop` (`ecommerce.sql`) and `legacy` (`legacy_customers.sql`). Compiled single-source cells take their room's audience. The conflict cell and the merged `customers` cell take neither room: they are visible to the reviewer and verifier only. That is the lens rule of §2.6, enforced at admission by audience.

**Steps.**
0. **Check transclusion on this Host build.** Run the existing JDV transclusion journey. If it fails, switch to the §4 fallback and say so in the report.
1. Install laws L-src, L-obj, L-rev and L-run as `Pred` JSON through the installPolicy verb (4). Generate the JSON from Lean `Pred` values. I could not find the client command for a custom law: the shell offers only `index`, `draft` and `note` (`shell.rs:146-155`). Finding that path is the lane's first task.
2. Import both files (§2.2). Expect 7 statement atoms in `shop` and 1 in `legacy`.
3. **Compile.**
   - Read the source cells with signed reads and render them to a scratch directory.
   - Run `ekos init/build/recover/resolve/compile/commit` there. EKOS's CLI is unchanged.
   - Export `ekos graph export --format ndjson`.
   - The mapper (new, Lean or Rust) turns the ndjson into commands. It keys evidence by `(logical_key, pins)` and **ignores EKOS's v4 evidence ids**. It locates each table's statement atom by structural key, because EKOS's table evidence names the file, not a line: `SourceLocation::file(source_path)` with fragment `"CREATE TABLE {name}"` (`sql_analyzer.rs:503-506`).
   - Submit the commands as `compiler` and append the compile-run.
4. Replay as `verifier` from the compile-run's pins and compare command-byte SHA-256. Append an attestation.
5. Resolve as `reviewer`: pick the `shop` claim.
6. Edit `legacy_customers.sql` (`email TEXT` → `email CITEXT`) and re-import, which is one `editAtom`. Recompile.

**Receipts that prove it** (each is an Accepted receipt or a refusal naming its clause; a refusal "names the clause (`LawLeaf`)", `OB:414`):

| # | Expected | Proves |
|---|---|---|
| R1 | Accepted: birth of the `customers` object cell carrying a snapshot transclusion whose pins name the `create-table:customers` atom and its revision | P3 at admission; evidence = a pinned source span |
| R2 | **Refused** (L-obj): the same birth with zero transclusions | "a birth must carry evidence" is enforced, not conventional |
| R3 | **Refused** (L-rev): `compiler` appends a resolution to the review cell | human-only by law, not by a grep (P10, upstream issue #14) |
| R4 | **Refused** (`sourceNotCovered`, `CR:452-453`): `compiler` transcludes a source cell its command does not read | a compiler can cite only what it was granted to read |
| R5 | After step 6: the `customers` evidence pin from `legacy` renders `moved` (`transclusion_pinned`); the conflict header atom is edited (new signature); the step-5 resolution renders `moved`, so the conflict is open again | RFC 0151 staleness and RFC 0172 carry-forward as one kernel theorem |
| R6 | `reader-shop` reads the `customers` cell from `shop`: properties visible, the `legacy` transclusion does not render, the conflict cell is unreadable | P8 at admission; the conflict is structurally absent for a one-source reader |
| R7 | The verifier's SHA-256 of the command bytes equals the compile-run's; a second import of unchanged files submits nothing (empty command, `CR:1638`) | P4 on this panel; P1 idempotence by not submitting |

**What the lane reports:** the seven receipts (ingress bytes and frames, as the journey retains them), the step-0 result, the cell count, and wall-clock time per step. Also report every place the mapper had to guess. Each guess is either an EKOS evidence-location defect (an upstream issue) or a schema gap here.

**Explicitly out of slice 1:** grains, Hermes, branches (P13), `ConflictRecord`, Objective Bend, any Isabelle kernel other than `Redact`. If `Redact` is not built yet, the importer calls `ekos_common::redaction` through EKOS's own binary and records that in the source header.

---

## 6. What I could not verify

- **Nothing here was built or run,** including whether `transclude` works on any current Host (§4) and whether `doc show --at H` works.
- **How a custom `Pred` law is installed on a document from the client.** I found only the three shell templates (`shell.rs:146-155`) and the installPolicy verb number. The exact JSON spelling of `not` in client law JSON is also unverified (the shell's examples use `eq`, `le`, `memberOf`, `all`, `any`).
- **Which subject a resident's landed command carries** under split tenancy, and so whether a subject-based human-only law can tell a resident from its member.
- **Room audience mechanics** (`audienceEpoch`/`audienceRoster` on targets). I read the field names, not their semantics.
- **Whether Objective Bend methods can emit content-cell actions.** This decides whether `Pred.objectivePin` could gate imports without a kernel change.
- **The cost of a separate Lake project importing `Kernel.ContentResource`** (it drags `Compiler.*`) and whether minidregg's pinned toolchain builds outside its snapshot script.
- **Scale.** I have no measurement of cell counts, tariff or latency above a room template. Lane 02 argues that a `KirObject` is a view over per-source claims rather than a stored record. My per-object cell with per-source evidence containers is compatible with that view: each container is one source's contribution. I did not reconcile the two in detail.
- **EKOS's compared attributes** for the slice fixture (`UNIQUE` vs no `UNIQUE`). I traced the conflict detector by reading only.
