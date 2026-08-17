# Typed Ads Writer and Spend Safety Implementation Plan

**Status:** In progress; foundational safety slice implemented
**Workflow mode:** `issue-resolution`
**Feature ID:** `meta-ads-writer-safety`
**Feature title:** Typed Ads writer and spend safety
**Issue reference:** `workflow:codex-design-and-implement-review-loop-session-732/communication:comm-002452`
**Design reference:** `design-docs/meta-ads-writer-safety.md`
**Codex agent reference:** `../google-marketing-gateway`
**Created:** 2026-08-15

## 1. Outcome

Implement the accepted writer-safety design as the only mutation path in the
Swift Meta Marketing gateway. The completed slice will provide separate reader
and writer APIs, typed paused Ads mutations, an endpoint-extensible generic
Graph mutation surface, deterministic previews, explicit confirmations, durable
idempotency/replay defense, destructive-operation gates, verified test-asset
handling, and an enforceable v1 live-spend authorization of USD 0 (strictly
below the issue ceiling of USD 20).

The implementation must not commit, push, publish, deploy, create a billable
campaign, activate delivery, or persist credentials. Kinko remains the only
credential store and is invoked only with explicit environment allowlists.

## 2. Starting point and dependencies

The target repository is empty at plan creation. File paths below are the target
layout; if the repository-foundation feature establishes equivalent SwiftPM
targets first, integrate with those names rather than duplicating modules.

| Dependency | Required contract | Blocking behavior |
|---|---|---|
| SwiftPM foundation | Library targets for graph core, reader, writer, and CLI executable targets. | Create the minimum targets in TASK-001 only if they do not already exist. |
| HTTP transport | Injectable async transport that reports whether request bytes may have been sent and disables cross-origin auth redirects. | Do not emulate send-boundary uncertainty with a plain `URLSession.data` wrapper that cannot classify it. |
| Authentication slice | Environment-backed credential provider with non-secret profile metadata and provider-authenticated app/actor identity lookup. | This feature owns the fail-closed interface and test fake; real setup may remain external. |
| Reader slice | Typed/generic read-only request execution for preflight observations and reconciliation. | Writer must depend on a reader protocol, not its CLI. |
| Official Meta contracts | Current Graph version, fields, permissions, sandbox evidence, and any endpoint-specific validation/idempotency rules. | Recheck official Meta docs on implementation day; do not infer global behavior. |
| Kinko | Installed CLI syntax for explicit environment allowlists. | Verify `kinko exec --help`; never test by echoing secret variables. |

## 3. Design-to-deliverable traceability

| Accepted design area | Implementation deliverable | Primary tasks |
|---|---|---|
| Reader/writer separation | Separate Swift targets/types and binaries; reader cannot import writer. | TASK-001, TASK-012 |
| Typed mutations | Closed request enums/models and descriptors for campaigns, ad sets, ads, creatives, audiences, and ads rules. | TASK-003, TASK-009 |
| Generic endpoint coverage | Relative Graph request builder and validated runtime descriptor bundles with immutable safety clamps. | TASK-002, TASK-004, TASK-010 |
| Preview/confirmation | Canonical intent, read-only observations, deterministic preview artifact, risk-specific confirmation. | TASK-002, TASK-005, TASK-006 |
| Idempotency/replay | Secure journal, permanent tombstones, uncertainty states, reconciliation. | TASK-007, TASK-008 |
| Destructive controls | Immutable policy engine, affected-resource closure, explicit destructive flags, no bulk destructive v1. | TASK-003, TASK-004, TASK-006, TASK-008 |
| Test/live-spend policy | Provider-verified non-billable classification, all else live, v1 activation/budget denial, USD 0 ledger. | TASK-011 |
| Kinko/secrets | Explicit allowlists, delayed credential resolution, safe artifacts and errors. | TASK-008, TASK-012 |

## 4. Planned file layout

Exact file splits may change to match the shared foundation, but responsibility
boundaries must remain intact.

```text
Package.swift
Sources/
  MetaGraphCore/
    CanonicalJSON.swift
    GraphRequest.swift
    GraphTransport.swift
    SafeGraphError.swift
  MetaMarketingReader/
    MetaMarketingReader.swift
    MutationObservationReader.swift
  MetaMarketingWriter/
    MetaMarketingWriter.swift
    MutationDescriptor.swift
    MutationIntent.swift
    MutationPreview.swift
    MutationConfirmation.swift
    MutationPolicy.swift
    MutationJournal.swift
    MutationReconciler.swift
    RuntimeDescriptorRegistry.swift
    SpendSafety.swift
    TypedAdsMutations.swift
    GenericGraphMutation.swift
  MetaMarketingCLISupport/
    SafeCLIOutput.swift
  MetaMarketingReaderCLI/
    main.swift
  MetaMarketingWriterCLI/
    main.swift
    WriterCommand.swift
scripts/
  verify-capability-boundaries.sh
  verify-no-secret-artifacts.sh
Tests/
  MetaGraphCoreTests/
  MetaMarketingWriterTests/
  MetaMarketingGatewayCLITests/
```

Prefer responsibility-based files below 1,000 lines. No writer source may be
added to the reader target's dependencies.

## 5. Work plan

### TASK-001: Establish capability-separated package boundaries

**Parallelizable:** No
**Depends on:** Repository foundation coordination

**Files:**

- `Package.swift`
- `Sources/MetaGraphCore/`
- `Sources/MetaMarketingReader/`
- `Sources/MetaMarketingWriter/`
- `Sources/MetaMarketingCLISupport/`
- `Sources/MetaMarketingReaderCLI/`
- `Sources/MetaMarketingWriterCLI/`
- `scripts/verify-capability-boundaries.sh`
- corresponding test targets

**Work:**

- Define library products `MetaGraphCore`, `MetaMarketingReader`, and
  `MetaMarketingWriter` plus separate `MetaMarketingReaderCLI` and
  `MetaMarketingWriterCLI` executable targets/products named
  `meta-marketing-gateway-reader` and `meta-marketing-gateway-writer`.
- If CLI output/parsing utilities are shared, keep them in a mutation-free
  `MetaMarketingCLISupport` target. Reader CLI must not compile or link writer
  command routing, even behind a runtime flag.
- Make writer depend on core and the narrow reader observation protocol. Do not
  let core or reader depend on writer.
- Add a package-structure test or source import audit that fails if the reader
  exposes `POST`/`DELETE` mutation dispatch or imports the writer module.
- Add `scripts/verify-capability-boundaries.sh` to inspect SwiftPM dependency
  metadata and linked symbols/imports for a reader-to-writer dependency.
- Reconcile names with concurrent foundation work without broadening this
  feature beyond the accepted design.

**Completion criteria:**

- [ ] SwiftPM resolves all targets with a one-way reader-to-writer boundary.
- [ ] Reader public API has no mutation, apply, delete, or unsafe execute method.
- [ ] Reader CLI cannot route to writer commands.
- [ ] Reader executable dependency/linkage audit contains no writer target or
  writer mutation symbols.
- [ ] Writer tests can inject transport, clock, ID generator, credential provider,
  observation reader, journal, and policy registry.

### TASK-002: Implement official-origin Graph requests and canonical intent

**Parallelizable:** No
**Depends on:** TASK-001

**Files:**

- `Sources/MetaGraphCore/CanonicalJSON.swift`
- `Sources/MetaGraphCore/GraphRequest.swift`
- `Sources/MetaGraphCore/GraphTransport.swift`
- `Sources/MetaMarketingWriter/MutationIntent.swift`
- `Tests/MetaGraphCoreTests/CanonicalJSONTests.swift`
- `Tests/MetaGraphCoreTests/GraphRequestTests.swift`

**Work:**

- Build URLs only from `https://graph.facebook.com`, an allowlisted Graph
  version, and validated relative node/edge components.
- Reject absolute/scheme-relative URLs, dot segments, encoded path traversal,
  alternate hosts, arbitrary headers, auth parameters, redirect auth, and
  caller-selected unverified versions or methods.
- Implement canonical JSON with sorted keys, normalized numbers and Unicode,
  explicit null versus omission, stable identifier encoding, and deterministic
  SHA-256 digests.
- Include operation, version, profile name, non-secret app/actor IDs, journal
  namespace, all target IDs, normalized inputs, upload hashes, observations,
  risk/spend classes, descriptor digest, and idempotency key in the intent.

**Completion criteria:**

- [ ] Equivalent intents always yield byte-identical canonical JSON and digest.
- [ ] Any target, input, identity, version, policy, precondition, or key change
  changes the digest.
- [ ] Host/header/token/path traversal corpus tests fail before credentials or
  transport are touched.
- [ ] Cross-origin redirects cannot carry authorization.

### TASK-003: Implement immutable mutation descriptors and policy taxonomy

**Parallelizable:** After TASK-002
**Depends on:** TASK-002

**Files:**

- `Sources/MetaMarketingWriter/MutationDescriptor.swift`
- `Sources/MetaMarketingWriter/MutationPolicy.swift`
- `Tests/MetaMarketingWriterTests/MutationPolicyTests.swift`

**Work:**

- Model stable operation ID, path/method shape, capability, risk, spend effect,
  reversibility, test support, affected-resource resolver, observation fields,
  confirmation class, allowed parameters, response projection, redaction, and
  endpoint-specific retry/idempotency contract.
- Model `standard`, `highRisk`, `destructive`, and `spendAffecting` confirmation
  classes by business effect rather than verb.
- Add immutable denies for access/ownership, business/ad-account assignment,
  billing/payment/funding source, account spend cap/status, token/credential,
  customer/audience membership upload, unknown sensitive data, and v1 live
  activation or live budget increase.
- Ensure no descriptor can enable a direct execution escape hatch.

**Completion criteria:**

- [ ] Invalid, contradictory, unknown-risk, and underspecified descriptors fail
  construction.
- [ ] Generic `DELETE` is destructive and generic writes default to maximum risk.
- [ ] V1 hard-denied capability tests cannot be relaxed by descriptor input.
- [ ] Typed and generic requests use the same policy evaluator.

### TASK-004: Add constrained runtime descriptor bundles

**Parallelizable:** After TASK-003
**Depends on:** TASK-002, TASK-003

**Files:**

- `Sources/MetaMarketingWriter/RuntimeDescriptorRegistry.swift`
- `Tests/MetaMarketingWriterTests/RuntimeDescriptorRegistryTests.swift`
- `Tests/Fixtures/RuntimeDescriptors/`

**Work:**

- Decode versioned declarative bundles with bounded size/depth and strict
  schema; validate official origin, allowlisted Graph version/method, relative
  path template, parameters, structured response projection, and full SHA-256.
- Ignore/reject caller attempts to lower risk. Force runtime policies to maximum
  risk, destructive, spend-possible, verified-non-billable-test-only.
- Disallow file/raw-byte uploads and immutable-deny categories.
- Require a read-only affected-resource closure resolver. Apply only when every
  direct/indirect resource is independently provider-verified non-billable test;
  unknown, cross-business, external, or live closure is preview-only.
- Opaque-redact every runtime parameter/file value; preserve only name, type,
  byte count, and digest. Discard free-text provider messages/bodies.
- Bind bundle bytes/digest to intent, preview, confirmation, journal, receipt.

**Completion criteria:**

- [ ] A safe future relative endpoint fixture can preview and apply through a
  fake transport without a new transport or typed API.
- [ ] Live, sensitive-data, secondary-live-resource, incomplete-closure, upload,
  and risk-downgrade runtime fixtures are denied before credential resolution.
- [ ] Malformed/oversized/deep bundles and partial digest matches fail closed.
- [ ] Runtime previews and errors contain none of the sentinel parameter values.

### TASK-005: Build read-only preparation and deterministic previews

**Parallelizable:** After TASK-003
**Depends on:** TASK-002, TASK-003, reader observation protocol

**Files:**

- `Sources/MetaMarketingReader/MutationObservationReader.swift`
- `Sources/MetaMarketingWriter/MutationPreview.swift`
- `Tests/MetaMarketingWriterTests/MutationPreviewTests.swift`

**Work:**

- Validate local syntax and secure files before resolving a reader credential.
- Resolve and bind provider-authenticated, non-secret app/actor identity.
- Execute only descriptor-declared read-only observations; label them as reader
  transport and hash the exact observed fields used as preconditions.
- Emit versioned deterministic preview JSON with redacted diff, defaults,
  targets, affected-resource closure, risk, reversibility, asset/spend policy,
  warnings/denials, idempotency key, digest, expiry, and confirmation class.
- Represent uploads by safe label, media type, byte count, and content hash only.

**Completion criteria:**

- [ ] Preview sends no mutation under success, error, cancellation, or timeout.
- [ ] Preview fixtures are byte-stable with injected clock/ID generator.
- [ ] Preview artifact has no tokens, secrets, auth headers, raw private data, or
  unrestricted provider message/body.
- [ ] Changed or missing observations make apply ineligible.

### TASK-006: Enforce confirmations and secure request files

**Parallelizable:** After TASK-005
**Depends on:** TASK-003, TASK-005

**Files:**

- `Sources/MetaMarketingWriter/MutationConfirmation.swift`
- secure local-file helper in the shared core target
- `Tests/MetaMarketingWriterTests/MutationConfirmationTests.swift`
- `Tests/MetaMarketingGatewayCLITests/WriterConfirmationCLITests.swift`

**Work:**

- Require full intent digest for all apply operations.
- Require `--allow-high-risk` plus exact operation/target confirmation for high
  risk; add `--allow-destructive` and repeated exact resource ID for destructive.
- Deny `--yes`, partial digests, confirmation in request files/environment,
  expired previews, wrong target/profile/identity, and destructive batches.
- Read preview/request/descriptor/upload files through a race-resistant helper;
  reject symlinks, non-regular files, insecure modes, replacement, oversize,
  malformed/deep JSON, and unsupported media types.

**Completion criteria:**

- [ ] Each confirmation class has positive and adversarial tests.
- [ ] Every confirmation mismatch fails before mutation credential resolution.
- [ ] Interactive and non-interactive flows enforce identical evidence.
- [ ] File validation failures do not read credentials or call transport.

### TASK-007: Implement the durable idempotency journal

**Parallelizable:** After TASK-002
**Depends on:** TASK-002

**Files:**

- `Sources/MetaMarketingWriter/MutationJournal.swift`
- `Tests/MetaMarketingWriterTests/MutationJournalTests.swift`

**Work:**

- Scope keys by journal namespace, profile, Meta app/actor IDs, business/ad
  account, operation, and idempotency key; bind the canonical intent digest.
- Implement `prepared`, `inFlight`, `succeeded`, `failedSafeToRetry`, and
  `outcomeUnknown` with atomic transitions and sanitized receipt digests.
- Use a `0700` directory, `0600` regular files, process locking, atomic replace,
  sequence numbers, and hash links; reject symlinks, broken ownership/mode,
  corruption, truncation, duplicate sequence, and missing namespaces.
- Retain scoped key/digest/target/state/receipt-digest tombstones permanently
  within the namespace even if receipt payloads are compacted.
- Make namespace creation an explicit administrative API outside mutation apply;
  deny rotation with unresolved records and invalidate old previews.

**Completion criteria:**

- [ ] Same key/same successful digest returns the recorded receipt without HTTP.
- [ ] Same key/different digest, in-flight, and unknown-outcome always deny.
- [ ] Safe-retry requires descriptor approval and a fresh exact preview.
- [ ] Restart, lock contention, crash points, compaction, corrupt/missing journal,
  namespace rotation, and tombstone retention tests pass.
- [ ] Journal fixture scans contain no credentials or raw bodies.

### TASK-008: Implement apply orchestration, send boundary, and reconciliation

**Parallelizable:** No
**Depends on:** TASK-002 through TASK-007, TASK-011

**Files:**

- `Sources/MetaMarketingWriter/MetaMarketingWriter.swift`
- `Sources/MetaMarketingWriter/MutationReconciler.swift`
- transport send-boundary support
- `Tests/MetaMarketingWriterTests/MutationApplyTests.swift`
- `Tests/MetaMarketingWriterTests/MutationReconciliationTests.swift`

**Work:**

- Implement the accepted order: local checks; confirmation/digest; journal bind;
  reader state/closure; immutable/spend policy; mutation credential resolution;
  app/actor identity match; atomic `inFlight`; one send; terminal journal state;
  sanitized receipt and optional typed read-back.
- Distinguish failures before any bytes, documented safe provider failures,
  authoritative success, and any possibly-sent uncertainty.
- Retry automatically only before bytes or under current, operation-specific
  official provider idempotency semantics encoded in a built-in descriptor.
- Add typed reconciliation reads that can prove effect/non-effect. Never offer a
  force replay when reconciliation is inconclusive.

**Completion criteria:**

- [ ] Transport fake covers cancellation, timeout, disconnect, decode failure,
  4xx, 5xx, and crash immediately before/after the send boundary.
- [ ] Possibly-sent failures persist `outcomeUnknown` and never auto-replay.
- [ ] Credential rotation for the same app/actor works; different app/actor fails
  before `inFlight` and HTTP mutation.
- [ ] Read-back records `verified`, `pending`, or `verificationUnavailable`
  without interpreting pending as permission to replay.

### TASK-009: Add typed paused Ads-domain mutations

**Parallelizable:** After TASK-003 and TASK-005
**Depends on:** TASK-003, TASK-005, TASK-008 contract

**Files:**

- `Sources/MetaMarketingWriter/TypedAdsMutations.swift` or domain-specific files
- domain model files shared with reader as appropriate
- `Tests/MetaMarketingWriterTests/TypedAdsMutationTests.swift`

**Work:**

- Add closed request models and built-in descriptors for campaign, ad set, ad,
  creative, audience, and ads-rule create/update/pause/destructive operations
  enumerated by the design.
- Use provider-verified, domain-specific non-serving defaults: `PAUSED` only on
  resource types that support it, `DISABLED` where that is the documented safe
  state, and no invented lifecycle field for non-serving resource types.
  Reject any create/transition that can activate delivery in v1.
- Treat targeting, schedules, bids, budgets, rule definitions, audience delete,
  archive, and delete according to the accepted risk taxonomy.
- Keep customer/audience membership upload, permission/ownership, billing,
  account status/spend cap, and rule enablement on live assets excluded.
- Decode response enums with `unknown(String)` while keeping typed request enums
  closed. Verify fields/permissions/version against current official Meta docs.

**Completion criteria:**

- [ ] Each typed operation has request validation, canonical intent, preview,
  policy, confirmation, provider request, response, receipt, and error tests.
- [ ] No serving-capable typed create can emit `ACTIVE` even if raw JSON attempts
  to inject it; other resource types do not invent unsupported lifecycle fields.
- [ ] Destructive and spend-affecting field changes cannot masquerade as standard.
- [ ] Official-contract verification date/version is recorded in fixtures/docs.

### TASK-010: Implement generic mutation and batch behavior

**Parallelizable:** After TASK-004 and TASK-008
**Depends on:** TASK-004, TASK-008

**Files:**

- `Sources/MetaMarketingWriter/GenericGraphMutation.swift`
- `Tests/MetaMarketingWriterTests/GenericGraphMutationTests.swift`
- `Tests/MetaMarketingWriterTests/GraphBatchMutationTests.swift`

**Work:**

- Accept only allowlisted version, validated relative template, descriptor-
  authorized mutation method, typed values, and secure handles.
- Route built-in and runtime descriptors through the same apply state machine.
- Preview batches as ordered entries with aggregate and per-entry digests.
- Require every entry to pass before send and journal provider results per entry;
  do not treat a batch as atomic or idempotent.

**Completion criteria:**

- [ ] Generic fixtures cover current-shaped and invented future relative edges
  without changing transport API.
- [ ] Unknown/unclassified operations cannot live-apply or lower maximum risk.
- [ ] Partial batch results produce independent terminal/unknown states and no
  automatic retry of failed or uncertain entries.
- [ ] Absolute URL, auth injection, unknown method/version, and path attacks fail.

### TASK-011: Enforce verified test assets and USD 0 v1 live authorization

**Parallelizable:** After TASK-005
**Depends on:** TASK-003, TASK-005, TASK-007

**Files:**

- `Sources/MetaMarketingWriter/SpendSafety.swift`
- `Tests/MetaMarketingWriterTests/AssetClassificationTests.swift`
- `Tests/MetaMarketingWriterTests/SpendSafetyTests.swift`

**Work:**

- Classify only current provider-verified non-billable sandbox/test assets as
  `verifiedNonBillableTest`; classify all other assets as `live`, including
  development-owned real accounts and unverified/paused targets.
- Deny live activation, live budget increase, live rule enablement, non-USD
  spend-affecting writes, and any request whose liability cannot be hard-bounded.
- Implement the v1 spend ledger with an authorization ceiling of USD 0. A later
  reviewed implementation may reserve at most 1,999 integer cents, but this plan
  does not enable that future state.
- Display authorization ceiling as distinct from actual provider invoicing and
  concurrent/external spend.

**Completion criteria:**

- [ ] Caller labels, ownership, names, and paused status cannot create test class.
- [ ] Stale/missing provider evidence classifies the target live.
- [ ] Every delivery-capable or live budget-changing fixture is denied before
  mutation credential resolution and transport.
- [ ] Boundary tests prove USD 0 is authorized and USD 0.01/USD 19.99/USD 20.00
  live liability all remain denied in v1.

### TASK-012: Add Kinko-only CLI, sanitization, documentation, and full verification

**Parallelizable:** After TASK-005; final verification waits for all tasks
**Depends on:** TASK-001 through TASK-011

**Files:**

- `Sources/MetaMarketingWriterCLI/WriterCommand.swift`
- `Sources/MetaMarketingCLISupport/SafeCLIOutput.swift`
- `Sources/MetaGraphCore/SafeGraphError.swift`
- CLI and sanitizer tests
- `scripts/verify-capability-boundaries.sh`
- `scripts/verify-no-secret-artifacts.sh`
- `README.md` and writer safety documentation, if owned by the implementation branch
- `design-docs/meta-ads-writer-safety.md` only if implementation requires a reviewed design correction
- `impl-plans/meta-ads-writer-safety.md` progress checkboxes/log

**Work:**

- Expose `preview`, `apply`, `reconcile`, and journal inspection/status commands
  with stable JSON output and categorized nonzero exit codes.
- Reject credential flags, token query/body fields, `.env`, secret config, stdin
  secrets, environment approval, `--yes`, and unrestricted debug output.
- Resolve only centrally allowlisted environment names and document explicit
  `kinko exec --env ... --` invocations after checking installed CLI syntax.
- Sanitize access/refresh/system-user tokens, app secret, `appsecret_proof`, auth
  headers, cookies, raw provider bodies/messages, customer data, emails, request
  values, and upload content across stdout/stderr/errors/previews/receipts/journal.
- Preserve safe structured error code/subcode, operation/field path, HTTP status,
  and `fbtrace_id` only through allowlisted extraction.
- Run the verification matrix without a live mutation or billable campaign.

**Completion criteria:**

- [ ] `preview`, denied `apply`, journal, and reconciliation CLI JSON fixtures are stable.
- [ ] Sentinel secret corpus is absent from every observable artifact.
- [ ] Kinko is the only documented credential source and every example has an
  explicit environment allowlist.
- [ ] Full lint, tests, build, diff checks, and secret/path audits pass.
- [ ] No network mutation, live spend, commit, push, publish, or deploy occurs.

## 6. Dependency order and parallel work

```text
TASK-001 -> TASK-002 -> TASK-003 -> TASK-005 -> TASK-006
                    |         |          |
                    |         |          +-> TASK-011
                    |         +-> TASK-004
                    +-> TASK-007

TASK-002..007 + TASK-011 -> TASK-008 -> TASK-009 and TASK-010 -> TASK-012
```

- TASK-004, TASK-005, and TASK-007 can proceed in parallel after their listed
  prerequisites.
- TASK-006 and TASK-011 can proceed in parallel after preview/policy contracts.
- TASK-008 cannot expose callable apply until TASK-011's asset classifier and
  USD 0 live-spend gate are integrated and passing.
- TASK-009 domain models may be split by domain after the common descriptor and
  preview APIs stabilize, but all changes share the same policy test suite.
- TASK-008 integrates the safety state machine and should land before generic or
  typed routes become callable.
- TASK-012 owns final verification and must not enable live apply to obtain test
  coverage.

## 7. Test and adversarial review matrix

| Boundary | Required cases |
|---|---|
| Origin/request | Absolute and scheme-relative URL, encoded traversal, alternate host/port, version/method injection, auth header/query/body injection, redirect. |
| Canonical intent | Key order, Unicode, numbers, null/omission, every bound identity/target/policy/key field, descriptor digest. |
| Preview | No mutation, read-only labeling, stable artifact, stale/missing observation, safe upload projection, no secrets. |
| Confirmation | Missing/wrong/partial digest, wrong target/profile/actor, expired preview, `--yes`, environment/request-file confirmation, destructive batch. |
| Descriptor | Runtime risk downgrade, immutable deny category, file/raw data, incomplete/live resource closure, malformed/deep/large bundle. |
| Journal | Duplicate/conflicting key, restart, contention, atomic crash points, unknown outcome, compaction/tombstone, corruption, missing journal, namespace rotation. |
| Send boundary | Failure before bytes, possibly sent timeout/disconnect/cancel, provider rejection, success then decode failure, read-back pending. |
| Spend/assets | Caller-labeled test, development-owned live, stale evidence, activation, budget increase, rule enable, non-USD, 0/1/1999/2000 cents. |
| Sanitization | All secret classes, provider body/message, customer/upload data, email, headers/cookies across all outputs and journal. |

An independent adversarial reviewer must inspect implementation diffs for raw
transport escape hatches, credential persistence, unsafe retry, risk downgrade,
secondary-resource classification, journal rollback/tombstone loss, and spend
ceiling bypass before the feature is marked complete.

## 8. Verification commands

Run from the repository root.

Documentation/plan verification available now:

```bash
test -f design-docs/meta-ads-writer-safety.md
test -f impl-plans/meta-ads-writer-safety.md
git diff --check -- design-docs/meta-ads-writer-safety.md impl-plans/meta-ads-writer-safety.md
rg -n "Kinko|kinko exec|USD 20|USD 0|idempot|outcomeUnknown|allow-destructive" \
  design-docs/meta-ads-writer-safety.md impl-plans/meta-ads-writer-safety.md
```

Implementation verification after Swift files exist:

```bash
swift package describe
swift build
swift test --filter MetaGraphCoreTests
swift test --filter MetaMarketingWriterTests
swift test --filter MetaMarketingGatewayCLITests
swift test
swiftlint lint --strict
```

If repository tasks wrap those commands, also run:

```bash
mise install
mise run lint
mise run test
mise run build
```

Kinko syntax and credential-source audit (never print values):

```bash
kinko exec --help
./scripts/verify-capability-boundaries.sh
./scripts/verify-no-secret-artifacts.sh
! find . -type f \( -name '.env' -o -name '.env.*' \) -print | rg -q .
```

Optional authenticated verification is read-only preview on a Meta-verified test
asset and requires explicit authorization plus the setup identity
`taco-dev-sandbox@mutvar.com`. Confirm installed Kinko syntax first:

```bash
kinko exec --env META_ACCESS_TOKEN,META_APP_SECRET -- \
  swift run meta-marketing-gateway-writer ads campaign preview \
  --request Tests/Fixtures/CLI/test-campaign-preview.json
```

Do not run an `apply` command against a live asset. No verification command in
this plan creates or activates a billable campaign.

## 9. Progress tracking

- [ ] TASK-001: Capability-separated package boundaries
- [ ] TASK-002: Official-origin Graph requests and canonical intent
- [ ] TASK-003: Immutable descriptors and policy taxonomy
- [ ] TASK-004: Constrained runtime descriptor bundles
- [ ] TASK-005: Read-only preparation and deterministic previews
- [ ] TASK-006: Confirmations and secure request files
- [ ] TASK-007: Durable idempotency journal
- [ ] TASK-008: Apply orchestration, send boundary, reconciliation
- [ ] TASK-009: Typed paused Ads-domain mutations
- [ ] TASK-010: Generic mutation and batch behavior
- [ ] TASK-011: Verified test assets and USD 0 v1 live authorization
- [ ] TASK-012: Kinko-only CLI, sanitization, docs, full verification

## 10. Progress log

- 2026-08-15: Plan created from the independently accepted feature design. No
  source implementation, network mutation, spend, commit, or push performed.
- 2026-08-15: Added fixed-origin generic `POST`/`DELETE` planning, canonical
  request/body/query digests, plan expiry, exact confirmation, high-impact
  second acknowledgement, and secure request/plan file checks. Focused tests
  prove plan/request binding, deny a missing high-impact acknowledgement, and
  prove that V1 rejects every mutation send before credential resolution until
  verified test-asset, principal, journal, and USD 0 policy work lands.
  `mise run lint`, `mise run test`, and `mise run build` passed. Journal/
  tombstones, authenticated principal binding, runtime descriptors, typed
  paused mutations, verified-asset classification, and USD 0 enforcement
  remain unchecked. No network mutation, spend, stage, commit, push, publish,
  or deploy occurred.
- 2026-08-15: Self-review correction: `confirm` recomputes the full canonical
  plan digest and rejects altered method/version/path/risk/expiry/request
  bindings; secure input/output now uses no-follow file descriptors. Added
  tamper and symlink tests. All writer TASK-001 through TASK-012 completion
  criteria remain unchecked pending their full implementations.
- 2026-08-15: Added immutable mutation descriptor validation, provider-evidence
  freshness classification, USD 0 authorization enforcement, and a
  process-local idempotency state machine that permanently blocks an unknown
  outcome for its lifetime. These are offline safety primitives only: the
  generic writer remains fail-closed because durable journal storage,
  provider-authenticated principal binding, descriptors/closures, typed
  mutations, and apply reconciliation are still incomplete. Focused tests pass
  with USD 0 and no mutation.
- 2026-08-15: Reconfirmed that the generic writer still denies every apply
  before credential resolution. The upload and retry changes do not widen writer
  authority. Durable journal storage, provider-authenticated principal and asset
  evidence, typed mutations, reconciliation, and TASK-007 through TASK-011
  remain unchecked and release-blocking.
- 2026-08-15: Added `DurableMutationJournal`: a `0700` namespace directory,
  `0600` no-follow record files, nonblocking cross-process lock, atomic
  replacements, persisted states, and permanent tombstone records without
  request bodies or credentials. Restart/unknown-outcome regression coverage
  passes. It is intentionally not wired to apply until provider-authenticated
  identity, verified assets, descriptor closure, and reconciliation land.
- 2026-08-15: Hardened the durable journal with explicit namespace creation,
  directory fsync after record creation/replacement, monotonic event sequences,
  and per-transition hash links. Added restart and tamper-chain regressions.
  Namespace rotation, compaction, crash injection, and apply integration remain
  unchecked and release-blocking.
- 2026-08-15: Added a dependency-injected, mock-tested apply slice that binds a
  canonical confirmed plan to an immutable descriptor, provider-authenticated
  principal evidence, fresh provider-verified non-billable asset evidence, and
  USD 0 authorization before one mutation transport send. Persisted successful
  receipts suppress duplicate sends; transient outcomes become permanent
  unknown-outcome tombstones and reconciliation is explicit and never replays.
  The production CLI remains fail-closed because provider verifiers,
  descriptors/closures, typed mutations, compaction/rotation/rollback, crash
  injection, and concrete reconciliation integrations remain unchecked.
- 2026-08-15: Rechecked expiry immediately before durable journal preparation,
  compare provider principal identity by app/actor rather than evidence time,
  and preserve a matching `prepared` record after a pre-send credential failure
  so it can safely retry before any mutation bytes. Deterministic tests cover
  expired-plan rejection without a journal record, same-identity credential
  rotation, and one successful retry after a credential failure. Production CLI
  orchestration, typed mutations, compaction/rotation/rollback, and crash-point
  requirements remain unchecked.

- 2026-08-15: Rechecked expiry after asynchronous provider verification and again after the
  asynchronous `inFlight` journal transition immediately before transport. A late expiry before
  sending leaves a retry-safe durable record and sends no bytes. The production CLI remains
  fail-closed pending provider verifier, descriptor registry, typed mutation, and reconciliation
  integrations; compaction, rotation, rollback, and crash-point requirements remain unchecked.
- 2026-08-15: Added deterministic coverage for expiry after the asynchronous `inFlight`
  transition. The journal records `failedSafeToRetry` and the mock transport observes zero sends.
- 2026-08-15: Added terminal-record compaction that retains key/digest/state/receipt tombstones,
  explicit rotation that denies unresolved records, an optional separately protected trusted-head
  store that detects rollback, and before/after atomic-replacement crash checkpoints. Offline
  regressions cover compaction, trusted-head rollback rejection, terminal-only rotation, and both
  crash sides of replacement. Production CLI provider wiring, typed mutations, and independent
  security gates remain unchecked.
- 2026-08-15: Address and thread sanitizer suites passed with 43 offline XCTest cases. Gitleaks,
  Semgrep, OSV Scanner, Syft, and Trivy are now installed and their scoped local scans completed
  without findings; this is evidence for delivery gates only and does not authorize production apply.
- 2026-08-15: Bound durable journals to a persisted namespace marker and require executable plans,
  journal keys, and apply dependencies to use that exact namespace. Rotation now requires a fresh
  directory, retires the old namespace, and rejects old previews/keys. A configured trusted-head
  store now fails closed when an anchor is absent; production-oriented apply dependencies require
  that anchor unless a deterministic test explicitly opts out. Regressions cover old-key rejection
  after rotation and missing-anchor rejection. Concrete CLI verifiers, typed mutations, and
  reconciliation wiring remain unchecked.
- 2026-08-15: Hardened rotation recovery: every durable-journal operation now checks the retired
  marker while holding the journal lock, so pre-rotation actor instances cannot read, prepare,
  transition, reconcile, compact, or rotate retired records. Trusted-head validation now requires
  exact current sequence/hash equality; a stale anchor fails closed until an explicit
  `repairTrustedHeadAnchor` recovery action is performed. Production
  `MutationApplyDependencies` no longer exposes an unanchored public bypass; only an internal
  `@testable` construction seam supports deterministic offline fakes. Regressions cover retired
  actors, stale-anchor recovery, and public anchoring enforcement. CLI provider wiring, typed
  mutations, and reconciliation integration remain unchecked and release-blocking.
- 2026-08-15: Replaced ordinary trusted-head repair with the explicit
  `repairTrustedHeadAnchorAdministratively(for:expectedHead:)` capability. Recovery now requires
  independently obtained exact sequence/hash evidence and can only advance an existing protected
  anchor to that exact newer journal head; stale evidence, mismatched hashes, and rolled-back
  records are rejected. Added deterministic regression coverage. Production CLI verifier, asset
  classifier, descriptor registry, typed mutation, journal-configuration, and reconciliation
  wiring remain unchecked.
- 2026-08-15: Restricted the trusted-head recovery evidence type and recovery operation to
  internal administrative composition. Public mutation callers cannot construct recovery
  authorization or invoke anchor repair; tests use only the existing `@testable` seam.
- 2026-08-15: Source-security triage verified `TRIAGE-AUTH-001` (medium): a
  caller could pair a test asset identity with a distinct ad-account path in an
  enabled composition. `MutationApplyAuthorization` now derives and binds the
  only admissible asset ID from the canonical `act_<id>` descriptor prefix;
  reconciliation also rechecks the returned provider asset ID before invoking
  the reconciler. Focused regressions
  `GraphSecurityTests/testWriterRejectsAuthorizationAssetPathMismatch` and
  `GraphSecurityTests/testReconcileRejectsMismatchedAssetEvidence` pass. The
  production provider-verifier/asset-classifier composition remains unchecked;
  no live mutation or spend occurred.

## 11. Plan completion definition

The plan is complete only when every task checkbox and completion criterion is
satisfied, all verification commands applicable to the repository pass, the
independent implementation review has no unresolved high/mid findings, and the
receipt records that verification used mocks/read-only test assets with USD 0
authorized live spend. Deferral must remain unchecked and include an owner,
dependency, and follow-up issue; it cannot be relabeled complete.
