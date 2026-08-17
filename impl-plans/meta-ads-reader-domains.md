# Typed Ads Reader Domains Implementation Plan

**Feature ID**: `meta-ads-reader`

**Feature title**: Typed Ads reader domains

**Issue**: `workflow:codex-design-and-implement-review-loop-session-732/communication:comm-002452`

**Workflow mode**: `issue-resolution`

**Status**: In progress; foundational reader contracts implemented

**Design reference**: `design-docs/meta-ads-reader-domains.md`

**Reference repository**: `../google-marketing-gateway`

**Plan reviewed**: 2026-08-15

## 1. Goal

Implement the accepted typed read surface for Meta ad accounts, campaigns, ad
sets, ads, ad creatives, and synchronous insights on top of the shared generic
Graph API core. Deliver safe field/filter construction, one-page cursor
pagination, tolerant typed decoding, local capability discovery, CLI routing,
tests, and documentation without adding a mutation path or persisting secrets.

## 2. Preconditions and Dependency Gate

Implementation starts only after the shared foundation provides these tested
contracts:

- `Package.swift` with core, reader executable, and core-test targets.
- A fixed-origin Graph request builder for `https://graph.facebook.com` with an
  explicit effective `GraphAPIVersion`.
- `JSONValue`, injected async HTTP transport, response byte/time limits, and
  sanitized provider errors.
- Reader-only operation dispatch and a local catalog route/registry that
  distinguishes implemented typed operations from generic-only capability.
- Credential resolution from a safe environment-variable reference, with
  Kinko as the only credential store and no `.env` loading.
- A bounded regular UTF-8 file loader or a compatible injectable abstraction.

Expected foundation paths are:

- `Sources/MetaMarketingGatewayCore/GraphAPIVersion.swift`
- `Sources/MetaMarketingGatewayCore/GraphPath.swift`
- `Sources/MetaMarketingGatewayCore/GraphQuery.swift`
- `Sources/MetaMarketingGatewayCore/GraphPage.swift`
- `Sources/MetaMarketingGatewayCore/GraphTransport.swift`
- `Sources/MetaMarketingGatewayCore/GraphExecutor.swift`
- `Sources/MetaMarketingGatewayCore/KinkoEnvironmentCredentials.swift`
- `Sources/MetaMarketingGatewayCore/SecureLocalFile.swift`
- `Sources/MetaMarketingGatewayCore/MetaGraphReader.swift`
- `Sources/MetaMarketingGatewayCore/GatewayCLI.swift`
- `Sources/MetaMarketingGatewayReader/main.swift`

If the accepted foundation uses different names, record the mapping in the
progress log before editing; do not create duplicate transport, credential,
catalog, or CLI foundations. A missing behavioral dependency blocks feature
implementation and is escalated to its owning feature rather than silently
implemented here.

## 3. Deliverables

### Production files

- [ ] `Sources/MetaMarketingGatewayCore/MetaAdsIdentifiers.swift`: distinct,
  injection-safe account/campaign/ad-set/ad/creative identifiers.
- [ ] `Sources/MetaMarketingGatewayCore/MetaAdsFields.swift`: versioned domain
  fields, non-empty selection, deterministic presets, and serialization bounds.
- [ ] `Sources/MetaMarketingGatewayCore/MetaAdsFilters.swift`: typed operators,
  values, domain/version matrices, and bounded filter-file decoding.
- [ ] `Sources/MetaMarketingGatewayCore/MetaAdsPagination.swift`: typed cursor
  requests and fixed-request reconstruction adapting the shared `GraphPage`;
  it does not define a second page envelope or paginator.
- [ ] `Sources/MetaMarketingGatewayCore/MetaAdsModels.swift`: tolerant domain
  models, unknown fields, tolerant provider enums, and lossless scalar wrappers.
- [ ] `Sources/MetaMarketingGatewayCore/MetaAdsInsights.swift`: insights subject,
  fields, time range, level, breakdown, attribution, sorting, and response rows.
- [ ] `Sources/MetaMarketingGatewayCore/MetaAdsReader.swift`: typed client
  protocol/implementation and exact request mapping.
- [ ] `Sources/MetaMarketingGatewayCore/MetaAdsCapabilities.swift`: eleven stable
  provider operation descriptors, versioned matrices, and typed/generic
  capability metadata registered with the shared catalog route.
- [ ] `Sources/MetaMarketingGatewayCore/GatewayCLI.swift`: reader-only Ads and
  shared catalog command parsing/dispatch.
- [ ] `Sources/MetaMarketingGatewayReader/main.swift`: composition only if the
  foundation entry point needs typed-reader dependency wiring.

### Test and fixture files

- [ ] `Tests/MetaMarketingGatewayCoreTests/MetaAdsIdentifierTests.swift`
- [ ] `Tests/MetaMarketingGatewayCoreTests/MetaAdsFieldFilterTests.swift`
- [ ] `Tests/MetaMarketingGatewayCoreTests/MetaAdsPaginationTests.swift`
- [ ] `Tests/MetaMarketingGatewayCoreTests/MetaAdsModelTests.swift`
- [ ] `Tests/MetaMarketingGatewayCoreTests/MetaAdsInsightsTests.swift`
- [ ] `Tests/MetaMarketingGatewayCoreTests/MetaAdsRequestTests.swift`
- [ ] `Tests/MetaMarketingGatewayCoreTests/MetaAdsCapabilityTests.swift`
- [ ] `Tests/MetaMarketingGatewayCoreTests/MetaAdsCLITests.swift`
- [ ] `Tests/MetaMarketingGatewayCoreTests/Fixtures/meta-ads/`: synthetic,
  secret-free v26 success, drift, paging, insight-action, and error fixtures.

### Documentation files

- [ ] `README.md`: typed reader examples, generic fallback, catalog command,
  Kinko-only invocation, safety limits, and supported-version policy.
- [ ] `design-docs/meta-ads-reader-domains.md`: update implementation status and
  evidence only if implementation completes without a design change.
- [x] `impl-plans/meta-ads-reader-domains.md`: plan, reviews, progress, and
  verification record.

No other design or plan path is in scope. Any required contract change is first
recorded in `design-docs/meta-ads-reader-domains.md` and re-reviewed.

## 4. Work Breakdown

### TASK-001: Reconcile the shared foundation

**Status**: Pending

**Depends on**: shared generic-core, credential, safety/CLI, and catalog features

**Parallelizable**: No

Inspect `Package.swift`, all expected foundation files, nearby tests, and current
repository instructions. Produce a path/type mapping in the progress log and
confirm that fixed origin/`GraphAPIVersion`, `GraphPath`/`GraphQuery`,
`GraphPage`, `MetaGraphReading`, injected transport, JSON values, response
bounds, reader-only dispatch, safe errors, Kinko environment references, secure
bounded file loading, and the shared `catalog list` extension point exist.

**Completion criteria**:

- [ ] Each dependency is linked to an existing type and test.
- [ ] No duplicate foundation abstraction is proposed.
- [ ] Any behavioral gap is returned to its owner or explicitly added to this
  plan after design re-review.
- [ ] Baseline `mise run test`, `mise run build`, and `mise run lint` pass, or
  pre-existing failures are recorded without being hidden.

### TASK-002: Implement typed IDs and field selection

**Status**: Pending

**Depends on**: TASK-001

**Parallelizable**: Yes, with TASK-003 after shared naming is fixed

Create `MetaAdsIdentifiers.swift` and `MetaAdsFields.swift`. Implement distinct
IDs, canonical `act_` account handling, domain field protocols/enums, non-empty
ordered deduplication, 16 KiB serialization bound, and versioned presets/matrix.
Do not add raw fields, nested expansions, or a wildcard.

**Completion criteria**:

- [ ] IDs reject empty, Unicode digit, whitespace, control, separator, query,
  fragment, and percent-escape injection cases.
- [ ] Account normalization accepts only digits or `act_` plus digits and emits
  one canonical value.
- [ ] Fields are domain/version checked, stable in order, non-empty, bounded,
  and expose no expression passthrough.
- [ ] Tests cover every boundary and prove no credential/transport access on
  invalid input.

### TASK-003: Implement filters and bounded filter files

**Status**: Pending

**Depends on**: TASK-001

**Parallelizable**: Yes, with TASK-002

Create `MetaAdsFilters.swift`. Define the closed operator/value model and the
single versioned domain compatibility matrix used by validation and discovery.
Decode CLI filter files through the shared file loader and encode the official
`filtering` query item exactly once with `JSONEncoder`.

**Completion criteria**:

- [ ] No raw operator, raw JSON fragment, non-finite number, or mixed array is
  accepted.
- [ ] Limits of 50 filters, 64 members per array, and 64 KiB encoded/file bytes
  are tested at, below, and above boundaries.
- [ ] Missing, invalid UTF-8, empty, terminal symlink, non-regular, concurrently
  growing, and malformed JSON files fail before credentials/transport.
- [ ] Capability data and runtime validation are generated from one matrix.

### TASK-004: Implement pagination and response envelopes

**Status**: Pending

**Depends on**: TASK-001

**Parallelizable**: Yes, with TASK-002 and TASK-003

Create `MetaAdsPagination.swift`. Model mutually exclusive directions, bounded
opaque cursors, local limit bounds, and next/previous request reconstruction
from the original typed request while adapting the shared `GraphPage` decode.

**Completion criteria**:

- [ ] Cursor empty/control/16 KiB boundaries and limit 1...500 are covered.
- [ ] Provider `paging.next` and `paging.previous` URLs are ignored even when
  malicious, off-origin, wrong-version, or token-bearing.
- [ ] Reconstructed requests preserve operation, version, fields, filters, and
  subject while changing only the cursor direction/value.
- [ ] Exact validated cursor values appear only in the intended result paging
  object and next request; never in descriptions, logs, errors, or diagnostic
  snapshots.

### TASK-005: Implement tolerant domain models

**Status**: Pending

**Depends on**: TASK-001, TASK-002

**Parallelizable**: Yes, with TASK-003 and TASK-004

Create `MetaAdsModels.swift` with the design's conservative field set. Add
tolerant enums, exact decimal/integer string wrappers where needed,
`additionalFields`, and field-name-only decode failures. Reuse the shared
`JSONValue`; do not create a second JSON tree.

**Completion criteria**:

- [ ] Known fixtures decode into typed properties.
- [ ] Unknown enum values and unconsumed selected fields survive round trips.
- [ ] Missing optional fields do not fail; malformed selected fields fail
  without echoing values.
- [ ] Model descriptions and encoded CLI output contain no credential or raw
  paging URL channel.

### TASK-006: Implement insights contracts

**Status**: Pending

**Depends on**: TASK-002, TASK-003, TASK-004, TASK-005

**Parallelizable**: No

Create `MetaAdsInsights.swift` with closed subject kinds, non-empty fields,
levels, date preset/time-range exclusivity, strict dates, time increments,
breakdown/action-breakdown matrices, attribution windows, sorting, filters, and
lossless rows.

**Completion criteria**:

- [ ] Account/campaign/ad-set/ad subjects map to exact fixed insights paths.
- [ ] Invalid date order, dual date selection, invalid level, duplicate or
  incompatible breakdown, unsupported version, and bounds fail locally.
- [ ] Query item spelling/order is deterministic and values are percent-encoded
  by the request builder, not concatenated.
- [ ] Decimal strings, action arrays, summary/paging shapes, and unknown metrics
  decode losslessly.
- [ ] No async job creation or polling surface is added.

### TASK-007: Implement typed requests and client

**Status**: Pending

**Depends on**: TASK-002 through TASK-006

**Parallelizable**: No

Create `MetaAdsReader.swift`. Map eleven provider reads to exact `GET` requests,
validate before credential resolution, delegate only to the shared Graph client,
and return typed models/pages. Keep local capability discovery separate from the
credentialed provider client.

**Completion criteria**:

- [ ] All operation IDs and fixed paths match the design matrix.
- [ ] No public typed initializer accepts URL, host, raw path, HTTP method,
  header map, access token, app secret, raw query dictionary, or request body.
- [ ] Validation failure records zero credential resolutions and zero requests.
- [ ] Request tests assert exact method, origin, version, path, encoded query,
  auth placement, body absence, response bound, cancellation, and redaction.

### TASK-008: Add catalog-driven capabilities

**Status**: Pending

**Depends on**: TASK-002, TASK-003, TASK-006, TASK-007

**Parallelizable**: No

Create `MetaAdsCapabilities.swift` with the eleven provider operation
descriptors and register them with the shared local `catalog list` route.
Generate field/filter/page/insights discovery from the same runtime matrices and
expose stable schema version 1; do not invent a local provider operation ID.

**Completion criteria**:

- [ ] Catalog IDs are unique, reader-only, correctly dispatchable, and identify
  typed versus generic-only coverage.
- [ ] Capabilities need no profile, credential, Kinko invocation, or network.
- [ ] Effective/tested versions and schema review date are visible.
- [ ] Output omits environment names, tokens, IDs, permissions, and live-access
  implications.
- [ ] Snapshot/semantic tests fail if a dispatch descriptor lacks discovery data
  or discovery advertises a non-dispatchable typed operation.

### TASK-009: Add reader CLI routing

**Status**: Pending

**Depends on**: TASK-007, TASK-008

**Parallelizable**: No

Extend `GatewayCLI.swift` and, only if needed, reader composition. Parse exact
commands/flags from the design, require explicit fields, decode bounded filter
files, emit the shared deterministic JSON envelope, and preserve validation-
before-credential order.

**Completion criteria**:

- [ ] All get/list/insights/catalog command shapes dispatch correctly.
- [ ] Every network command requires the shared `--api-version`; offline catalog
  listing may select a tested version without credentials.
- [ ] Unknown/duplicate/inapplicable flags, missing fields/IDs, stdin fallback,
  origin/version/headers/token overrides, and mutation words are rejected.
- [ ] Capability commands run without credentials; provider reads resolve one
  token only after local validation.
- [ ] Help, success, and every error class are checked against sentinel secret,
  filter, cursor, and provider-message values.
- [ ] Reader executable cannot resolve writer/admin operation descriptors.

### TASK-010: Complete documentation and verification

**Status**: Pending

**Depends on**: TASK-001 through TASK-009

**Parallelizable**: No

Update `README.md`, mark only completed items here, append verification evidence,
and change design status to implemented only after all deterministic gates pass.
Document Kinko allowlisting without example secret values or `.env` files.

**Completion criteria**:

- [ ] README examples use `kinko exec --env META_ACCESS_TOKEN -- ...` and fake
  account IDs only.
- [ ] Typed/current versus generic/future coverage and v26 review basis are
  explicit.
- [ ] Full lint, tests, build, CLI capability smoke, diff check, and secret scan
  pass.
- [ ] No live mutation, paid campaign, credential persistence, commit, push,
  publish, or deploy occurred.

## 5. Test Traceability

| Design contract | Primary tests |
|---|---|
| Identifier isolation and injection safety | `MetaAdsIdentifierTests.swift`, `MetaAdsRequestTests.swift` |
| Fields, presets, and typed-only boundary | `MetaAdsFieldFilterTests.swift`, `MetaAdsCapabilityTests.swift` |
| Filter matrix and bounded files | `MetaAdsFieldFilterTests.swift`, `MetaAdsCLITests.swift` |
| Cursor safety and URL non-following | `MetaAdsPaginationTests.swift`, `MetaAdsRequestTests.swift` |
| Tolerant/lossless response decoding | `MetaAdsModelTests.swift`, `MetaAdsInsightsTests.swift` |
| Insights structural contract | `MetaAdsInsightsTests.swift`, `MetaAdsRequestTests.swift` |
| Local honest discovery | `MetaAdsCapabilityTests.swift`, `MetaAdsCLITests.swift` |
| Reader-only dispatch and redaction | `MetaAdsCLITests.swift`, existing credential/catalog tests |
| Fixed origin/version and response bounds | `MetaAdsRequestTests.swift`, existing transport tests |

Every production deliverable has a directly named test owner. Shared-foundation
tests remain required and are not replaced by feature tests.

## 6. Verification Commands

Run from the repository root after implementation:

```bash
mise install
swift test --filter MetaAdsIdentifierTests
swift test --filter MetaAdsFieldFilterTests
swift test --filter MetaAdsPaginationTests
swift test --filter MetaAdsModelTests
swift test --filter MetaAdsInsightsTests
swift test --filter MetaAdsRequestTests
swift test --filter MetaAdsCapabilityTests
swift test --filter MetaAdsCLITests
mise run lint
mise run test
mise run build
swift run meta-marketing-gateway-reader catalog list --product ads --domain campaigns --api-version v26.0 --output json
git diff --check
git diff -- design-docs/meta-ads-reader-domains.md impl-plans/meta-ads-reader-domains.md Sources/MetaMarketingGatewayCore Tests/MetaMarketingGatewayCoreTests README.md
git status --short
```

Run the following repository scan without printing matched values. It reports
only file names and must return empty for credential-bearing file patterns:

```bash
find . -type f \( -name '.env' -o -name '.env.*' -o -name '*access-token*' -o -name '*app-secret*' \) -print
```

An optional live read smoke is outside deterministic acceptance. If separately
authorized, use only Meta test assets and exactly an explicit Kinko allowlist:

```bash
kinko exec --env META_ACCESS_TOKEN -- \
  swift run meta-marketing-gateway-reader ads campaigns list \
  --api-version v26.0 --account-id act_123456789 --fields id,name
```

Replace the fake account only inside the authorized execution context; do not
save it in the repository. The smoke must not create, mutate, publish, or spend.

## 7. Review Record

### Plan self-review

Decision: **accepted after correction**.

The first plan draft had two plan-only defects: response drift tests were grouped
under request mapping without an owning model task, and completion could be
claimed before the shared foundation was reconciled. TASK-001 is now a blocking
dependency gate; TASK-005 and the traceability matrix explicitly own tolerant
decoding. These defects changed execution completeness, not the accepted design.

The self-review confirmed design-plan consistency, concrete files, dependency
ordering, deliverables, completion criteria, progress fields, and executable
verification commands. It found no new design defect.

### Independent adversarial plan review

Decision: **accepted after correction**.

A separate pass found two medium plan-only defects: capability/runtime matrix
drift had no invariant test, and the verification list did not explicitly check
for credential files. TASK-003 and TASK-008 now require a single shared matrix
plus cross-consistency tests, and verification now includes a filename-only
credential-file scan. During design-plan consistency checking, the plan also
reopened the design's ambiguous cursor-sanitization wording; that medium design
defect was corrected in the design before this plan was reaccepted. Those two
plan findings and the cursor design finding were closed.

The independent pass also checked every design section against at least one
task and test, ensured mutation/async-insights work was absent, confirmed Kinko
and no-spend constraints, and verified that source-path assumptions are gated
rather than silently duplicated. After the cursor-preservation correction, it
found no further design defect. A final cross-feature plan pass then found three
medium plan-only integration defects: stale assumed foundation paths, a task
that could duplicate `GraphPage`, and a parallel `OperationCatalog.swift`
deliverable instead of shared catalog registration. The plan now names the
accepted foundation paths, adapts `GraphPage`, and owns only
`MetaAdsCapabilities.swift`. No high or medium plan finding remains.

## 8. Addressed Feedback

### Design defects resolved before or during planning

- Removed raw field passthrough from typed requests.
- Replaced provider paging-URL exposure/following with bounded opaque cursors and
  fixed typed request reconstruction.
- Replaced floating-point insights decoding with lossless provider-compatible
  values.
- Made cursor redaction and local-only, non-permission capability discovery
  explicit.
- Required exact opaque cursor preservation in the intended result while still
  excluding cursors from logs, errors, and diagnostics.
- Reused the accepted `GraphAPIVersion` and `GraphPage` contracts, required the
  shared network `--api-version`, and replaced a parallel capabilities route
  with Ads descriptors contributed to `catalog list`.

### Plan-only defects resolved

- Added a blocking shared-foundation reconciliation task.
- Added explicit ownership and traceability for response-drift tests.
- Required one source of truth for capability data and runtime validation.
- Added credential-file scanning to verification without printing contents.
- Replaced stale foundation path assumptions with the accepted Graph foundation
  paths and `MetaGraphReading` contract.
- Changed pagination work to adapt `GraphPage` rather than define a duplicate.
- Replaced the parallel `OperationCatalog.swift` deliverable with feature-owned
  `MetaAdsCapabilities.swift` registration into the shared catalog route.

## 9. Progress Log

- 2026-08-15: Plan created from the accepted feature design.
- 2026-08-15: Self-review corrected dependency gating and response-test
  ownership; no design change was required.
- 2026-08-15: Independent adversarial review corrected matrix-drift and
  credential-file verification gaps.
- 2026-08-15: Design-plan consistency review reopened and corrected the
  medium cursor-preservation wording defect, then reaccepted both artifacts.
- 2026-08-15: Cross-feature reconciliation with the accepted Graph foundation
  and delivery artifacts corrected four medium design-integration findings and
  three medium plan-only findings; both artifacts were reaccepted.
- 2026-08-15: Added the shared typed-ID, explicit field-selection, local
  11-operation capability catalog, conservative models with retained unknown
  fields, typed read protocol, and paged request construction in
  `Sources/MetaMarketingGatewayCore/MetaAdsReader.swift`. Focused offline tests
  verify ID/field rejection and credential-free catalog access; `mise run lint`,
  `mise run test`, and `mise run build` passed. Filters, CLI Ads routes,
  lossless insight-specific contracts, fixtures, and full task criteria remain
  unchecked. No live Meta call, spend, stage, commit, or push occurred.
- 2026-08-15: Self-review correction: decoded only `paging.cursors.after` and
  added a regression test proving the typed reader preserves that validated
  structured cursor. TASK-001 through TASK-010 remain incomplete.
- 2026-08-15: Added closed filter operators/value shapes, count/member/byte
  bounds, and deterministic JSON query encoding. Added credential-free
  `catalog list` CLI output. Domain-specific models, insight contracts, and
  typed CLI read routes remain unchecked.
- 2026-08-15: Self-review correction: filter scalar integers and integer arrays
  now encode as JSON numbers, with a semantic regression test. Filter binding
  into every typed request remains unchecked.
- 2026-08-15: Added `MetaAdsListOptions` to bind closed filters exactly once to
  typed list and insight requests, plus lossless insight metric/action JSON
  retention. Fake-reader tests assert filtering query construction and numeric
  and array metric preservation. Domain-specific model matrices and typed CLI
  dispatch remain unchecked; no credential or network access occurred.
- 2026-08-15: Added secure descriptor-based filter-file decoding with the same
  closed filter validation as inline filters, bounded typed all-page helpers
  for every implemented list/insights route, and typed reader CLI list/insight
  dispatch that validates fields, IDs, pagination, and filters before any
  credential resolution. Domain-specific response models, full insights
  matrix, account-list command coverage, fixtures, and final task criteria
  remain unchecked. `swift test` passed offline; no live request or spend
  occurred.
- 2026-08-15: Tightened typed CLI parsing so each operation has an exact flag
  set, malformed or duplicate limits fail before credential resolution, and
  insight subjects use the closed capability vocabulary. Programmatic
  string-array filters now validate every element for bounds and control
  characters. Focused offline regressions pass; full typed domain models,
  insight matrices, and all documented CLI operations remain unchecked.
- 2026-08-15: Replaced the local insight-subject string check with
  `MetaAdsInsightSubject`, which binds the subject to the catalog operation ID
  and exact account or object-ID path shape before credentials are resolved.
  Domain matrix and fixture completion remains unchecked.
- 2026-08-15: Added the closed `ads list adaccounts` CLI operation without an
  account flag; other list operations still require an exact `act_<id>` flag.
  Full tolerant models, insight matrices, fixtures, and catalog/runtime
  invariants remain unchecked.
- 2026-08-15: Replaced nominal aliases with distinct tolerant ad-account, campaign, ad-set, ad,
  and creative response types backed by lossless unknown-field retention and tolerant provider
  statuses. Added an offline regression for unknown status and decimal-field preservation. Full
  field/insight matrices, fixture corpus, and catalog/runtime invariants remain unchecked. `mise
  run check` and address/thread sanitizer suites pass with 43 XCTest cases.
- 2026-08-15: Existing reader completion criteria remain deliberately unchecked: nominal tolerant
  records do not substitute for the accepted complete field/insight matrices, fixture corpus, or
  catalog/runtime invariants. No typed-reader scope was expanded in the journal hardening revision.
- 2026-08-15: Centralized the reviewed v26 typed-field matrix in
  `MetaAdsFieldMatrix`, derived local list capability descriptors from one
  catalog matrix, and made the typed CLI consume that list descriptor rather
  than a second hand-maintained operation mapping. Added explicit typed model
  accessors and a processed synthetic campaign fixture with focused
  `MetaAdsReaderAcceptanceTests` covering field/capability dispatch invariants
  and lossless unknown provider values. `swift test --filter
  MetaAdsReaderAcceptanceTests` passed offline. Full insight-option matrices
  and the complete multi-domain fixture corpus remain unchecked; no credential,
  network, mutation, spend, stage, commit, push, publish, or deploy occurred.

## 10. Completion Checklist

- [x] Design reference is accepted and has no unresolved high/medium finding.
- [x] Deliverables, paths, dependencies, task status, and completion criteria are
  explicit.
- [x] Every design contract maps to implementation and verification ownership.
- [x] Self-review and independent adversarial review have no unresolved
  high/medium plan finding.
- [ ] TASK-001 foundation gate is satisfied.
- [ ] TASK-002 through TASK-009 implementation and focused tests are complete.
- [ ] TASK-010 full verification and documentation are complete.
- [ ] Design status is updated with implementation evidence.

Plan acceptance means the work is ready to implement; it does not mean the
feature implementation is complete.

## 11. Risks

| Risk | Owner task | Mitigation / release gate |
|---|---|---|
| Foundation features land with different names or incomplete behavior. | TASK-001 | Map names, require behavioral tests, escalate gaps; do not duplicate core. |
| Meta v26 fields/operators drift before implementation. | TASK-002, TASK-003, TASK-006 | Re-check official docs and update the single tested matrix/fixtures before coding. |
| Typed models become brittle or lossy. | TASK-005, TASK-006 | Optional fields, tolerant enums, `additionalFields`, lossless insight values. |
| Paging URLs introduce SSRF/version/token leakage. | TASK-004, TASK-007 | Never follow/expose URLs; rebuild from fixed operation and opaque cursor. |
| Capability output diverges from dispatch. | TASK-003, TASK-008 | Generate from shared matrices/descriptors and enforce invariant tests. |
| CLI exposes raw Graph or writer behavior through typed routes. | TASK-007, TASK-009 | Closed request types, negative flags, reader catalog gating, no raw transport inputs. |
| Secrets enter fixtures, docs, or diagnostics. | TASK-009, TASK-010 | Sentinel redaction tests, Kinko-only examples, filename scan, no raw logs. |
| Verification touches live assets or spend. | TASK-010 | Fakes are acceptance gate; optional smoke requires separate authorization and test assets only. |
