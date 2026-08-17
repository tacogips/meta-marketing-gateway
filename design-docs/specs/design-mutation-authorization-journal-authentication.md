# Enforced Mutation Authorization and Authenticated Journal Identity

**Issue reference:** `workflow:codex-design-and-implement-review-loop-session-740/findings:SEC-001,SEC-002`  
**Workflow mode:** `issue-resolution`  
**Review mode:** `adversarial`  
**Risk:** `medium`  
**Status:** Accepted for implementation and adversarial review  
**Reviewed:** 2026-08-15  
**Codex agent references:** None supplied

## 1. Purpose and scope

This design closes two mutation-safety gaps without changing unrelated gateway
behavior:

- `SEC-001`: authorization must be derived from an enforced, closed policy over
  the complete mutation intent. Caller-supplied risk, confirmation, and spend
  metadata may not reduce that policy.
- `SEC-002`: the durable journal must cryptographically bind immutable record
  identity, plan digest, retained-chain identity, and the independently stored
  trusted head.

The work is local and fail-closed. It does not authorize live mutation, spend,
activation, publication, deployment, migration without independent evidence,
or network auditing. Dismissed `STATIC-COMMAND_EXEC-008` and
`STATIC-INSECURE_HTTP-001..007` findings remain out of scope.

## 2. Security invariants

1. Standard-risk authorization exists only for a built-in operation whose
   method, normalized path, query fields, body fields, and relevant values are
   all explicitly classified as standard by library policy.
2. An unknown generic write is never standard risk. Unknown, ambiguous, or
   unparseable mutation input is denied unless a closed policy explicitly maps
   it to a conservative non-standard class.
3. Equivalent intent expressed in the path, query, or body receives the same
   minimum risk, confirmation, and spend requirements. In particular, status,
   activation, budget, spend, rule, targeting, and schedule changes cannot be
   hidden in query or body input to obtain standard authorization.
4. The effective authorization is computed by trusted gateway policy from the
   exact request being confirmed and applied. A caller descriptor is a claim,
   not authority. A weaker claim is rejected, and a stronger claim cannot make
   a policy-denied operation eligible.
5. Confirmation and apply re-evaluate policy over the exact canonical request;
   they do not rely solely on the risk serialized in a plan or descriptor.
6. Every durable journal event authenticates the journal schema, physical
   namespace, complete logical key, bound plan digest, and chain predecessor.
7. Every trusted head authenticates the same record identity plus the retained
   chain boundary and final event. Moving or rebinding a valid chain to another
   key, namespace, plan digest, filename, or trusted head fails closed.
8. Legacy journal material is never upgraded automatically. It remains
   unusable unless an explicit administrative migration can establish its
   identity from independently protected evidence.

## 3. SEC-001: enforced mutation policy

### 3.1 Policy input and normalization

The policy engine receives one canonical mutation-policy input containing:

- HTTP method and normalized relative Graph path;
- the canonical, duplicate-free query field tree;
- the canonical body field tree and declared media type;
- operation identity and any built-in typed-operation policy; and
- request-derived spend facts, including whether a field can affect spend and
  the requested liability when it can be computed safely.

Query and body classifiers share the same field/value rules. Nested object and
list paths are evaluated recursively, using normalized field names while
preserving typed scalar values. Ambiguous encodings, duplicate keys, excessive
nesting, unsupported body formats, and values that cannot be safely interpreted
are rejected before a plan can be confirmed.

### 3.2 Closed classification rules

Built-in typed operations define an allowlist of accepted method/path shapes,
fields, value constraints, and their minimum authorization. Standard risk is an
explicit allowlist result, never a default.

The generic policy remains conservative:

| Mutation characteristic | Minimum result |
|---|---|
| `GET` or immutable-denied access, ownership, billing, funding, credential, token, audience-membership, or upload operation | denied |
| `DELETE`, delete/archive semantics, or irreversible detachment | destructive risk and destructive confirmation |
| activation/serving status, budget/spend, automated rule, targeting, bid, or schedule semantics in path, query, or body | at least high-impact; spend-affecting confirmation when spend or serving can change |
| unknown generic write or an otherwise unclassified field/value | high-impact only when the generic policy can safely bound it; otherwise denied |
| built-in operation containing only explicitly standard-safe fields and values | standard |

Semantic values are classified as well as field names. For example, a generic
`status=ACTIVE` in query and `{"status":"ACTIVE"}` in a body have the same
minimum result. Aliases supported by an operation must map to the same canonical
field before classification. A newly introduced alias is unknown until policy
is updated and therefore cannot inherit standard authorization.

### 3.3 Authorization lattice and caller metadata

The enforced result contains risk, confirmation class, spend effect, liability
requirement, and denial reasons. Its ordering is monotonic:

`standard < highImpact < destructive < denied`

Confirmation strength is likewise monotonic from standard through high-risk,
destructive, and spend-affecting requirements. `mayAffectSpend=true` and any
policy-derived liability requirement cannot be changed to weaker values.

At each boundary the gateway:

1. computes the enforced result from canonical request bytes;
2. rejects a caller descriptor whose method, path, or operation identity does
   not match the enforced operation;
3. rejects caller risk, confirmation, spend-effect, or liability metadata that
   is weaker than the enforced result;
4. uses the enforced result for plan contents, acknowledgements, spend checks,
   journal binding, and transport eligibility; and
5. permits stronger caller restrictions only as additional restrictions, never
   as a way to override a denial.

Plan, confirm, and apply recompute or verify the same policy-result digest.
Apply classifies the exact query/body bytes supplied for transport and requires
them to match both the request digest and policy-result digest in the confirmed
plan. Any mismatch occurs before credential resolution, journal transition, or
transport.

### 3.4 Confirmation and spend behavior

High-impact and destructive operations require their corresponding exact-plan
acknowledgements. Spend-affecting operations also require spend-affecting
confirmation and the existing provider-verified asset/spend checks. The v1
ceiling remains USD 0, so a policy classification cannot make live or positive-
liability spend eligible.

## 4. SEC-002: authenticated journal identity

### 4.1 Versioned record identity

New journal namespaces, entries, events, and trusted heads use one explicit new
schema version. The canonical record identity contains, with domain separation:

- journal schema version;
- physical journal namespace from the protected namespace marker;
- every `MutationJournalKey` field: namespace, principal, target, operation ID,
  and idempotency key;
- the full bound plan digest; and
- the canonical record filename derived from the complete key.

The record identity digest is recomputed from decoded data and the actual file
location. Stored identity digests are comparisons, not trusted inputs. The key
namespace must equal the physical namespace, the filename must equal the name
derived from the key, and the plan digest must be a complete valid digest.

### 4.2 Event and retained-chain authentication

Each event hash is domain-separated and covers the record identity digest,
event sequence, state, receipt digest, previous hash, and schema version. The
first retained event additionally must agree with the entry's retained-chain
boundary: `firstRetainedSequence` and `previousRetainedHash`.

The entry envelope binds its schema, record identity, first retained sequence,
previous retained hash, and events. Validation occurs before every read,
prepare, transition, reconciliation, compaction, rotation, or administrative
repair. State-transition rules are checked only after authenticity succeeds.

Compaction remains terminal-only. It may discard predecessor event bodies, but
it preserves the terminal event, its sequence, and its authenticated predecessor
hash. The resulting envelope and trusted head bind the new retained boundary.
Compaction cannot change the key, namespace, plan digest, terminal state,
receipt, final sequence, or final event hash.

### 4.3 Trusted-head binding

The independently protected trusted head covers:

- trusted-head schema version and journal namespace;
- canonical record filename and record identity digest;
- first retained sequence and previous retained hash;
- final event sequence and final event hash.

Head lookup remains derived from the canonical record filename. A missing head,
unknown schema, malformed digest, record/head identity mismatch, stale head, or
retained-boundary mismatch is a policy denial. Recovery after a record/head
replacement interruption remains an administrative operation requiring exact
independently verified expected-head evidence; ordinary apply cannot repair or
replace a head.

### 4.4 Legacy compatibility and migration

Legacy entries and heads lack authenticated immutable identity and therefore
cannot establish authenticity. Opening a legacy namespace or encountering a
legacy record/head during any operation fails before state is returned or
changed. Decoding a missing schema as the current schema is forbidden.

There is no automatic or in-place migration. A future administrative migration
may copy only terminal records into a newly created namespace when separately
protected evidence establishes the complete old key, plan digest, terminal
state, receipt, and trusted-head expectation. The migration writes a new-schema
record and head, validates them through the normal reader, and retires the old
namespace. If any evidence is missing or mismatched, migration fails without
making the legacy record operational. Nonterminal or uncertain legacy records
require manual reconciliation and never become retryable by migration.

Namespace rotation validates every source record and trusted head under the new
schema before creating the replacement. Old plans remain bound to the retired
namespace and cannot be replayed in the replacement.

## 5. Validation and adversarial coverage

Tests must demonstrate:

- status, activation, and budget/spend semantics in path, query, body, nested
  body, and supported aliases produce equivalent conservative authorization;
- standard-risk caller metadata, weaker confirmation, false spend-effect, or
  understated liability is rejected when enforced policy is stronger;
- confirmation/apply fail when request fields or the policy-result binding are
  changed after planning, before credentials, journal state, or transport;
- tampering with the plan digest, any key field, namespace marker, record name,
  record identity digest, schema, retained sequence/hash, event data, or any
  trusted-head-bound value fails closed;
- compacted terminal records retain authenticated identity and receipt, while
  tampered compacted boundaries fail;
- legacy or missing-schema entries/heads are rejected, automatic migration is
  absent, and migration without complete independent evidence fails closed;
- namespace rotation preserves old-namespace retirement and rejects rebinding.

Required verification after implementation:

```text
swift test --filter GraphSecurityTests.testWriterTreatsBodyStatusAndBudgetAsHighImpact
swift test --filter GraphSecurityTests.testTrustedHeadRejectsDigestTampering
swift test --filter GraphSecurityTests
swift test
gitleaks detect --source . --no-git --redact --report-format json --report-path /tmp/meta-marketing-gateway-gitleaks.json
riela workflow run codex-source-security-check-loop --variables '{"workflowInput":{"targetPath":".","maxFindings":50,"runNetworkAudits":"false"}}' --output jsonl --verbose --no-auto-improve
```

The final source-security run must report no verified high or medium findings.
Network audits remain disabled.

## 6. Rollout constraints and residual risk

- Schema enforcement ships atomically with writers of the new record/head
  format; mixed-schema read/write operation is not supported.
- Existing legacy journals are quarantined by default. Operators need explicit
  administrative guidance before any evidence-backed migration is introduced.
- No live Meta mutation, spend, publish, deploy, staging, commit, or push is
  part of verification.
- Kinko credentials remain restricted to explicit allowlists and are not needed
  for offline policy, journal, or test verification.
- Generated `.build` content and unrelated untracked worktree content must not
  be modified.
- Same-privilege host/process compromise and failure to protect the trusted-head
  store independently remain residual risks. Runtime host isolation, custom
  embedding behavior, provider contracts, and dependency/network advisories are
  outside this design's verification boundary.

## 7. CLI and reference behavior

No Codex-agent reference input was supplied for this issue, and the findings do
not introduce Cursor-specific behavior. CLI adapters may display sanitized
policy-denial or journal-authentication failures, but all classification,
authorization, and authenticity decisions remain in core policy/journal
modules. No adapter may reinterpret a denial or weaken a confirmation gate.
