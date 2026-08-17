# SEC-001 and SEC-002 Security Remediation Implementation Plan

**Status:** Active; TASK-001 through TASK-004 remediated; TASK-005 source-security exit gate pending (session 743 active at harness recon; no terminal decision)  
**Workflow mode:** `issue-resolution`  
**Issue reference:** `workflow:codex-design-and-implement-review-loop-session-740/findings:SEC-001,SEC-002`  
**Accepted design:** `design-docs/specs/design-mutation-authorization-journal-authentication.md`  
**Design review:** Step 3 accepted via `comm-002502`; no revision requested  
**Codex-agent references:** None supplied  
**Created:** 2026-08-15

## 1. Outcome and boundaries

Resolve only the two verified medium findings:

- `SEC-001`: derive mutation authorization from a closed policy over the exact
  method, normalized path, duplicate-free query, body, typed operation, spend
  effect, and liability; never trust caller metadata to reduce authorization.
- `SEC-002`: version and authenticate the journal namespace, complete key,
  plan digest, canonical record filename, retained-chain identity, events, and
  trusted head; reject legacy or mismatched material before use.

The accepted design is authoritative. Dismissed scanner items
`STATIC-COMMAND_EXEC-008` and `STATIC-INSECURE_HTTP-001..007` are not work
items. Do not modify generated `.build` content or unrelated untracked files.
Do not perform a live Meta mutation, spend, publish, deploy, network audit,
stage, commit, or push. Credentials remain Kinko-only with explicit allowlists;
offline verification must not resolve credentials.

## 2. Deliverables and traceability

| Finding / design invariant | Deliverable | Owning tasks |
|---|---|---|
| `SEC-001`: complete-intent classification | Canonical policy input/result with closed field/value rules and conservative denial | `TASK-001` |
| `SEC-001`: caller metadata is not authority | Plan/confirm/apply derive and bind effective risk, confirmation, spend effect, and liability | `TASK-002` |
| `SEC-001`: equivalent path/query/body effects | Adversarial parity, downgrade, and pre-side-effect tests | `TASK-001`, `TASK-002` |
| `SEC-002`: immutable record identity | Versioned namespace marker, entry, event, and trusted-head identities | `TASK-003` |
| `SEC-002`: retained chain and trusted head | Context-aware validation across all journal operations, compaction, rotation, and recovery | `TASK-003`, `TASK-004` |
| `SEC-002`: legacy fail-closed behavior | Missing/old/unknown schema rejection and no automatic migration | `TASK-004` |
| Exit gate | Focused/full tests, secret scan, then source-security workflow with zero verified high/medium findings | `TASK-005` |

Primary files:

- `Sources/MetaMarketingGatewayCore/MutationPlan.swift`
- `Sources/MetaMarketingGatewayCore/MutationSafety.swift`
- `Sources/MetaMarketingGatewayCore/GraphRequest.swift`
- `Sources/MetaMarketingGatewayCore/URLSessionGraphTransport.swift`
- `Sources/MetaMarketingGatewayCore/GatewayCLI.swift`
- `Tests/MetaMarketingGatewayCoreTests/GraphSecurityTests.swift`
- `README.md`
- `SECURITY.md`

Corresponding existing CLI tests under `Tests/MetaMarketingGatewayCoreTests/`
may be changed only to verify body-media-type parsing and to pass the same
canonical request through the core enforcement boundary.

If responsibility-sized policy or journal helpers are extracted, keep them
inside `Sources/MetaMarketingGatewayCore/` and record the new path in this
plan's progress log before editing it. Do not add an adapter-side policy.

## 3. Task breakdown

### TASK-001: Build the closed mutation policy model

**Depends on:** Accepted Step 3 design.  
**Parallelizable:** No; it writes `MutationSafety.swift`, which is also required
by `SEC-002`.  
**Write scope:** `MutationSafety.swift`, `GraphRequest.swift`, the
`RequestSource` model in `GatewayCLI.swift`, policy-focused tests in
`GraphSecurityTests.swift`, corresponding CLI tests, or a recorded
responsibility-sized core helper.

**Work:**

- Define a canonical policy input for method, normalized relative path,
  duplicate-free query fields, bounded JSON body fields/values, declared media
  type, operation identity, and request-derived spend/liability facts.
- Add a closed body-media-type representation to `GraphRequest`. Require a
  supported declared media type whenever a body is present, require no body
  media type when the body is absent, and reject arbitrary, conflicting, or
  unsupported values before planning. Extend the CLI `RequestSource` schema to
  carry that declaration; it must not infer a permissive type from body bytes.
- Use the same recursive field/value classifier for query and body. Normalize
  supported aliases before classification and cap size/depth/work. Reject
  duplicate keys, ambiguous/unparseable encodings, unsupported body formats,
  and unknown aliases before plan creation.
- Define an enforced result containing risk, confirmation class,
  `mayAffectSpend`, liability requirement, denial reasons, and a canonical
  digest. Encode the monotonic lattices `standard < highImpact < destructive <
  denied` and standard/high-risk/destructive/spend-affecting confirmation.
- Make standard risk available only to built-in typed operations whose
  method/path/fields/values are explicitly allowlisted. Generic unknown writes
  are high-impact only when safely bounded; otherwise deny. Keep immutable
  access, ownership, billing, funding, credential/token, audience-membership,
  and upload categories denied. Classify deletes as destructive.
- Treat activation/serving status, budget/spend, automated rules, targeting,
  bids, and schedules consistently wherever expressed. Spend or serving
  changes require high-impact plus spend-affecting confirmation and derived
  liability handling.
- Add table-driven policy tests for safe typed input, denied categories,
  unknown fields, aliases, duplicate query/body keys, nested/list bodies,
  depth/size limits, and equivalent path/query/body intent.

**Deliverables:** Closed policy API; deterministic policy-result digest;
table-driven normalization/classification tests.

**Completion criteria:**

- [x] Only the `meta.ad-account.rename` typed allowlist can obtain standard
      risk; generic or unknown operation identities cannot obtain it by default.
- [x] `GraphSecurityTests.testMutationPolicyCoversClosedPathQueryAndBodyMatrix`
      directly asserts risk, confirmation, spend effect, liability, and denial
      behavior for path/query/body status aliases, nested activation, list
      budgets, targeting, bids, schedules, deletes, depth, and size bounds.
- [x] Invalid, ambiguous, duplicate, unsupported, or over-budget input fails
      before plan creation, credentials, journal access, or transport.
- [x] Missing, conflicting, or unsupported body media types fail before policy
      classification, while a body-free request cannot smuggle a media type.
- [x] Policy decisions are produced by core code and cannot be supplied by a
      CLI adapter or mutation caller.

### TASK-002: Bind enforced authorization through plan, confirm, and apply

**Depends on:** `TASK-001`.  
**Parallelizable:** No; it shares `MutationSafety.swift` and
`GraphSecurityTests.swift` with later journal work.  
**Write scope:** `MutationPlan.swift`, `GraphRequest.swift`,
`URLSessionGraphTransport.swift`, the descriptor/authorization portion of
`MutationSafety.swift`, `GatewayCLI.swift`, and focused core/CLI/transport
tests.

**Work:**

- Bump the mutation-plan schema and bind the enforced policy-result digest,
  declared body media type, effective confirmation, spend effect, and liability
  requirement into canonical plan bytes. Reject old or missing plan schemas;
  do not silently reinterpret schema-v1 risk.
- At planning, evaluate the exact canonical method/path/query/body and typed
  operation policy. Treat `MutationDescriptor` risk, confirmation,
  `mayAffectSpend`, and requested liability as caller claims. Reject a claim
  that is weaker or inconsistent; allow stronger restrictions only as an
  additional clamp, never to override denial.
- Change the core confirmation boundary so it re-evaluates the exact request,
  including its declared media type, verifies the request and policy-result
  digests, and requires the effective acknowledgement class. Preserve a
  compatibility overload only if it cannot confirm without the same exact
  canonical request evidence.
- At apply, reclassify the exact query/body bytes before journal preparation,
  credential resolution, provider verification, state transition, or
  transport. Require method/path/operation/request/policy bindings to match the
  confirmed plan and enforced descriptor result.
- At the transport boundary, derive `Content-Type` exclusively from the closed,
  policy-authorized media type carried by the validated `GraphRequest`. Emit
  that exact value with the classified body bytes; emit no body content type
  when there is no body. Do not expose an arbitrary header or content-type
  override through the request, writer, CLI, or transport APIs.
- Feed only enforced `mayAffectSpend` and liability values into `SpendSafety`.
  A descriptor cannot suppress a spend check or substitute a lower liability.
- Update the CLI call site to pass the already-loaded request into core
  confirmation, including its declared media type. The CLI may render a
  sanitized denial but must not classify, infer, or weaken it.
- Instrument fakes to prove downgrade and post-plan tamper failures make zero
  credential, journal-transition, and transport calls.
- Add a recording `URLProtocol` transport contract test proving the authorized
  media type is the exact wire `Content-Type`, an absent body sends neither body
  nor content type, and media-type tampering is rejected before transport.

**Deliverables:** Versioned policy-bound mutation plan; exact-request confirm,
apply, and wire-media-type enforcement; minimal CLI call-site adaptation;
downgrade and transport-contract regressions.

**Completion criteria:**

- [x] `GraphSecurityTests.testWriterTreatsBodyStatusAndBudgetAsHighImpact`
      passes and covers both body and query expression.
- [x] `GraphSecurityTests.testWriterRejectsEachWeakerCallerAuthorizationClaimBeforeSideEffects`
      independently rejects weaker risk, confirmation, spend effect, and
      liability claims before credential resolution, journal creation, or transport.
- [x] `GraphSecurityTests.testWriterRejectsPostPlanBodyQueryAndMediaTamperingBeforeSideEffects`
      proves query/body/media changes fail before credential resolution,
      durable-journal creation/transition, or transport action.
- [x] Operation identity is schema-v5 request-, policy-, and plan-bound, and a
      post-plan identity substitution fails before credentials, journal, or transport.
- [x] `GraphSecurityTests.testWriterTransportUsesPolicyAuthorizedContentType`
      proves an absent body emits neither body nor `Content-Type`; post-plan
      removal or alteration of body media type fails before side effects.
- [x] `GraphSecurityTests.testWriterTransportUsesPolicyAuthorizedContentType`
      proves the classified media type equals the wire `Content-Type`, no
      arbitrary header override exists, and tampering makes zero transport
      calls.
- [x] Apply authorization is derived from enforced policy, not descriptor-risk
      equality.
- [x] `GraphSecurityTests.testWriterPlansConfirmsAndAppliesDestructiveSpendAffectingDelete`
      proves a destructive, spend-affecting DELETE satisfies the destructive
      acknowledgement requirement through plan, confirm, and apply.

### TASK-003: Introduce authenticated journal schema and record identity

**Depends on:** `TASK-002`; serialize because both findings change shared
security models and tests.  
**Parallelizable:** No.  
**Write scope:** durable-journal portion of `MutationSafety.swift` and focused
journal tests in `GraphSecurityTests.swift`.

**Work:**

- Define one explicit new schema version for namespace markers, journal
  entries, events, and trusted heads. Missing, legacy, and unknown versions are
  never decoded as current.
- Build a domain-separated canonical record identity from schema, physical
  namespace marker, every `MutationJournalKey` field, full validated plan
  digest, and canonical filename derived from the complete key. Recompute the
  identity from decoded material and actual file location; stored digests are
  comparison values only.
- Bind schema and record-identity digest into every event hash. Bind entry
  schema/identity and `firstRetainedSequence`/`previousRetainedHash` into the
  envelope validation contract.
- Expand the trusted head to authenticate its schema, journal namespace,
  canonical record filename, record-identity digest, retained boundary, final
  sequence, and final event hash. Continue deriving head lookup from the
  canonical record filename.
- Centralize a context-aware record loader/validator used before state-machine
  checks. It must verify marker schema/namespace, expected key, actual filename,
  full digest format, identity digest, retained boundary, event chain, and
  configured trusted head in that order.
- Ensure new record creation writes an entry/head pair with identical identity
  inputs and retains existing secure-file, owner-only, no-follow, locking,
  atomic-replacement, and fsync behavior.

**Deliverables:** Versioned authenticated namespace/entry/event/head schema;
central validation boundary; creation and reload tests.

**Completion criteria:**

- [x] `GraphSecurityTests.testTrustedHeadRejectsDigestTampering` passes.
- [x] Changes to plan digest, any key field, namespace, filename, identity
      digest, schema, event, or trusted-head identity fail closed; length-prefixed
      key material prevents delimiter rebinding.
- [x] No untrusted stored digest or record name chooses validation context.
- [x] Existing secure storage and rollback protections remain intact.

### TASK-004: Enforce identity across lifecycle, compaction, rotation, and legacy data

**Depends on:** `TASK-003`.  
**Parallelizable:** No; all paths write the same actor and regression suite.  
**Write scope:** `MutationSafety.swift` and journal lifecycle tests in
`GraphSecurityTests.swift`.

**Work:**

- Route `prepare`, `state`, `receiptStatus`, `transition`, `reconcile`,
  `compact`, namespace rotation, and administrative trusted-head repair through
  the context-aware authenticity validator before returning or changing state.
- During compaction, retain the terminal event and authenticate the new
  `firstRetainedSequence`/`previousRetainedHash` boundary in both entry and
  head. Prohibit changes to identity, key, plan digest, terminal state,
  receipt, final sequence, or final hash.
- During rotation, authenticate every source entry/head and require terminal
  state before creating the replacement namespace. Do not copy/rebind old
  records; retire the old namespace so old plans and keys remain unusable.
- Expand administrative recovery evidence to bind the expected record
  identity and retained boundary as well as the final sequence/hash. Ordinary
  apply remains unable to repair, create, or replace a trusted head.
- Add synthetic legacy fixtures for missing/old marker, entry, event, and head
  schemas. Prove opening or operating on them fails closed. Do not add
  automatic/in-place migration. Prove incomplete or mismatched evidence cannot
  make a legacy record operational.
- Add compacted-boundary tampering, identity rebinding, head swapping, stale or
  missing head, rotation, repair, and crash-checkpoint regressions.

**Deliverables:** Authenticated lifecycle operations; safe compaction and
rotation; legacy quarantine behavior; expanded adversarial suite.

**Completion criteria:**

- [x] `GraphSecurityTests.testTrustedHeadRejectsIndependentFieldTamperingAcrossOperations`
      independently rejects all trusted-head-bound fields on read, transition,
      compaction, rotation, and administrative repair paths, with an
      unmodified stale-anchor repair control.
- [x] Valid compacted terminal records preserve state and receipt; tampered
      compacted boundaries are rejected.
- [x] Legacy/missing-schema data never becomes current automatically, and
      incomplete migration/recovery evidence cannot enable it.
- [x] Rotation authenticates all source records and cannot replay an old plan
      or rebind an old record into the replacement namespace.
- [x] `GraphSecurityTests.testDurableJournalRejectsPostOpenNamespaceMarkerTamperingAcrossOperations`
      proves an already-open journal re-reads and rejects a tampered marker
      before every lifecycle, rotation, and administrative-repair operation.

### TASK-005: Document, integrate, verify, and close both findings

**Depends on:** `TASK-001` through `TASK-004`.  
**Parallelizable:** No; this is the serialized exit gate.  
**Write scope:** `README.md`, `SECURITY.md`, tests, and this plan's
progress/checklist. Source changes are allowed solely for defects exposed by
verification and must be logged.

**Work:**

- Update `README.md` and `SECURITY.md` with the enforced complete-intent policy,
  declared body-media-type requirement, schema rollout, default legacy-journal
  quarantine, absence of automatic/in-place migration, independently protected
  trusted-head store requirement, administrative recovery boundary, and
  sanitized policy/journal-denial behavior. Do not publish a recovery command
  that makes ordinary apply capable of repair.
- Run the repository-mandated `mise run check` gate first; it must pass its
  `format-check`, deterministic `test`, and `build` dependencies. Retain
  standalone `swift build` as explicit product typecheck/build evidence, then
  run the focused named regressions, complete `GraphSecurityTests` suite, and
  full Swift suite. Fix failures without relaxing the accepted invariants.
- Run the local gitleaks command and inspect its report. Network dependency
  audits remain disabled.
- Rerun `codex-source-security-check-loop` with target `.`, maximum 50 findings,
  and network audits set to string `"false"`.
- If the source-security workflow reports any verified high or medium finding,
  keep this plan active, append the finding and evidence to the progress log,
  and return to the owning task. Do not mark completion on test success alone.
- Confirm `git status --short` shows no modification to `.build` or unrelated
  user content and no stage/commit/push occurred.

**Deliverables:** Operator/security documentation; build/typecheck and test
evidence; gitleaks report outside the repository; source-security review
decision; completed progress log.

**Completion criteria:**

- [ ] Every required verification command passes.
- [ ] `mise run check` passes, including its format-check, deterministic test,
      and build dependencies, with the result recorded in the progress log.
- [ ] `README.md` and `SECURITY.md` accurately document policy/media-type
      enforcement, atomic schema rollout, legacy quarantine, trusted-head
      protection/recovery boundaries, and sanitized denials.
- [ ] The rerun reports no verified high or medium source-security finding.
- [ ] `SEC-001` and `SEC-002` are explicitly closed with test evidence.
- [ ] No unrelated dirty-worktree content or generated `.build` file changed.
- [ ] No live mutation, credential resolution, spend, publish, deploy, stage,
      commit, push, or network audit occurred.

## 4. Dependencies and sequencing

```text
Accepted design / Step 3 comm-002502
  -> TASK-001 closed policy model
  -> TASK-002 plan-confirm-apply enforcement (closes SEC-001 behavior)
  -> TASK-003 authenticated journal schema and identity
  -> TASK-004 lifecycle/legacy/compaction/rotation coverage (closes SEC-002 behavior)
  -> TASK-005 full verification and source-security rerun
```

There are no safe parallel implementation tasks in the current layout:
`TASK-001` through `TASK-004` overlap in
`Sources/MetaMarketingGatewayCore/MutationSafety.swift` and
`Tests/MetaMarketingGatewayCoreTests/GraphSecurityTests.swift`; `TASK-005`
depends on all of them. Read-only research does not count as an implementation
task and does not change this decision.

## 5. Verification commands

Run in this order from the repository root and record pass/fail output in the
progress log:

```text
mise run check
swift build
swift test --filter GraphSecurityTests.testWriterTreatsBodyStatusAndBudgetAsHighImpact
swift test --filter GraphSecurityTests.testWriterTransportUsesPolicyAuthorizedContentType
swift test --filter GraphSecurityTests.testTrustedHeadRejectsDigestTampering
swift test --filter GraphSecurityTests
swift test
rg -n -e "media type" -e "legacy" -e "trusted head" -e "automatic migration" -e "policy denial" README.md SECURITY.md
gitleaks detect --source . --no-git --redact --report-format json --report-path /tmp/meta-marketing-gateway-gitleaks.json
riela workflow run codex-source-security-check-loop --variables '{"workflowInput":{"targetPath":".","maxFindings":50,"runNetworkAudits":"false"}}' --output jsonl --verbose --no-auto-improve
git status --short
```

Also retain explicit zero-call assertions for credential resolvers, journal
state transitions, and transports on all policy/tamper denials.

## 6. Overall completion criteria

- [ ] All `TASK-001` through `TASK-005` task criteria are checked with dated
      command evidence.
- [ ] Status, budget, and equivalent body/query/path mutations cannot receive
      standard-risk authorization.
- [ ] Authorization and spend gates derive from enforced policy; weaker caller
      metadata is rejected.
- [ ] The transport emits only the policy-authorized body media type as the
      exact wire `Content-Type`; callers cannot supply or override headers.
- [ ] Journal schema and hashes authenticate namespace, complete key, full plan
      digest, canonical filename, retained boundary, events, and trusted head.
- [ ] Legacy, compaction, recovery, and rotation behavior is explicitly tested
      and fail-closed wherever authenticity cannot be established.
- [ ] `README.md` and `SECURITY.md` document the new policy, body-media-type,
      schema rollout, legacy quarantine, and trusted-head operator boundaries.
- [ ] `mise run check`, standalone `swift build`, focused/full Swift tests, and
      documentation checks pass; gitleaks reports no secret finding, and the
      security rerun leaves no high/medium finding.
- [ ] Repository constraints and dirty-worktree preservation are satisfied.

## 7. Progress-log expectations

For every implementation session, append a dated entry containing:

- task ID and finding (`SEC-001` or `SEC-002`);
- exact files changed and security invariant implemented;
- verification commands with pass/fail result and test count when available;
- the `mise run check` result and explicit status of its `format-check`, `test`,
  and `build` dependencies;
- observed failures or source-security findings and the owning follow-up task;
- confirmation that no live/network mutation, credential use, spend,
  `.build` edit, stage, commit, push, publish, or deploy occurred; and
- remaining unchecked completion criteria.

Do not check a task merely because code was written. Check it only after its
criteria and regressions pass. Record any intentional design divergence before
implementation and send it back through design review; none is currently
accepted.

## 8. Progress log

- 2026-08-15: Created this active plan from the accepted Step 3 design and
  `comm-002502`. Mapped both verified medium findings to serialized tasks,
  explicit deliverables, adversarial regressions, and the required security
  exit gate. No implementation code, test, build, network request, credential
  access, `.build` edit, stage, commit, push, publish, or deploy occurred.
- 2026-08-15: Revised the plan after self-review `comm-002504`. Assigned the
  accepted declared-media-type behavior to `GraphRequest.swift`, CLI
  `RequestSource`, plan/confirm/apply bindings, and core/CLI tests; corrected
  equivalent-intent ownership to `TASK-001` and `TASK-002`; added explicit
  `README.md`/`SECURITY.md` operator documentation and `swift build` verification.
  No implementation code, build, test, network request, credential access,
  `.build` edit, stage, commit, push, publish, or deploy occurred.
- 2026-08-15: Began TASK-001/TASK-002 without checking completion criteria.
  Added core-only, exact-request closed policy classification in
  MutationSafety.swift; generic writes are never standard, GET and immutable
  categories are denied, and delete/status/budget semantics from normalized
  path, query, or bounded JSON body produce conservative results. Mutation-plan
  schema v2 now binds the policy digest, effective confirmation, and spend
  flag; confirmation and apply reclassify the supplied exact request before the
  journal or transport boundary. GatewayCLI.swift now passes its loaded request
  to core confirmation. Added
  GraphSecurityTests.testWriterTreatsBodyStatusAndBudgetAsHighImpact and
  updated existing writer tests to confirm exact request evidence. Verified
  swift test --filter GraphSecurityTests.testWriterTreatsBodyStatusAndBudgetAsHighImpact
  and swift test --filter GraphSecurityTests (51 tests). TASK-001 through
  TASK-005 remain unchecked: declared media-type enforcement, typed-operation
  allowlists, duplicate-field canonicalization, authenticated journal schema,
  documentation, and exit-gate scans remain pending. No credential resolution,
  live/network mutation, spend, .build edit, stage, commit, push, publish, or
  deploy occurred.
- 2026-08-15: Revised the plan after self-review `comm-002506`. Added
  `URLSessionGraphTransport.swift` to `TASK-002`, required the closed
  policy-authorized media type to become the exact wire `Content-Type` without
  a caller-controlled header path, and added a named recording-transport
  regression and verification command. No implementation code, build, test,
  network request, credential access, `.build` edit, stage, commit, push,
  publish, or deploy occurred.
- 2026-08-15: Revised the plan after independent plan review `comm-002509`.
  Added repository-mandated `mise run check` as the first ordered verification
  gate, required its format-check/test/build results in completion and progress
  evidence, and retained standalone build, focused security regressions,
  documentation verification, gitleaks, and the source-security rerun. No
  implementation code, build, test, network request, credential access,
  `.build` edit, stage, commit, push, publish, or deploy occurred.

- 2026-08-15: Implementation in progress for `SEC-001`/`SEC-002`. Updated
  `GraphRequest.swift`, `MutationPlan.swift`, `MutationSafety.swift`,
  `GatewayCLI.swift`, and `URLSessionGraphTransport.swift` so JSON mutation
  bodies require a declared policy-approved media type; plan/confirm/apply bind
  it with the exact request and policy result; duplicate JSON fields fail
  closed; status/serving changes require spend-affecting confirmation; and
  weaker descriptor liability metadata is rejected. Versioned journal
  namespace/entry/event/trusted-head records now bind complete key, plan
  digest, filename, retained boundary, and final event, rejecting legacy or
  mismatched material. Added media-type and trusted-head digest-tampering
  regressions plus updated policy-equivalent writer fixtures. Focused
  `GraphSecurityTests` passed (53 tests); `swift build` and `mise run check`
  passed (the formatter emitted existing-style warnings but returned success).
  This entry records partial implementation only; TASK-001 through TASK-005
  remain unchecked until every listed criterion has dated evidence.
  No live mutation, credential resolution, network audit, spend, `.build`
  edit, stage, commit, push, publish, or deploy occurred.
- 2026-08-15: Continued TASK-001/TASK-002 remediation. Core policy rejects
  duplicate mutation query keys and duplicate JSON object fields before
  classification, requires declared JSON media type, treats serving/status as
  spend-affecting, and derives integer liability from duplicate-free
  budget/spend inputs. Apply rejects a mismatched authorization liability
  before journal, credentials, or transport; regression coverage includes
  missing media, duplicate query/JSON fields, status/budget parity, and
  zero-side-effect understated-liability denial. Repaired the in-progress
  versioned journal implementation so marker, entry, event, retained boundary,
  and trusted-head records bind schema, namespace, canonical filename, and
  record identity before transitions. `swift test` (57 tests), focused policy/
  writer regressions, and `mise run check` pass; gitleaks reports no leaks.
  Source-security rerun session `codex-source-security-check-loop-session-741`
  remains in harness reconnaissance and is not exit-gate evidence yet.
  No credential resolution, live request, mutation, spend, stage, commit,
  push, publish, or deploy occurred.

- 2026-08-15: TASK-005 verification: `swift build`, `mise run check`, focused
  writer/media-type and trusted-head digest tests, `GraphSecurityTests` (55),
  and full `swift test` (57) passed; documentation terminology check passed;
  `gitleaks detect --source . --no-git --redact --report-format json
  --report-path /tmp/meta-marketing-gateway-gitleaks.json` found no leaks.
  Source-security session
  `codex-source-security-check-loop-session-741` was started with network
  audits disabled after the documented `--verbose` option proved unsupported
  by this local Riela CLI. It remains in harness reconnaissance, with only the
  previously-dismissed documentation command example and generated `.build`
  plist DTD heuristics pending triage; no generated file was edited. TASK-005
  and overall completion remain unchecked until that session reaches its final
  review decision. No live mutation, credential resolution, spend, network
  audit, `.build` edit, stage, commit, push, publish, or deploy occurred.

- 2026-08-15: Continued TASK-002 without checking completion criteria. Bumped
  `MutationPlan` to schema v4 and bound policy-derived
  `requestedLiabilityCents` into canonical plan bytes, plan confirmation, and
  apply validation. `SpendSafety` now consumes exact-request policy liability
  and spend effect rather than authorization metadata; authorization remains a
  matching descriptor claim only. Existing trusted-head recovery evidence and
  legacy marker/record/head regressions bind record identity and retained
  boundary, but the broader production writer, typed-reader, delivery, and
  source-security exit criteria remain incomplete. No credential resolution,
  live request, mutation, spend, stage, commit, push, publish, or deploy
  occurred.

- 2026-08-15: Verified the current partial revision with `swift format lint
  Sources/MetaMarketingGatewayCore/MutationPlan.swift
  Tests/MetaMarketingGatewayCoreTests/GraphSecurityTests.swift`, standalone
  `swift build`, focused liability/tampered-plan tests, `swift test --filter
  GraphSecurityTests` (61 tests), full `swift test` (63 tests), `mise run
  check`, and gitleaks (no leaks). Repository-wide `mise run check` still
  reports pre-existing formatter warnings in `MutationSafety.swift` and
  `GatewayCLI.swift`; no changed-file formatting warning remains. TASK-001
  through TASK-005 remain unchecked because their complete criteria, including
  genuine production composition and the final source-security workflow
  decision, have not been satisfied.

- 2026-08-15: Addressed self-review findings `SELF-REVIEW-001` and
  `SELF-REVIEW-002` for `SEC-002`. Administrative trusted-head repair now
  validates trusted-head schema, namespace, canonical filename, record
  identity, digest shape, and independently protected expected record identity
  and retained-boundary evidence before replacement. A missing canonical record
  with an existing trusted head now fails closed instead of allowing a new
  entry/head pair. Added regressions for repair identity tampering, key and
  namespace tampering, canonical filename rebinding, retained-boundary
  tampering after compaction, legacy marker/entry/event/head schemas, and the
  absence of automatic migration. Extended coverage to each journal-key field,
  marker namespace, and a legacy schema version. Updated TASK-003/TASK-004
  completion criteria with focused evidence. `swift test --filter
  GraphSecurityTests` passed (62 tests). TASK-005 and overall completion remain unchecked pending
  the full verification rerun and a final source-security decision. No live
  mutation, credential resolution, spend, network audit, `.build` edit, stage,
  commit, push, publish, or deploy occurred.

- 2026-08-15: Reran the local verification after the self-review remediation:
  `mise run check`, standalone `swift build`, each named SEC-001/SEC-002
  regression, `swift test --filter GraphSecurityTests` (62 tests), and
  `swift test` (64 tests) passed. The documentation
  terminology check and gitleaks report (0 findings) also passed. The
  source-security workflow session remains stalled in `step2-harness-recon`
  with no final review decision; its only raw findings remain the documented
  command example and generated `.build` plist DTD heuristics already recorded
  as dismissed review context. TASK-005 and overall completion remain
  unchecked pending that final decision. No `.build` file or unrelated
  top-level content was edited, and no stage, commit, push, live mutation,
  credential resolution, spend, publish, deploy, or network audit occurred.

- 2026-08-15: Reconciled the active-plan header after self-review
  `comm-002502`: TASK-001/TASK-002 remain explicitly partial, TASK-003/TASK-004
  remain checked only because their listed authenticated-schema and lifecycle
  criteria passed, and TASK-005 remains pending the terminal source-security
  decision. Re-ran recursive Swift formatter lint, standalone `swift build`,
  and `swift test --filter GraphSecurityTests` (62 tests); all passed after an
  initial concurrent test-discovery run was repeated in isolation and as the
  full focused suite. No policy or journal invariant was relaxed. No
  credential resolution, live request, mutation, spend, network audit, `.build`
  edit, stage, commit, push, publish, or deploy occurred.

- 2026-08-15: TASK-005 remains incomplete after the required rerun: `mise run
  check` passed its recursive format lint, build, and 64 parallel tests;
  standalone `swift build`; all three named SEC regressions;
  `swift test --filter GraphSecurityTests` (62 tests); and full `swift test`
  (64 tests) passed. The README/SECURITY terminology check and gitleaks report
  (0 leaks) passed. `codex-source-security-check-loop-session-741` is still
  non-terminal in `step2-harness-recon` after 358 seconds of backend silence;
  it retains one documentation-command heuristic and seven generated `.build`
  plist heuristics as open raw findings, so it cannot be treated as a zero
  high/medium exit decision. TASK-005 and overall completion remain unchecked.
  No credential resolution, live request, mutation, spend, network audit,
  `.build` edit, stage, commit, push, publish, or deploy occurred.

- 2026-08-15: Addressed `SELF-REVIEW-003`, `SELF-REVIEW-004`, and
  `SELF-REVIEW-005`. Recovery evidence now binds both the expected replacement
  head and the independently protected prior anchor, so a retained-boundary
  change cannot be repaired over. The journal rejects malformed plan digests,
  noncanonical record filenames, malformed record/head identities, and
  incoherent retained boundaries before use; test fixtures now use complete
  digests. Added focused retained-boundary-repair and malformed-digest
  regressions. Restored the authoritative issue reference and empty Codex-agent
  references in this plan header. `mise run check` passed format lint, build,
  and 66 tests; `swift test --filter GraphSecurityTests` passed (64 tests),
  full `swift test` passed (66 tests), named SEC regressions passed, the
  documentation terminology check passed, and gitleaks found 0 leaks.
  `codex-source-security-check-loop-session-741` remains stalled at
  `step2-harness-recon`, so TASK-005 and overall completion remain unchecked.
  No credential resolution, live request, mutation, spend, network audit,
  `.build` edit, stage, commit, push, publish, or deploy occurred.

- 2026-08-15: Addressed `SELF-REVIEW-006`, `SELF-REVIEW-007`, and
  `SELF-REVIEW-008`. Administrative recovery now accepts an interrupted
  compaction only when the independently protected prior anchor and replacement
  evidence exactly bind the unchanged final sequence/hash and the retained
  boundary has changed; ordinary recovery still requires a sequence advance.
  The identity-mismatch regression now uses a genuinely stale anchor, making
  the identity mismatch decisive, and an interrupted-compaction regression
  proves recovery restores the trusted head. Corrected stale session references
  to `codex-source-security-check-loop-session-741`. `mise run check` passed
  format lint, build, and 67 tests; standalone `swift build`; the named
  SEC-001/SEC-002 regressions; `swift test --filter GraphSecurityTests` (65
  tests); and full `swift test` (67 tests) passed. The documentation
  terminology check and gitleaks (0 leaks) passed. TASK-005 remains pending
  the terminal source-security review.

- 2026-08-15: Addressed `SELF-REVIEW-009` and `SELF-REVIEW-010`. Equal-final
  administrative recovery now requires the retained boundary to advance, so it
  cannot restore discarded predecessor events; the backward-boundary regression
  fails closed. Marked TASK-001 and TASK-002 completion criteria remediated
  using the recorded exact-policy, liability, tamper, media-type, and
  zero-side-effect regressions. `mise run check` passed format lint, build,
  and 68 tests; standalone `swift build`; focused `GraphSecurityTests` (66
  tests); full `swift test` (68 tests); and named SEC regressions passed.
  The documentation terminology check and gitleaks (0 leaks) passed. TASK-005
  remains pending the terminal source-security review.

- 2026-08-15: Addressed `SELF-REVIEW-011`, `SELF-REVIEW-012`, and
  `SELF-REVIEW-013`. `MutationPolicy` now receives a validated operation
  identity, admits standard risk only through the closed
  `meta.ad-account.rename` typed rule, and keeps equivalent generic writes
  high-impact. `MutationPlan` schema v5 binds the operation identity into the
  request, policy, and canonical plan digests; plan, confirmation, and apply
  re-evaluate it before side effects. Added a regression for the typed-safe
  case, generic-equivalent high-impact case, and post-plan identity
  substitution with zero credential, journal, and transport calls. TASK-001
  and TASK-002 completion criteria now record this evidence. `swift format`
  passed on all changed Swift files; the named identity regression, focused
  `GraphSecurityTests` (67 tests), standalone `swift build`, full `swift test`
  (69 tests), documentation terminology check, gitleaks (0 leaks), and `mise
  run check` (format lint, build, 69 tests) passed. TASK-005 remains pending
  the terminal source-security review. No live mutation, credential use outside
  test fakes, spend, network audit, `.build` edit, stage, commit, push,
  publish, or deploy occurred.

- 2026-08-15: Addressed `TEST-INTEGRITY-001` and `TEST-INTEGRITY-002` without
  weakening the full-suite gate. Added a table-driven SEC-001 policy matrix
  that directly asserts risk, confirmation, spend effect, liability, and
  denial behavior across path/query/body, nested/list values, status alias,
  activation, targeting, bid, schedule, delete, depth, and size cases. Added
  body-free wire assertions and post-plan media/query/body tamper coverage;
  all tamper and understated-liability paths now assert zero credential
  resolution, no durable-journal record/transition, and zero transport calls.
  `swift format` passed; the named policy, tamper, and transport regressions,
  focused `GraphSecurityTests` (69 tests), standalone `swift build`, and full
  `swift test` (71 tests), `mise run check` (format lint, build, 71 tests),
  documentation terminology check, and gitleaks (0 findings) passed. TASK-005
  remains pending the terminal source-security review. No live mutation, credential use outside
  test fakes, spend, network audit, `.build` edit, stage, commit, push,
  publish, or deploy occurred.

- 2026-08-15: Addressed `TEST-INTEGRITY-003` and `TEST-INTEGRITY-004` without
  weakening the full-suite gate. Added isolated same-operation apply cases for
  weaker risk, confirmation, spend-effect, and liability claims; each rejects
  before journal creation, credential resolution, or transport. Added
  independent trusted-head mutations for schema, namespace, record name,
  record identity, retained sequence/hash, final sequence, and final hash;
  ordinary read/transition and terminal compaction/rotation fail closed.
  Administrative-repair coverage is corrected in the subsequent
  `SELF-REVIEW-014` entry. `swift format` and the named regressions passed;
  focused `GraphSecurityTests` (71 tests), standalone `swift build`, and full
  `swift test` (73 tests), `mise run check` (format lint, build, 73 tests),
  documentation terminology check, and gitleaks (0 findings) passed. TASK-005
  remains pending the terminal source-security review. No live mutation, credential use
  outside test fakes, spend, network audit, `.build` edit, stage, commit,
  push, publish, or deploy occurred.

- 2026-08-15: Addressed `SELF-REVIEW-014` and `SELF-REVIEW-015`. The
  trusted-head matrix now restores the captured stale anchor before mutating
  exactly one authenticated field, while recovery evidence remains bound to
  the unmodified stale anchor; a separate unmodified stale-anchor control
  successfully repairs the interrupted anchor update. The TASK-004 criterion
  and prior progress evidence now state this decisive coverage. `swift format`,
  the named trusted-head and caller-authorization regressions, focused
  `GraphSecurityTests` (71 tests), standalone `swift build`, full `swift test`
  (73 tests), `mise run check` (format lint, build, 73 tests), documentation
  terminology check, and gitleaks (0 findings) passed. TASK-005 remains
  pending the terminal source-security review. No live mutation, credential use
  outside test fakes, spend, network audit, `.build` edit, stage, commit, push,
  publish, or deploy occurred.

- 2026-08-15: Addressed Step 7 findings in `Sources/MetaMarketingGatewayCore/MutationSafety.swift`
  and `Tests/MetaMarketingGatewayCoreTests/GraphSecurityTests.swift`. Journal
  schema v3 derives filenames and record identities from domain-separated,
  length-prefixed complete-key material, and the delimiter-rebinding regression
  proves distinct complete keys cannot reuse an entry or trusted head. Every
  locked journal operation now re-reads the namespace marker; the marker-tamper
  matrix covers prepare, reads, transition, reconciliation, compaction,
  rotation, and administrative repair. Destructive spend-affecting descriptors
  consistently use destructive confirmation; the DELETE plan-confirm-apply
  regression completes with one credential and transport call. `swift format`,
  three named regressions, focused `GraphSecurityTests` (74 tests), standalone
  `swift build`, full `swift test` (76 tests), and `mise run check` (format
  lint, build, 76 tests) passed. Source-security rerun session
  `codex-source-security-check-loop-session-743` is active at
  `step2-harness-recon` without a terminal decision; TASK-005 and overall exit
  criteria remain unchecked. No live mutation, credential use outside test
  fakes, spend, network audit, `.build` edit, stage, commit, push, publish, or
  deploy occurred.

- 2026-08-15: Retried the required source-security harness reconnaissance
  after validating `codex-source-security-check-loop`; the retry created
  session `codex-source-security-check-loop-session-744` at
  `step2-harness-recon`. Its Codex backend became `stalled-suspect` after more
  than 180 seconds without an output event. The original full scan session
  `codex-source-security-check-loop-session-743` also remains stalled at the
  same step with eight untriaged scanner heuristics. No terminal zero-high/mid
  decision is available, so TASK-005 and the overall completion checklists
  remain unchecked. No repository source or generated `.build` file changed
  during this retry.

## 9. Risks and controls

- **Policy incompleteness:** New aliases or recursively encoded fields can hide
  effect. Control with closed allowlists, shared recursive rules, bounded
  decoding, semantic value tests, and deny-on-unknown behavior.
- **API compatibility:** Exact-request confirmation may require a signature or
  plan-schema change. Control with a schema bump and only compatibility paths
  that preserve exact-request reclassification; never accept schema-v1 risk.
- **Mixed journal schemas:** Atomic rollout is required. Control by rejecting
  legacy/missing schemas and providing no implicit migration.
- **Trusted-head interruption:** Record replacement can precede anchor update.
  Control through fail-closed reads and identity-bound administrative recovery
  evidence; ordinary apply cannot repair.
- **Host/process compromise:** Same-privilege compromise can still read
  credentials or alter mutable state. The trusted-head store must remain
  genuinely separate; this residual risk is not closed by these findings.
- **External/runtime uncertainty:** Meta contracts, dependencies, host
  isolation, custom embeddings, and provider-controlled recursive JSON remain
  outside offline verification. Network audits stay disabled as required.
