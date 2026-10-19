# L-src

On `ekos/source` cells. The JSON is one `Pred` in the client's spelling (`shell/law.rs`), the same `any` shape as `document_law` (`shell.rs:161-163`): verbs that pass sit in one `memberOf`, and the mutate clause sits under `request/verb == 2`.

Principal lists are placeholders, not real subjects. Replace them before any install.

| placeholder | stands for |
|---|---|
| `91001` | the importer set |
| `91002` | the owner set |

## Verb by verb

| verb | code | verdict |
|---|---|---|
| observe | 1 | allowed. The law does not look at the subject. A grant is still required; this file does not grant one. |
| mutate | 2 | allowed only when `request/subject` is in `[91001]`. No content slot is constrained: a source write may create, edit, link, annotate. |
| delegate | 3 | allowed. Delegation does not bypass the mutate clause; the subject is checked again when the grant is used. |
| installPolicy | 4 | allowed only when `request/subject` is in `[91002]`. |
| revoke | 5 | allowed. The exploration's row does not constrain it. |

Anything else is refused, because no branch of the `any` matches. That includes object verbs the shell templates also leave out: append 7, place 10, reserve 12 (`CredentialAuthorityEntryCodec.lean:82-88`). A source "append" in the document sense is a mutate whose command counts atom-creates, not verb 7.

## What it cannot express

- That the bytes were redacted, or that there is a single raw-content entry. `Pred` reads integer slots (`Pred/Core.lean:307-341`). P9 stays a client obligation.
- That the importer set is the right set of people. `91001` is a name written as an integer.
- installPolicy and revoke are `Verb .program`, not `Verb .object` (`Theory/TypedAuthorization.lean:87-91`). On a content object this clause may never be the one judged. See the memo.
