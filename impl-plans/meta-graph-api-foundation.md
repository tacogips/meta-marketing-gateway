# Generic Graph API and Credential Foundation Implementation Plan

**Feature ID:** `meta-graph-foundation`

**Feature title:** Generic Graph API and credential foundation

**Issue reference:** `workflow:codex-design-and-implement-review-loop-session-732/communication:comm-002452`

**Workflow mode:** `issue-resolution`

**Status:** In progress; foundational implementation started

**Design reference:** `design-docs/meta-graph-api-foundation.md`

**Codex agent reference:** `../google-marketing-gateway`

**Progress owner:** implementation worker

## 1. Objective and boundaries

Build the accepted shared transport and Kinko credential foundation in a new
Swift 6 package. Deliver separate reader and writer clients/CLIs, an
endpoint-complete validated relative Graph surface, versioning, pagination,
batches, uploads, bounded retries, sanitized errors, documentation, and offline
tests. Do not implement broad typed Ads domains in this slice.

Do not add OAuth login/refresh, `.env` support, keychain/file credential stores,
arbitrary origins/headers, an all-capabilities binary, webhook hosting, live
campaign creation, or publishing. Do not stage, commit, push, deploy, or perform
billable verification. Expected spend is USD 0 and must remain below USD 20.

## 2. Delivery map

The exact split may be adjusted to keep Swift files focused and under 1000
lines, but module boundaries and responsibilities are fixed.

| Deliverable | Planned paths |
|---|---|
| Package/products | `Package.swift`, `Sources/MetaMarketingGatewayReader/main.swift`, `Sources/MetaMarketingGatewayWriter/main.swift` |
| Core request model | `Sources/MetaMarketingGatewayCore/GraphAPIVersion.swift`, `GraphPath.swift`, `GraphQuery.swift`, `GraphRequest.swift`, `GraphResponse.swift` |
| Credentials/security | `Sources/MetaMarketingGatewayCore/KinkoEnvironmentCredentials.swift`, `CredentialRedactor.swift`, `SecureLocalFile.swift` |
| Transport/errors/retries | `Sources/MetaMarketingGatewayCore/GraphTransport.swift`, `URLSessionGraphTransport.swift`, `GraphExecutor.swift`, `GraphError.swift`, `GraphErrorSanitizer.swift`, `RetryPolicy.swift` |
| Pagination | `Sources/MetaMarketingGatewayCore/GraphPage.swift`, `GraphPaginator.swift` |
| Batch | `Sources/MetaMarketingGatewayCore/GraphBatch.swift`, `GraphBatchExecutor.swift` |
| Upload | `Sources/MetaMarketingGatewayCore/GraphUpload.swift`, `MultipartBodyStream.swift`, `UploadSessionDriver.swift` |
| Public clients | `Sources/MetaMarketingGatewayCore/MetaGraphReader.swift`, `MetaGraphWriter.swift`, `MutationPlan.swift` |
| CLI | `Sources/MetaMarketingGatewayCore/GatewayCLI.swift`, `CLIInput.swift`, `CLIOutput.swift` |
| Tests/fixtures | `Tests/MetaMarketingGatewayCoreTests/**`, `Tests/MetaMarketingGatewayCoreTests/Fixtures/**` |
| Operator docs/tooling | `README.md`, `SECURITY.md`, `mise.toml`, `.gitignore` |

The reference repository may inform SwiftPM layout, transport injection, redirect
rejection, binary routing, and fixture structure. Do not copy its OAuth/local
profile/token-storage implementation.

## 3. Dependencies and ordering

Use Foundation and FoundationNetworking only unless implementation demonstrates
a concrete need for another package. This minimizes supply-chain and binary
surface. Tasks execute in order because later layers depend on validated models
and credential/error invariants. Tests are added with each task, not deferred.

Official Meta documentation must be rechecked before setting any version,
numeric limit, recognized retry code, or upload-host rule. Record source URL and
verification date next to the tested constant. If documentation is unavailable,
fail closed or leave the strategy unsupported rather than guessing.

## 4. Work plan

### P0 — Bootstrap and policy rails

- [ ] Create a Swift 6 package with macOS 14 minimum, one core library, separate
  reader/writer executables, and one core test target with copied fixtures.
- [ ] Add strict compiler settings consistent with concurrency-safe `Sendable`
  boundaries; add `mise` tasks for format/lint/build/test/check without secret
  hooks that inject every Kinko value.
- [ ] Add `.gitignore` rules for Swift output, local response/plan files,
  `.env*`, and common secret artifacts; do not create example secret files.
- [ ] Add `README.md` and `SECURITY.md` statements that Kinko is the only store,
  `kinko exec --env KEY[,KEY...]` is mandatory, `--all` is forbidden in project
  documentation, and credential values must never be reported.
- [ ] Add a repository scan test/script for token-shaped fixtures, `.env`, and
  forbidden production credential-source types; fixture sentinels use an
  unmistakable non-secret prefix.

Completion criteria: package resolves; both binaries print distinct help;
documentation names only allowlisted Kinko injection; secret scan passes.

### P1 — Canonical request and response models

- [ ] Implement `GraphAPIVersion` parsing with canonical `vN.N` serialization
  and rejection of empty, unversioned, signed, overflow, suffix, and whitespace
  values. Do not provide a changing "latest" default.
- [ ] Implement `GraphPath` from logical segments and CLI relative path input;
  reject absolute URLs, scheme-relative paths, authority/userinfo, fragments,
  queries, empty/dot segments, controls, backslashes, and decoded/encoded path
  separators that could change structure.
- [ ] Implement ordered `GraphQuery` with repeated keys, canonical encoding, and
  rejection of credential-reserved names case-insensitively.
- [ ] Implement `GraphBody`, bounded JSON/form/multipart/file representations,
  expected response kind, and metadata-only request summaries.
- [ ] Implement `GraphRequest` so origin and authorization headers cannot be
  caller supplied. Implement `GraphResponse` with bounded raw bytes, lazy JSON
  decoding, status, and a safe header allowlist.
- [ ] Add table-driven tests covering Unicode, percent encodings, repeated
  parameters, structured values, malformed values, every supported method, and
  reserved-auth smuggling in all carriers.

Completion criteria: request model can express arbitrary relative Graph
nodes/edges for `GET`, `POST`, and `DELETE` without accepting an origin, raw
query, raw header, or credential field.

### P2 — Kinko-only credential boundary and secure files

- [ ] Implement an internal credential value with redacted description/debug
  output and bounded, non-empty token validation.
- [ ] Implement `KinkoEnvironmentCredentials` reading only
  `META_ACCESS_TOKEN` and optional `META_APP_SECRET`; return missing variable
  names without values. Do not enumerate environment contents.
- [ ] Compute optional `appsecret_proof` in memory using a vetted platform
  primitive or narrowly scoped dependency only after security review; never
  persist inputs or output.
- [ ] Keep the production resolver concrete/internal. Add a fixture-only
  injection seam under test compilation so file/keychain/stdin resolvers cannot
  become public production alternatives.
- [ ] Implement secure local input: no symlinks, regular files only, ownership
  and unsafe write-bit checks, open-then-stat identity check, byte/depth/count
  limits, and parser-before-credential ordering.
- [ ] Implement atomic owner-only output creation, no overwrite by default, and
  cleanup/marking of partial output.
- [ ] Add unit and CLI tests proving invalid input never calls the credential
  resolver and exact sentinel secrets never appear in plan/stdout/stderr/errors.

Completion criteria: no production secret persistence API exists; all examples
use explicit `kinko exec --env`; credential resolution happens only after input
and confirmation validation.

### P3 — Transport, origin pinning, sanitization, and retries

- [ ] Define injectable `GraphTransport`, clock, sleeper, jitter, and event sink
  protocols; tests must not sleep or access the network.
- [ ] Implement `URLSessionGraphTransport` with ephemeral configuration, no
  cookies/cache, fixed connect/resource timeouts, decompression/response bounds,
  and redirect rejection.
- [ ] Build only HTTPS URLs under reviewed Meta origin enums. Normal requests
  use `graph.facebook.com`; upload origins remain unreachable until a strategy
  opts into an officially verified host.
- [ ] Inject bearer authorization and optional proof after validation. Ensure
  request descriptions and transport errors cannot render the effective URL,
  raw headers, body values, or file content.
- [ ] Decode structured Graph errors defensively. Expose only status, numeric
  code/subcode, transient flag, validated trace ID, attempt count, and local
  digest. Drop provider/user messages and unsafe headers by default.
- [ ] Implement layered redaction for exact fixture secrets, bearer tokens,
  reserved query/form keys, cookies, URL userinfo, batch bodies, redirect
  locations, and malformed responses.
- [ ] Implement bounded exponential backoff with full jitter. Retry eligible
  reads only; never automatically replay generic `POST`, `DELETE`, mixed/mutating
  batch, or final upload actions after ambiguous delivery.
- [ ] Before encoding retry codes/headers, verify official error guidance and
  annotate dated constants. Add deterministic tests for cancellation, budget
  exhaustion, 429/5xx/transient/non-transient responses, malformed hints, and
  concurrent throttling.

Completion criteria: fake-transport tests prove fixed hosts, rejected redirects,
late auth injection, safe errors, bounded retry timing, and no ambiguous generic
mutation replay.

### P4 — Reader, pagination, and generic read CLI

- [ ] Define `MetaGraphReading` and implement `MetaGraphReader.get` using the
  shared executor; expose no writer method or escape hatch to raw transport.
- [ ] Decode `data`, `summary`, and paging while preserving unknown JSON.
- [ ] Implement explicit page/item/byte/time budgets, default single-page
  behavior, cancellation, and cycle detection.
- [ ] Validate `paging.next` as HTTPS, allowed host, selected version, no
  userinfo/fragment/custom port; strip credential fields and reconstruct with
  current in-memory auth. Test hostile, cross-version, and token-bearing links.
- [ ] Implement reader CLI `graph get` with structured `--query-file` input,
  explicit `--api-version`, relative `--path`, optional pagination budgets, and
  bounded inline/owner-only file output.
- [ ] Route and validate before credentials. Prove `POST`, `DELETE`, upload, and
  mutating batch are absent/rejected by the reader binary before resolution.

Completion criteria: arbitrary validated Graph `GET` requests and bounded pages
work against fakes; cross-origin paging and every generic mutate route fail
before credential access.

### P5 — Canonical mutation plan/apply and writer client

- [ ] Define immutable canonical plan models containing method, version, relative
  path, parameter names, request-source hash, body kind/hash/size, safe file
  identity, risk labels, expiry, and schema version; exclude all values, local
  request-file paths, and secret material.
- [ ] Generate a stable digest over canonical encoded bytes. Reject unknown
  fields, expired plans, changed files, changed request inputs, digest mismatch,
  and attempts to use a plan with another method/version/path.
- [ ] Implement conservative spend, delivery, deletion, access, and unknown
  high-impact classifications. Require a second risk acknowledgement bound to
  the plan digest; do not permanently deny the generic endpoint, because the
  transport contract is endpoint-complete. Add typed guards in later features.
- [ ] Define `MetaGraphWriting` and implement confirmed `POST`/`DELETE` apply.
  Public APIs require `ConfirmedMutationPlan`, not a boolean confirmation.
- [ ] Implement writer CLI
  `graph post|delete --request-file <file> --plan-out <plan-file>` as offline
  validation and
  `--request-file <file> --apply <plan-file> --confirm <digest>` as the only
  execution route. High-impact apply also requires
  `--acknowledge-high-impact <digest>`. Plan never resolves credentials; apply
  resolves them last.
- [ ] Add negative tests for digest confusion, canonicalization collisions,
  symlink/file replacement, expired plans, missing/mismatched high-impact
  acknowledgement, risk-classification coverage, cross-client calls, and
  secret-bearing error paths.

Completion criteria: no generic writer request can execute without a matching
fresh plan digest and required risk acknowledgement; every validated endpoint
remains representable; no live mutation occurs and mock verification costs USD
0.

### P6 — Batch support

- [ ] Verify Meta's official batch format and current maximum item count; encode
  a dated provider cap plus stricter byte/file limits.
- [ ] Model names, dependencies, omission behavior, relative subrequest method,
  query, body, and attached-file references without raw URLs or auth fields.
- [ ] Validate every subrequest with the single-request validators. Detect
  duplicate/missing names, cycles, capability mixing, and aggregate limit
  violations before credentials.
- [ ] Reader accepts only read-safe subrequests. Writer canonicalizes the whole
  batch into one plan/digest and applies the same spend/delivery rules.
- [ ] Decode per-item status/safe headers/body/error while preserving order.
  Sanitize malformed and nested errors. Never auto-replay received mixed or
  mutating batches.
- [ ] Add fixtures for partial success, dependencies, omitted successes,
  attached files, malformed bodies, per-item secrets, transport failure, and
  hostile relative URLs.

Completion criteria: safe read batches and confirmed mutation batches work
against fakes; any unsafe subrequest rejects the whole request before auth.

### P7 — Multipart and resumable uploads

- [ ] Implement a streaming multipart encoder with generated collision-resistant
  boundaries, known lengths, sanitized filenames, MIME allowlist/default, and
  no whole-file buffering or debug rendering.
- [ ] Revalidate open file identity and enforce per-file/aggregate byte budgets.
  Extend canonical plans with file hash/size/identity only.
- [ ] Define `UploadStrategy` with fixed reviewed origin, start/transfer/query/
  finish builders, offset reconciliation, size rules, and completion decoder.
  Keep strategies internal/allowlisted so callers cannot invent hosts/protocols.
- [ ] Implement `UploadSessionDriver` state transitions, cancellation, safe
  progress metadata, and chunk retry only after remote offset reconciliation.
- [ ] Keep upload session identifiers and reconciled offsets in memory for
  same-process recovery; never print or persist them. Explicitly reject a local
  resume-state option. Defer cross-process resume until a separately reviewed
  Kinko write/read lifecycle is designed.
- [ ] Verify official upload documentation for each concrete strategy before
  enabling it. If no strategy is yet justified, ship multipart Graph upload and
  the tested resumable framework with concrete resumable routes unavailable.
- [ ] Add scripted tests for boundary encoding, short reads, replacement races,
  offset mismatch, interrupted chunks, finish ambiguity, expired resume state,
  malicious filenames, and redaction.

Completion criteria: bounded multipart works against fakes; resumable state
machine and safety tests pass; only officially reviewed hosts are reachable.

### P8 — Packaging, adversarial suite, and documentation closure

- [ ] Document public client examples, CLI request schemas, Kinko allowlists,
  version selection, pagination budgets, batch plans, upload constraints,
  retry semantics, output handling, and sanitized diagnostics.
- [ ] Add an explicit statement that endpoint expressibility does not grant Meta
  permissions, App Review, business verification, or resource access.
- [ ] Add `--help`/`--version`; help must distinguish reader/writer routes and
  contain placeholders only, never token flags or real Graph version claims.
- [ ] Run adversarial fixtures across all carriers: exact token/app secret,
  percent/base64-looking credentials, query auth, headers, JSON/form/multipart,
  pagination, batch, upload state, provider messages, redirect, and transport
  exceptions.
- [ ] Verify no source or docs contain `.env` loading, `kinko exec --all`, token
  command flags, non-Meta origins, unversioned requests, or production file/
  keychain credential stores.
- [ ] Run the complete verification matrix below and record results in the
  progress log. Do not use live Meta assets unless a later issue explicitly
  requires them; prefer Meta test assets and stay under USD 20 if authorized.

Completion criteria: documentation matches behavior, security scans and all
quality gates pass, no live/billable action occurred, and worktree contains no
staged changes.

## 5. Design-to-plan traceability

| Accepted design requirement | Plan coverage |
|---|---|
| Separate reader/writer APIs and binaries | P0, P4, P5 |
| Arbitrary relative versioned Graph surface with fixed origins | P1, P3 |
| Kinko-only secrets and explicit environment allowlist | P0, P2, P8 |
| Pagination validation and budgets | P4 |
| Batch validation and partial results | P6 |
| Multipart/resumable uploads | P7 |
| Safe bounded retries | P3, P6, P7 |
| Sanitized errors/logs/plans | P2, P3, P5-P8 |
| Generic writer safety and no live/billable verification | P5, P8 |
| Official Meta documentation checks | P3, P6, P7, P8 |
| Offline tests, no commit/push/publish/deploy | all phases, verification |

## 6. Verification commands

Documentation-only checks for this planning branch:

```bash
test -f design-docs/meta-graph-api-foundation.md
test -f impl-plans/meta-graph-api-foundation.md
rg -n "meta-graph-foundation|Kinko|kinko exec --env|pagination|batch|upload|retry" \
  design-docs/meta-graph-api-foundation.md impl-plans/meta-graph-api-foundation.md
test -z "$(git diff --no-index --check /dev/null design-docs/meta-graph-api-foundation.md 2>&1)"
test -z "$(git diff --no-index --check /dev/null impl-plans/meta-graph-api-foundation.md 2>&1)"
git status --short
```

Implementation verification after P8:

```bash
mise install
mise run format-check
mise run lint
mise run test
mise run build
swift test --parallel
swift run meta-marketing-gateway-reader --help
swift run meta-marketing-gateway-writer --help
rg -n "kinko exec --all|dotenv|\.env|--access-token|--app-secret" \
  README.md SECURITY.md Sources Tests
git diff --check
git status --short
```

The final scan is reviewed contextually because tests may mention forbidden
strings as negative fixtures. Verification must not execute a Graph request,
create a campaign, spend money, stage files, commit, push, publish, or deploy.

## 7. Review gates

- [x] Design self-review: feature contract, credential boundary, generic
  completeness, capability separation, safety, tests, and scope are explicit.
- [x] Independent design pass: high findings on executable plan/apply inputs and
  endpoint completeness versus permanent spend-path denial, plus mid findings
  on pagination URL trust, ambiguous retry, upload-host variation, and upload
  session credential storage, were addressed in the accepted design.
- [x] Plan self-review: every design section maps to deliverables, dependencies,
  completion criteria, progress checkboxes, and commands.
- [x] Independent plan pass: high findings on request-source binding and
  endpoint-complete high-impact handling, plus mid findings on bootstrap needs
  for an empty repo, official-limit verification, the absence of a safe Kinko
  write path for cross-process upload resume, and secret-scan interpretation,
  were addressed.
- [ ] Implementation review: required after code completion; not part of this
  planning worker.

No open high- or mid-severity design or plan finding remains.

## 8. Progress log

- 2026-08-15: Confirmed target repository is empty and inspected the referenced
  Swift gateway for reusable patterns and excluded credential behavior.
- 2026-08-15: Confirmed local Kinko CLI syntax is
  `kinko exec (--all|--env KEY[,KEY...]) -- command`; selected only `--env`.
- 2026-08-15: Checked official Meta Graph overview and linked official
  versioning, batch, pagination, error, secure-request, token, and Marketing API
  references; avoided hard-coding a "latest" version.
- 2026-08-15: Completed design self-review and independent design pass; accepted
  after addressing all high/mid findings.
- 2026-08-15: Completed plan self-review and independent plan pass; accepted
  after addressing all high/mid findings.
- 2026-08-15: Implemented P0 and a bounded first slice of P1-P5 in
  `Package.swift`, `Sources/`, tests, docs, and `mise.toml`: separate products,
  explicit version/path/query validation, fixed `graph.facebook.com` HTTPS URL
  construction, GET-only reader, Kinko environment-only resolver, validated
  paging cursor extraction, offline digest-bound writer plans, and high-impact
  acknowledgement. `mise run lint`, `mise run test`, `mise run build`, help
  smoke tests, and `git diff --check` passed. No Graph request, spend, stage,
  commit, push, publish, or deploy occurred. P3 retries, P6 batches, P7 uploads,
  durable writer journal, and final security/release gates remain unchecked.
- 2026-08-15: Self-review correction: moved request and plan input to
  descriptor-based `O_NOFOLLOW` reads with owner/mode/regular-file/byte checks;
  plan output now uses exclusive owner-only creation. Canonical plan bytes are
  rehashed at confirmation and use integral expiry seconds. Added tamper and
  symlink regression tests. `mise run lint`, `mise run test`, and `mise run
  build` passed; remaining P3-P8 criteria are still unchecked.
- 2026-08-15: Added bounded streaming `URLSession` response collection,
  read-only batch validation, and filter encoding primitives with focused tests.
  Concrete retry policy, batch transport encoding, multipart, and resumable
  upload tasks remain unchecked pending official-source revalidation.
- 2026-08-15: Added injected, read-only bounded retry execution and opaque
  cursor traversal with cancellation, page/item budgets, and cycle rejection.
  Added validated batch dependency/cycle validation, deterministic provider
  batch-form encoding, and bounded partial-result decoding. Focused fake-based
  tests pass; batch transport dispatch, official provider cap revalidation,
  multipart, and resumable upload remain unchecked. No credential or network
  access occurred.
- 2026-08-15: Extended retry receipts with full-jitter injection, bounded total
  delay, and retryable transport-error classification. Added cumulative page-byte
  budgets and a dedicated reader-only batch transport capability that posts only
  the validated provider envelope while its subrequests remain GET. Fake tests
  prove receipt accounting and capability isolation. Upload support, official
  provider-constant revalidation, concurrency throttling, and full paginator
  client/CLI integration remain unchecked.
- 2026-08-15: Corrected paginator byte arithmetic to reject negative and
  oversized externally supplied page counts before subtraction; added elapsed
  budget enforcement. Extended retry execution with injected monotonic clock,
  event sink, and optional shared throttle. Batch decoding now retains only
  safe headers and numeric provider error metadata, and rejects invented
  multi-dependency semantics. Added bounded multipart chunk construction,
  file identity revalidation, and an in-memory resumable-driver framework with
  no concrete unreviewed provider route or persisted session. Focused offline
  tests pass. Official retry/batch/upload revalidation and complete CLI/client
  integration remain unchecked.
- 2026-08-15: Replaced aggregate multipart chunk collection with a bounded
  pull stream that retains one file chunk at a time, revalidates source identity
  on each pull, and is accepted only by a dedicated upload capability with a
  validated Graph relative path. Retry now records terminal transport failures,
  and paginator deadlines are rechecked after every fetch. Focused offline
  regressions pass; provider-approved resumable routes and full upload transport
  integration remain unchecked pending official revalidation.
- 2026-08-15: Replaced buffered `URLSession.upload(for:fromFile:)` response
  handling with a file-backed request `InputStream` plus bounded
  `URLSession.bytes(for:)` receipt collection. The only enabled provider route is
  `act_<id>/adimages`; `advideos` and all resumable routes remain disabled pending
  dated official-provider revalidation. No completion criteria were checked.
- 2026-08-15: Added an offline writer send-boundary integration test through the
  shared transport protocol. A confirmed descriptor-bound mutation may send once
  only after principal, asset, and USD 0 checks; durable receipts suppress a
  repeat send and uncertain outcomes require reconciliation instead of replay.
  Production provider identity/asset verification and mutation transport wiring
  remain unchecked.
- 2026-08-15: Added deterministic `URLProtocol` multipart transport coverage
  for the only enabled `act_<id>/adimages` route. The test proves the request
  remains file-backed (`httpBodyStream`), carries only the expected bearer
  credential, and rejects a receipt exceeding the four-MiB bound. Redirect and
  authentication challenges remain deny-only transport behavior; provider
  strategy revalidation and resumable routes remain unchecked.
- 2026-08-15: Added deterministic delegate contracts proving the transport
  denies redirects and authentication challenges. Oversized receipt rejection
  now invalidates and cancels the URLSession task, with a local URLProtocol
  regression observing `stopLoading`; no upload route beyond
  `act_<id>/adimages` is enabled.
- 2026-08-15: Corrected authentication-challenge handling to preserve platform-default TLS
  server-trust validation while rejecting non-TLS credential challenges. Added deterministic
  delegate coverage for both dispositions; redirects remain disabled and no provider route was
  widened.
