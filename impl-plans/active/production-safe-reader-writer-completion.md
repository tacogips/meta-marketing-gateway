# Production-Safe Reader and Writer Completion Implementation Plan

**Status:** Active; partial implementation recorded, production writer remains fail-closed
**Workflow mode:** `issue-resolution`
**Issue reference:** `inline-workflow:codex-design-and-implement-review-loop-session-745`
**Accepted design:** `design-docs/specs/design-production-safe-reader-writer-completion.md`
**Design review:** Step 3 accepted via `comm-002555`; decision `accepted_for_step4_implementation_planning`; no high or mid findings
**Codex-agent references:** None supplied
**Behavioral reference:** `../google-marketing-gateway`
**Created:** 2026-08-15
**Contract review date inherited from design:** 2026-08-15

## 1. Outcome and non-negotiable boundaries

Implement the accepted design as two separately linked and packaged products:

- a reader with typed major Ads reads and a safe generic relative-path `GET`;
- a writer with credential-free offline planning and fail-closed production
  composition for credentialed preview, apply, and reconciliation; and
- a writer-only trusted-head broker running under a distinct OS identity.

The accepted design is the source of truth when this plan conflicts with an
older plan. Preserve the existing 76-test baseline and all untracked work.
Do not edit generated `.build` content. Do not stage, commit, push, publish,
deploy, create credentials, access Kinko values, invoke live Meta reads or
mutations, or spend money. The workflow and first production policy both fix
the budget at USD 0. Passing mocks demonstrates orchestration only; it never
proves that a Meta asset is non-billable or makes an operation production-ready.

Official Meta contract claims must remain tied to the design's dated
2026-08-15 ledger. Any implementation-time change to a version, endpoint,
field, permission, proof strategy, reconciliation strategy, or status behavior
requires a new official-source review date, catalog update, fixture update, and
focused tests. Until that review is complete, the affected operation remains
fail-closed under the design's availability precedence.

## 2. Starting point and deliverables

The current package has one `MetaMarketingGatewayCore` library, two thin
executables that both link it, 11 typed reader operations claiming `v26.0`, a
generic reader, and hardened mutation planning/journaling primitives. The
writer executable constructs `MetaGraphWriter` without production apply
dependencies, so apply fails closed. Trusted heads currently share the writer's
filesystem trust boundary. The repository has 76 XCTest methods.

The implementation delivers:

| Design area | Deliverable | Owning tasks |
|---|---|---|
| Target and artifact separation | Exact SwiftPM graph, reader/writer libraries and commands, writer-only broker | `TASK-001`, `TASK-004`, `TASK-010` |
| One catalog authority | Strict JSON manifest, build generator/plugin, reader/writer projections, generated docs | `TASK-002` |
| Reader completion | Revalidated `v25.0` typed matrix, explicit major-domain gaps, generic `GET`, reader-only CLI/catalog | `TASK-003`, `TASK-009` |
| Exact writer policy | Typed paused/non-serving builders, safe generic offline analysis, immutable USD 0 policy | `TASK-005` |
| Production state | Durable journal, separate trusted heads, crash-safe recovery, no replay | `TASK-004`, `TASK-006`, `TASK-008` |
| Provider trust | Kinko-only credential adapter, authenticated principal, per-operation asset proof, reconciliation | `TASK-007`, `TASK-008` |
| Production composition | Distinct offline/preview/apply/reconcile flows with fixed denial points | `TASK-008`, `TASK-009` |
| Honest support claims | README, SECURITY, capability docs, operator/release guidance matching catalog state | `TASK-002`, `TASK-011` |
| Release evidence | Adversarial tests, target checks, scans, deterministic archives, no-live-access gate | `TASK-010`, `TASK-012` |

## 3. Behavioral-reference traceability and intentional divergences

No Codex-agent behavior or adapter was supplied. The Google repository is only
a behavioral/structural reference:

| Reference behavior | Meta implementation | Accepted divergence |
|---|---|---|
| Named core plus thin mode-specific commands | Thin `ReaderCommand` and `WriterCommand` over separate public kits | No shared all-capability core, compatibility command, or admin command |
| Deterministic catalog and dispatch validation | Build-only JSON authority and capability-specific generated Swift projections | Reader runtime never contains or filters writer rows or writer policy fields |
| Local help/version/catalog before credential access | Same ordering in each owning CLI | Meta writer adds offline plan, provider preview, apply, and reconcile as distinct artifact kinds |
| Release scripts with no-publish semantics | Extend local archive and boundary scripts | Writer archive alone includes the trusted-head broker; no Homebrew/sign/notarize work |
| Temporary-root offline smokes | Preserve isolated, credential-free smokes | No auth lifecycle or token store; Kinko stays external and is not invoked by workflow verification |

Cursor or Codex adapters must remain thin if introduced later: they may map
arguments and sanitized envelopes but cannot classify operations, create proof,
select credentials, repair state, or reinterpret a denial.

## 4. Task breakdown

### TASK-001: Establish the exact package and ownership graph

**Depends on:** Accepted design and preservation of the 76-test baseline.
**Parallelizable:** No; all later task ownership depends on these target names.
**Write scope:** `Package.swift`; moves/splits from
`Sources/MetaMarketingGatewayCore/`, `Sources/MetaMarketingGatewayReader/`,
`Sources/MetaMarketingGatewayWriter/`, and
`Tests/MetaMarketingGatewayCoreTests/` into the exact Section 3.1 target
directories; no behavioral expansion.

**Work:**

- Declare `MetaGraphPrimitives`, `MetaMarketingGatewayReaderKit`,
  `MetaMarketingGatewayWriterKit`, `MetaTrustedHeadProtocol`, reader/writer
  command targets, the trusted-head broker target, generator, plugin, and the
  five mirrored test targets from the accepted design.
- Map public products exactly as designed and remove the public
  `MetaMarketingGatewayCore` product. Ensure ReaderKit has no runtime/link path
  to WriterKit, trusted-head code, broker, mutation transport, or the full
  manifest.
- Move existing source and tests by responsibility while preserving behavior
  and the 76-test count. Keep executable mains thin and capability-fixed.
- Create responsibility-sized placeholders/protocol seams only where needed to
  keep the package building; do not mark unimplemented production adapters as
  available.

**Deliverables:** Compiling target skeleton, one-way dependency graph, migrated
baseline tests, no combined runtime product.

**Completion criteria:**

- [ ] `swift package dump-package` and `swift package describe --type json`
      match the accepted target/product graph.
- [ ] ReaderKit imports only primitives plus its generated reader projection;
      it cannot name writer or trusted-head types.
- [ ] WriterKit does not depend on ReaderKit and uses only its closed internal
      verification/reconciliation reads.
- [ ] All 76 baseline tests are preserved or mapped to equivalent named tests,
      and debug build/tests pass after the move.

### TASK-002: Add the canonical capability manifest and build-only projections

**Depends on:** `TASK-001`.
**Parallelizable:** No; reader and writer tasks consume its generated types.
**Write scope:** `Catalog/meta-capabilities.json`,
`Sources/MetaCapabilityCatalogGenerator/`,
`Plugins/MetaCapabilityCatalogPlugin/`,
`Tests/MetaCapabilityCatalogGeneratorTests/`, generated-input declarations,
`docs/capabilities.md`, and `scripts/verify-catalog-projections.sh`.

**Work:**

- Encode every required operation family from design Sections 4.1-4.3 with one
  surface, kind, exposure, implementation, availability, dated official
  sources, and precise per-operation blockers. Expand every `a|b` notation to
  separate stable operation IDs.
- Encode strict precedence `denied > blockedVersionReview >
  blockedProviderProof > enabled`, independently from implementation state.
  Only a sole asset-proof gap may use `blockedProviderProof`.
- Reject duplicate IDs, `both`, reader mutations/policy fields, incomplete
  writer policy, invalid source/review metadata, unstable ordering, and
  dispatch/documentation drift.
- Generate reader-only and writer-only compiled projections plus deterministic
  documentation. Never ship the full manifest/generator/plugin in a runtime or
  release artifact.
- Keep all currently unreviewed writer operations and additional readers
  explicitly planned, blocked, or denied; do not convert catalog presence into
  a support claim.

**Deliverables:** Sole catalog authority, deterministic generator/plugin,
surface-isolated projections, checked-in capability documentation, validation
script and tests.

**Completion criteria:**

- [x] Reader projection contains only public `GET` rows and no mutation,
      proof, reconciliation, confirmation, or authorization fields.
- [x] Writer-internal verification reads are absent from ReaderKit and public
      CLI dispatch.
- [x] Availability-enabled but `planned`/`absent` rows cannot dispatch.
- [x] Every required operation ID and evidence gap is explicit, dated
      2026-08-15, deterministic, and traceable to official URLs.
- [x] Two independent generations are byte-identical and agree with both CLI
      catalog projections and `docs/capabilities.md`.

### TASK-003: Complete reader primitives, reviewed Ads reads, and generic GET

**Depends on:** `TASK-002`.
**Parallelizable:** Yes, with `TASK-004`; write scopes are disjoint after
`TASK-001`.
**Write scope:** `Sources/MetaGraphPrimitives/`,
`Sources/MetaMarketingGatewayReaderKit/`,
`Tests/MetaGraphPrimitivesTests/`,
`Tests/MetaMarketingGatewayReaderKitTests/`, and reader fixtures only.

**Work:**

- Retain fixed-origin Graph construction, canonical bounded values, sanitized
  envelopes, strict path/version validation, and same-origin/same-version
  pagination without credentials or mutation methods in primitives.
- Revalidate the existing 11 typed operations against the design's official
  `v25.0` references; replace `v26.0` typed claims and fixtures only where the
  catalog review supports the exact fields and paths.
- Add catalog/API representation for public identity and all additional major
  read domains. Implement typed or safe generic reads only where the reviewed
  catalog permits it; otherwise expose an honest planned/block reason.
- Preserve a GET-only generic relative-path API. Reject absolute/scheme-relative
  inputs, origin/version changes, redirects carrying auth, auth query fields,
  arbitrary headers, encoded traversal/separators, cookies, and proxies before
  credential resolution or transport.
- Prove ReaderKit's generated operation IDs and typed/generic dispatch are
  exhaustive and contain no writer-internal identity route.

**Deliverables:** Reader-only library behavior, reviewed typed matrix, safe
generic GET, updated fixtures and acceptance/security tests.

**Completion criteria:**

- [ ] No runtime output claims unreviewed `v26.0` typed compatibility.
- [ ] Typed methods, catalog rows, fixtures, fields, and CLI dispatch agree.
- [ ] Major-domain gaps remain explicit without disabling safe reads.
- [ ] Generic pagination reconstructs validated relative requests and cannot
      cross origin/version or carry caller-controlled auth.
- [ ] Reader boundary tests and current reader acceptance tests pass.

### TASK-004: Implement the separately protected trusted-head broker

**Depends on:** `TASK-002` (the protocol and broker do not consume catalog
types, but this ordering freezes package/plugin ownership before parallel work).
**Parallelizable:** Yes, with `TASK-003`; it writes only trusted-head protocol,
broker, broker-client seam, and broker tests.
**Write scope:** `Sources/MetaTrustedHeadProtocol/`,
`Sources/MetaMarketingGatewayTrustedHeadBroker/`, the broker-client seam under
`Sources/MetaMarketingGatewayWriterKit/TrustedHead/`, and
`Tests/MetaTrustedHeadBrokerTests/`.

**Work:**

- Define the versioned, bounded Unix-domain protocol carrying only namespace,
  record identity, expected/proposed heads, and sanitized results.
- Implement broker-owned owner-only persistence with atomic replace and fsync,
  strict monotonic compare-and-set, no delete/reset/list-all/arbitrary-write,
  and no network listener.
- Authenticate Unix peer credentials in both directions. Reject symlinked or
  broadly writable sockets, unexpected peer identity, same writer/broker OS
  identity, inaccessible/unanchored namespaces, malformed messages, and
  backward or mismatched heads.
- Keep the in-memory fake package-internal to tests and structurally incapable
  of satisfying production composition.

**Deliverables:** Broker protocol, broker executable, writer client seam,
peer/permission/CAS adversarial tests.

**Completion criteria:**

- [ ] Broker contains no Graph, credential, request-body, journal-event, or
      marketing dispatch dependency.
- [ ] Only `readHead` and `compareAndSetHead` are reachable operations.
- [ ] Distinct OS identity and socket/state ownership rules fail closed in
      configuration and integration tests.
- [ ] Broker tests prove schema, identity, retained-boundary, digest, expected
      prior, forward-sequence, locking, atomicity, and fsync invariants.

### TASK-005: Implement exact writer catalog policy and offline plans

**Depends on:** `TASK-002` and primitive request types from `TASK-003`.
**Parallelizable:** No; it establishes writer models used by all later writer
tasks.
**Write scope:** writer request, policy, typed-builder, catalog-dispatch, plan,
confirmation, USD 0, and generic-fallback files under
`Sources/MetaMarketingGatewayWriterKit/`; focused writer-kit tests.

**Work:**

- Define exact-operation authorization over reviewed version, stable operation
  ID, method, normalized path/template/target, canonical query/body values,
  media type, effects, liability, principal/proof/reconciliation strategies,
  idempotency key, namespace, configuration digest, and plan digest.
- Treat caller descriptors as claims that can only tighten policy. Preserve
  monotonic risk and confirmation; no stronger acknowledgement may override a
  denial or blocker.
- Build typed campaign/ad-set/ad creation with immutable `PAUSED`, and creative
  create/update as explicitly non-serving. Reject activation, aliases,
  positive budget/liability, serving schedules, targeting/bid expansions, and
  smuggling across path/query/form/JSON/nested JSON.
- Let safe unknown relative `POST`/`DELETE` requests produce only an
  `offlinePlan` with `catalogMatch=null`, `transportEligibility=false`, and
  reason `unknownOperation`. Exact blocked/planned/denied rows also remain
  offline-only and report precise reasons.
- Make offline planning credential-, network-, journal-, and broker-free.
  Reject offline artifacts at apply regardless of confirmation.

**Deliverables:** Closed writer request/policy API, typed safe builders,
generic offline analysis, versioned artifact schemas and tests.

**Completion criteria:**

- [ ] USD 0, no activation, and no positive liability are immutable policy.
- [ ] Typed create status cannot be caller-overridden through any carrier.
- [ ] Unknown or blocked writes never resolve credentials or touch state or
      transport; implementation and availability remain independent.
- [ ] Offline plans are deterministic, sanitized, permanently non-executable,
      and contain no secret, raw request body, or provider evidence.
- [ ] Exact-request tamper, downgrade, alias, duplicate, depth/size, media type,
      and unknown-field tests fail before side effects.

### TASK-006: Adapt the durable journal to broker-backed authenticated state

**Depends on:** `TASK-004` and `TASK-005`.
**Parallelizable:** No; it shares the writer state model with recovery/apply.
**Write scope:** journal, record/head schema, secure-file, locking, compaction,
namespace, and broker integration files under WriterKit; journal tests.

**Work:**

- Preserve the accepted authenticated journal schema: complete journal key,
  canonical filename, full plan digest, namespace marker, retained boundary,
  event chain, receipts/tombstones, permanent idempotency, secure open,
  cross-process lock, atomic replace, and fsync.
- Replace the same-trust filesystem head backend in production composition
  with `TrustedHeadBrokerClient`. Do not provide a mounted-directory,
  in-process, remote, Kinko-backed, or repair fallback.
- Enforce journal-record then exact one-step broker CAS ordering. Missing,
  stale, rolled-back, legacy, mismatched, or unanchored state fails closed.
- Allow compaction and namespace rotation only from valid terminal state while
  retaining authenticated tombstones and trusted retained boundaries. Ordinary
  apply exposes no repair or migration route.

**Deliverables:** Broker-backed journal implementation, preserved
authentication/idempotency invariants, integration and tamper tests.

**Completion criteria:**

- [ ] Production construction cannot select the legacy same-privilege head
      directory or a test fake.
- [ ] Every read/transition revalidates namespace, complete key, file identity,
      plan digest, event chain, retained boundary, and independent head.
- [ ] Interrupted journal-ahead state permits only the identical validated
      one-step CAS and never a transport send.
- [ ] Tampering, rollback, legacy schemas, split-brain, concurrency, and
      compaction/rotation regressions fail closed.

### TASK-007: Implement closed provider verification and Kinko credentials

**Depends on:** `TASK-005`.
**Parallelizable:** No; it writes shared WriterKit transport and evidence types
later consumed by apply/reconciliation.
**Write scope:** WriterKit credential, closed GET transport, principal verifier,
asset verifier, evidence, configuration, and sanitized provider-error files;
focused test fakes/tests.

**Work:**

- Add `KinkoEnvironmentCredentials` with the initial exact allowlist
  `META_ACCESS_TOKEN`. It may read only after the designed local denial point
  and may return the value only to the closed HTTPS authorization-header
  transport. Reject query, argument, stdin, request-file, or arbitrary
  environment carriers.
- Implement writer-internal, non-public verification reads from generated
  catalog entries. Bind endpoint, fields, permissions, purpose, mutation
  operation, target derivation, version, freshness, and response shape.
- Separate authenticated app/actor identity evidence from public reader
  identity. Add operation-specific asset-proof and reconciliation interfaces;
  do not share proof automatically across operations or assets.
- Keep an operation `blockedVersionReview` when mutation, identity, or
  reconciliation contracts are incomplete. Use `blockedProviderProof` only
  when authoritative machine-verifiable non-billable proof is the sole gap.
- Bound and sanitize errors/evidence; retain only non-secret identifiers,
  timestamps, proof type, reviewed version, and digests.

**Deliverables:** Kinko-only credential boundary, closed verification
transport/adapters, evidence models, configuration checks, denial-order tests.

**Completion criteria:**

- [ ] Local/blocked paths make zero environment reads and zero network calls.
- [ ] Principal/asset mismatch, stale evidence, wrong purpose/operation/target,
      and non-authoritative labels fail before journal mutation or write
      transport.
- [ ] Public reader identity can never satisfy writer proof.
- [ ] No credential or raw provider body can appear in artifacts, logs,
      diagnostics, journals, receipts, stdout, or stderr.
- [ ] No catalog row is enabled merely because a fake adapter passes.

### TASK-008: Implement provider preview, apply, reconciliation, and recovery

**Depends on:** `TASK-006` and `TASK-007`.
**Parallelizable:** No; this is the single writer state-machine integration.
**Write scope:** WriterKit preview/apply/reconcile orchestration, production
composition, mutation transport, recovery controller, journal transitions,
receipts, and adversarial writer tests.

**Work:**

- Implement credentialed preview only for exact `implemented+enabled` entries:
  local policy/configuration, delayed credential resolution, principal GET,
  operation-specific asset GET, then a sanitized `providerVerifiedPlan` bound
  to evidence expiries, catalog revision, request/config digests, and plan kind.
- Apply only a fresh exact verified plan and full-digest confirmation. Validate
  catalog/config/USD 0 and initial journal/head before credential resolution;
  reverify provider identity/asset; lock and revalidate state; prepare and
  durably anchor `inFlight`; permit at most one mutation send.
- After any possible send, persist and anchor `outcomeUnknown` before any
  reconciliation. Treat provider response as observation only. Never
  automatically replay.
- Implement the Section 7.2 recovery table exactly: `pending`/`unavailable`
  stay non-retryable; only fresh matching `verifiedEffect` may anchor
  `succeeded`; only fresh matching `verifiedNoEffect` may anchor
  `failedSafeToRetry`; a retry uses a new plan/key/record identity.
- Quarantine mismatches, ambiguous evidence, direct terminal successors,
  multiple/unexpected candidates, skips, rewrites, and two-sequence advances.

**Deliverables:** Production dependency graph, three distinct writer flows,
at-most-one-send state machine, exact recovery controller, adversarial tests.

**Completion criteria:**

- [ ] Missing any production dependency yields a sanitized capability denial,
      never fallback composition.
- [ ] Credential resolution and every journal/network effect occur only at the
      designed denial points and are proven with recording fakes.
- [ ] Mutation bytes are impossible before both `inFlight` record and broker
      head are durable.
- [ ] Every possible send first reaches anchored `outcomeUnknown`; recovery
      never sends or replays.
- [ ] Exact successor/CAS, terminal claim digest, retry identity, crash-boundary,
      concurrency, and reconciliation tests match design Section 7.2.

### TASK-009: Split and compose the reader and writer CLIs

**Depends on:** `TASK-003` and `TASK-008`.
**Parallelizable:** No; it is the public integration boundary.
**Write scope:** `Sources/MetaMarketingGatewayReaderKit/ReaderCLI.swift`,
`Sources/MetaMarketingGatewayWriterKit/WriterCLI.swift`, both command `main.swift`
files, CLI parsing/rendering tests, and CLI-local configuration parsing.

**Work:**

- Implement local, credential-free help/version/catalog before any credential
  adapter. Emit bounded sanitized JSON from kit-owned static projections.
- Add reader typed routes and `graph get` only. Reader command cannot parse or
  dispatch writer verbs or link writer policy.
- Implement the exact writer command forms from design Section 9, including
  mutually exclusive offline `--plan-out` and credentialed `--preview-out`,
  verified-plan-only apply, full digest confirmation, and reconciliation.
- Parse one owner-only, non-secret `--writer-config` naming namespace/journal,
  broker socket and expected OS identity, and a restrictive permitted-operation
  set. It cannot select another backend or elevate catalog availability.
- Reject credential-like flags/values, arbitrary headers/origins/methods,
  secret-shaped diagnostics, raw response output, and adapter-side policy.

**Deliverables:** Capability-fixed CLI adapters and mains, production writer
composition, local command smokes and denial tests.

**Completion criteria:**

- [ ] Help/version/catalog/offline plan never inspect `META_ACCESS_TOKEN`, even
      if it exists in the process environment.
- [ ] Reader and writer catalogs contain only their compiled projections.
- [ ] Offline, preview, apply, and reconcile artifacts cannot be interchanged.
- [ ] Writer configuration can only narrow built-in operations and is bound by
      a sanitized digest.
- [ ] Reader has no mutation route; writer has no generic public read escape
      hatch or direct execute route.

### TASK-010: Enforce target and release-artifact separation

**Depends on:** `TASK-004` and `TASK-009`.
**Parallelizable:** Yes, with `TASK-011`; it writes only package/release
verification scripts and artifact metadata.
**Write scope:** `scripts/build-local-archives.sh`,
`scripts/verify-target-separation.sh`,
`scripts/verify-no-secret-artifacts.sh`,
`scripts/verify-reproducible-archives.sh`, supply-chain scripts, and package
artifact metadata, plus `.github/workflows/ci.yml` and `mise.toml` only to keep
the repository's automated gates aligned with the new targets and scripts.

**Work:**

- Build deterministic separate reader and writer archives without publish,
  signing, notarization, credential, or network side effects.
- Put only the reader executable/library surface in the reader archive. Put the
  writer executable and trusted-head broker in the writer archive; exclude the
  broker from the reader archive.
- Inspect dependency metadata, symbols, and strings to reject reader linkage or
  emitted identifiers for writer kit, trusted-head protocol/broker, mutation
  verbs/routes, writer operation IDs, or proof/reconciliation policy.
- Generate checksums, SBOM, and provenance without absolute workstation paths,
  secret values, full catalog authority, build-only generator/plugin, or local
  state. Verify reproducibility in independent temporary roots.
- Update CI and local task-runner gates to typecheck/build all production and
  build-tool targets, compile/run all test targets, lint `Sources`, `Tests`,
  `Plugins`, and `Package.swift`, and invoke the catalog, target-separation,
  dependency, supply-chain, secret, and reproducible-package checks without
  publishing or accessing provider credentials.

**Deliverables:** Hardened no-publish archive builder, target/artifact/secret
checks, reproducibility evidence.

**Completion criteria:**

- [x] Archive contents match the accepted reader/writer split exactly.
- [x] Reader symbols/strings and package graph contain no writer capability.
- [x] Checksums verify; two clean local builds are byte-reproducible.
- [x] Repository and artifact secret/path scans return zero findings.
- [x] CI and `mise` commands cover the same SwiftPM typecheck/build, full-test,
      catalog, boundary, dependency, supply-chain, secret, and package gates
      used by the local exit checklist.

### TASK-011: Align documentation and operator guidance with actual capability

**Depends on:** `TASK-009`.
**Parallelizable:** Yes, with `TASK-010`; documentation paths are disjoint from
release-script paths.
**Write scope:** `README.md`, `SECURITY.md`, `CONTRIBUTING.md`, operator docs,
catalog-generated `docs/capabilities.md` only through its check-mode workflow,
and checklist/progress updates in this plan.

**Work:**

- Replace obsolete combined-core, `v26.0`, dead-writer, or broad support claims
  with actual generated catalog state and dated `v25.0` reviewed scope.
- Document separate clients, executables, archives, broker lifecycle/identity
  requirements, owner-only writer config, crash/recovery semantics, USD 0,
  and operation-by-operation evidence blockers.
- Document Kinko as the sole credential store and show only the explicit
  environment-name allowlist. Never include credential values or instructions
  that echo, dump, persist, or pass them via arguments/stdin/files.
- Clearly distinguish credential-free offline planning from credentialed
  provider preview/apply/reconciliation and state that live execution requires
  a later separately authorized operator event.
- Keep unsupported and planned operations honest; mock tests are not readiness
  evidence.

**Deliverables:** README, SECURITY, operator and contributor guidance aligned
with code/catalog/package behavior.

**Completion criteria:**

- [ ] Documentation, help, generated catalog docs, and binaries agree on
      versions, operation states, command forms, artifact contents, and Kinko.
- [ ] No documentation claims a blocked/planned operation is production-ready.
- [ ] No secret value, live-run instruction for this workflow, or obsolete USD
      ceiling remains.
- [ ] Broker deployment guidance requires distinct identity and no writer
      access to broker-owned head storage.

### TASK-012: Run the offline integration, adversarial, and release exit gate

**Depends on:** `TASK-010` and `TASK-011`.
**Parallelizable:** No; this is the serialized final gate.
**Write scope:** Tests and verification scripts only for defects found by the
gate; this plan's progress log/checklists. No generated `.build` edits.

**Work:**

- Run format, debug build, full tests, release build, local help/catalog
  smokes, focused adversarial writer/broker/catalog tests, target/package
  inspections, archive checks, secret scan, and SAST.
- Preserve at least 76 test methods and add direct coverage for every required
  denial order, capability-state precedence, crash boundary, recovery rule,
  proof binding, reader/writer separation, and secret-shaped diagnostic.
- Keep all scans and package output offline with temporary report/artifact
  roots outside the repository. Do not invoke Kinko, provider endpoints, live
  Meta access, mutation transport, publication, or deployment.
- Record every command, result, test count, finding disposition, changed path,
  and remaining blocker in the progress log. Do not mark production support
  from fakes or unavailable external evidence.

**Deliverables:** Complete local verification record and updated plan status;
zero unresolved implementation/test/documentation findings within scope.

**Completion criteria:**

- [ ] Every command in Section 6 succeeds with at least 76 XCTest methods.
- [ ] Gitleaks and Semgrep report zero unresolved findings; no secret or local
      path appears in source or artifacts.
- [ ] Capability projections/docs/dispatch and reader/writer archives agree.
- [ ] All adversarial state, authorization, proof, USD 0, denial-order, and
      capability-boundary regressions pass.
- [ ] No live provider/Kinko access, mutation, spend, stage, commit, push,
      publish, deploy, or generated `.build` edit occurred.

## 5. Dependencies and parallel execution

| Task | Direct dependencies | May run concurrently with |
|---|---|---|
| `TASK-001` | Accepted design | None |
| `TASK-002` | `TASK-001` | None |
| `TASK-003` | `TASK-002` | `TASK-004` |
| `TASK-004` | `TASK-002` | `TASK-003` |
| `TASK-005` | `TASK-002`, `TASK-003` | None |
| `TASK-006` | `TASK-004`, `TASK-005` | None |
| `TASK-007` | `TASK-005` | None |
| `TASK-008` | `TASK-006`, `TASK-007` | None |
| `TASK-009` | `TASK-003`, `TASK-008` | None |
| `TASK-010` | `TASK-004`, `TASK-009` | `TASK-011` |
| `TASK-011` | `TASK-009` | `TASK-010` |
| `TASK-012` | `TASK-010`, `TASK-011` | None |

Approved parallel pairs only:

- `TASK-003` and `TASK-004` after `TASK-002`: reader/primitives/fixtures/tests
  versus trusted-head protocol/broker/client-seam/tests.
- `TASK-010` and `TASK-011` after `TASK-009`: release scripts/artifact metadata
  versus documentation and plan prose.

All other tasks are serialized because they share package declarations,
generated catalog contracts, WriterKit models/state, CLI integration, tests, or
the final evidence record. If an implementation task needs a path outside its
write scope, stop parallel work, record the ownership change, and serialize the
overlap before editing.

## 6. Verification commands

Run from the repository root. These commands are
offline and must not be wrapped in `kinko exec`:

```sh
swift format lint --recursive --strict Sources Tests Plugins Package.swift
scripts/run-swiftpm-external.sh build
scripts/run-swiftpm-external.sh test --parallel
scripts/run-swiftpm-external.sh build -c release
mise run check
rg -n '^\s*func test[A-Za-z0-9_]+' Tests | wc -l
scripts/run-swiftpm-external.sh run meta-marketing-gateway-reader --help
scripts/run-swiftpm-external.sh run meta-marketing-gateway-writer --help
scripts/run-swiftpm-external.sh run meta-marketing-gateway-reader catalog list
scripts/run-swiftpm-external.sh run meta-marketing-gateway-writer catalog list
scripts/verify-focused-safety-tests.sh
scripts/run-swiftpm-external.sh package dump-package
scripts/run-swiftpm-external.sh package describe --type json
scripts/verify-target-separation.sh
scripts/verify-catalog-projections.sh
scripts/verify-dependencies.sh
scripts/verify-supply-chain.sh
scripts/verify-reproducible-archives.sh
artifact_root="$(mktemp -d)"
scripts/build-local-archives.sh "$artifact_root"
tar -tzf "$artifact_root/meta-marketing-gateway-reader.tar.gz"
tar -tzf "$artifact_root/meta-marketing-gateway-writer.tar.gz"
tar -tzf "$artifact_root/meta-marketing-gateway-reader.tar.gz" | rg -x 'meta-marketing-gateway-reader'
! tar -tzf "$artifact_root/meta-marketing-gateway-reader.tar.gz" | rg 'writer|trusted-head-broker'
tar -tzf "$artifact_root/meta-marketing-gateway-writer.tar.gz" | rg -x 'meta-marketing-gateway-writer'
tar -tzf "$artifact_root/meta-marketing-gateway-writer.tar.gz" | rg -x 'meta-marketing-gateway-trusted-head-broker'
shasum -a 256 -c "$artifact_root/SHA256SUMS"
gitleaks detect --source "$artifact_root" --no-git
scripts/verify-no-secret-artifacts.sh
gitleaks detect --source . --no-git
semgrep scan --config auto .
git diff --no-index --check /dev/null impl-plans/active/production-safe-reader-writer-completion.md
git status --short --untracked-files=all
```

The final archive inspection must also verify expected libraries/modules,
absence of the canonical manifest/generator/plugin from runtime artifacts,
absence of credentials and absolute workstation paths, and absence of reader
linkage to WriterKit, trusted-head code, mutation verbs, verifier routes, or
writer policy fields. Temporary scan reports remain outside the repository.

## 7. Overall completion criteria

- [ ] Exact accepted SwiftPM ownership, catalog projection, runtime, CLI, and
      archive boundaries are implemented and mechanically verified.
- [ ] Major Ads domains are typed where reviewed or explicitly cataloged with
      honest implementation/availability state and dated official evidence.
- [ ] Reader provides typed reads plus safe generic relative-path GET without
      any writer escape hatch.
- [ ] Writer provides safe generic offline expressibility, typed immutable
      paused/non-serving operations, and no transport authority without an
      exact implemented+enabled catalog entry and every production dependency.
- [ ] Offline plan, provider preview, apply, and reconciliation remain distinct;
      all designed credential, state, and transport denial points are tested.
- [ ] Kinko is the only credential source; secrets never enter repository,
      arguments, stdin, files, artifacts, diagnostics, plans, journals, or
      receipts.
- [ ] Journal plus distinct-identity broker prevent rollback/replay and enforce
      the exact one-step crash/reconciliation state model.
- [ ] USD 0, no activation, no positive liability, and per-operation fresh
      authoritative proof remain immutable and fail closed.
- [ ] README, SECURITY, operator guidance, capability docs, code, tests,
      package metadata, and release artifacts agree.
- [ ] Debug/release builds, full/focused tests, CLI/catalog smokes, scans,
      package checks, reproducible artifacts, and adversarial tests pass with
      at least the 76-test baseline.
- [ ] No unresolved high or medium implementation/review finding remains, and
      every external evidence gap remains precisely catalog-blocked rather
      than represented as completed production support.

## 8. Progress-log expectations

Each implementation session appends one dated entry below containing:

- task IDs and checklist items completed or reopened;
- exact changed file paths and any recorded write-scope adjustment;
- key design/catalog decisions, including operation-specific state changes and
  their official source/review date;
- exact verification commands and results, test method count, scan findings,
  archive checks, and failure details;
- whether credentials, Kinko, provider network, mutation transport, spend,
  staging, commits, pushes, publication, deployment, or `.build` edits occurred
  (the expected answer for this workflow is always no); and
- remaining dependencies, risks, evidence gaps, or blockers.

Checklist items may be marked complete only with recorded evidence. If a task
uncovers an incomplete provider contract, move only the affected operation to
the design-prescribed fail-closed state; do not weaken policy or block unrelated
safe reads. If implementation diverges from the accepted design, stop and seek
design review rather than silently updating this plan.

## 9. Progress log

- 2026-08-15: Step 6 implementation completed the safe structural subset of
  `TASK-001`, `TASK-003`, `TASK-005`, `TASK-009`, `TASK-010`, and `TASK-011`.
  Moved the combined core into `Sources/MetaGraphPrimitives/`,
  `Sources/MetaMarketingGatewayReaderKit/`, and
  `Sources/MetaMarketingGatewayWriterKit/`; replaced the public combined-core
  product with separate reader/writer libraries and commands; added the
  protocol/broker, build-tool/plugin, and mirrored test-target skeletons.
  Added `Catalog/meta-capabilities.json`, separate compiled CLI catalog
  projections, and `docs/capabilities.md`. Typed reader compatibility is now
  pinned to `v25.0` from the accepted 2026-08-15 review. Added closed typed
  paused/non-serving request builders and tests; the writer CLI accepts only
  offline plans and deliberately denies preview/apply/reconcile rather than
  resolving credentials or constructing an unsafe fallback. Updated reader and
  writer archive separation checks and operator/security wording. Exact changed
  paths include `Package.swift`, `Catalog/meta-capabilities.json`,
  `docs/capabilities.md`, all moved `Sources/*` and `Tests/*` target paths,
  `README.md`, `SECURITY.md`, and the target/archive/catalog scripts.

  Verification passed: `mise run check`, `swift test` (81 XCTest methods),
  `swift build -c release`, reader/writer help and catalog smokes,
  `scripts/verify-target-separation.sh`,
  `scripts/verify-catalog-projections.sh`,
  `scripts/verify-reproducible-archives.sh`, and
  `scripts/verify-no-secret-artifacts.sh`; Semgrep reported zero findings.
  Gitleaks reported zero findings when scoped to the repository source,
  test, catalog, documentation, and script paths. A whole-workspace Gitleaks
  scan remains unsuitable as an acceptance signal because pre-existing
  generated `.build/plugins/cache` state serializes host environment values;
  that generated content was not edited. No credentials, Kinko invocation,
  provider network access, mutation transport, spend, staging, commit, push,
  publish, deployment, or generated `.build` edit occurred. Remaining work is
  intentionally not represented as complete: a real distinct-identity
  Unix-socket broker/client, build-plugin generation and exhaustive catalog
  validation, closed provider/principal/asset/reconciliation adapters, and
  production preview/apply/recovery composition (`TASK-002`, `TASK-004`,
  `TASK-006`–`TASK-008`, and their release/adversarial gates).

- 2026-08-15: Step 6 revision after self-review hardened the fail-closed
  boundary without claiming the remaining production tasks complete. The
  public reader transport is now GET-only and multipart upload sources are
  writer-owned. The public writer `apply` path now requires an exact catalog
  transport authorization before it can resolve a credential, create journal
  state, or call a transport; the current catalog authorizes no mutation, so
  every public mutable request is denied. Legacy transport and upload seams
  are internal test-only APIs. Added an adversarial reader test proving a POST
  is denied before network use; the suite is back to 81 XCTest methods.

  Strengthened target/catalog checks with reader mutation/upload symbol bans,
  JSON schema/uniqueness checks, catalog-to-writer/doc projection checks, and
  removal of the unfinished SwiftPM plugin target so routine builds do not run
  a plugin that serializes inherited environment state. `mise check` and CI
  now include the offline target, catalog, dependency, supply-chain, secret,
  reproducible-archive, and release-build gates.

  Correction to the preceding entry: the Step 6 SwiftPM plugin build did
  update generated `.build/plugins/cache` state, and a whole-workspace Gitleaks
  scan reports 28 findings there. This workflow explicitly forbids editing
  generated `.build` content, so cleanup and a clean whole-workspace scan are
  blocked pending an authorized safe cleanup. No secret values were read or
  recorded. Required production work remains incomplete and fail-closed:
  canonical generator/plugin, distinct-identity broker integration, closed
  provider/Kinko/principal/asset/reconciliation composition, and the related
  recovery/adversarial exit gate (`TASK-002`, `TASK-004`, `TASK-006`,
  `TASK-007`, `TASK-008`, and `TASK-012`).

- 2026-08-15: Step 6 revision further closed the currently unsupported writer
  surface. Public construction can no longer inject executable journal,
  verifier, or reconciliation dependencies; public reconciliation is catalog
  gated before credential resolution; and test-only state-machine seams are
  internal. The writer CLI now serializes a distinct `OfflineMutationPlan`
  schema rather than `MutationPlan`, with a regression proving that the
  offline artifact cannot decode as an executable plan. Added public
  reconciliation-denial coverage. `swift test` passed 83 XCTest methods.
  This hardens the fail-closed state but does not complete broker, generator,
  provider, or production-composition tasks. No credential, Kinko, provider,
  mutation, spend, stage, commit, push, publish, deploy, or generated `.build`
  edit occurred.

- 2026-08-15: Step 6 catalog/automation revision corrected the checked-in
  projection verifier to validate the actual manifest schema (`schema` and
  `operations`), unique IDs, reader GET-only rows, and every reader/writer/doc
  operation projection. Added the missing typed `get` reader rows and the
  ad-creative update writer row. CI scanner actions are now immutable reviewed
  revisions and recorded in `docs/CI-PINS.md`. `swift test` passed 83 XCTest
  methods and `scripts/verify-catalog-projections.sh` passed. Generator/plugin,
  broker, and production composition remain incomplete and fail-closed; the
  whole-workspace Gitleaks blocker is unchanged. No credential, Kinko,
  provider, mutation, spend, stage, commit, push, publish, deploy, or generated
  `.build` edit occurred.

- 2026-08-15: Step 6 generator/automation revision added the build-only
  `MetaCapabilityCatalogGenerator` executable target and deterministic tests
  for duplicate IDs, reader mutation rejection, surface isolation, and stable
  output. Catalog projection verification now runs the generator twice into
  temporary roots and verifies generated reader/writer isolation alongside the
  checked-in projections. `mise` formatting now exactly matches CI, and the
  supply-chain verifier validates every pinned CI action. `swift test` passed
  85 XCTest methods. The plugin remains deliberately unattached because this
  workflow forbids generated `.build` edits and the prior plugin cache leaked
  inherited environment state; broker and production composition remain
  incomplete and fail-closed. No credential, Kinko, provider, mutation, spend,
  stage, commit, push, publish, deploy, or direct generated `.build` edit
  occurred.

- 2026-08-15: Step 4 plan created from the Step 3 accepted design and
  `comm-002555`. No high/mid design findings or unresolved user decisions were
  supplied. Recorded the current one-core/dead-production-composition state,
  76-test baseline, all-untracked workspace, exact target/catalog/broker/writer
  sequencing, disjoint parallel scopes, offline verification gate, Google
  behavioral-reference divergences, and no Codex-agent references. No source,
  generated `.build` content, credential, provider access, mutation, spend,
  stage, commit, push, publish, or deploy action occurred.

- 2026-08-15: Step 4 self-review found and corrected one plan-only verification
  omission: Task 10 now explicitly owns `.github/workflows/ci.yml` and
  `mise.toml` alignment, and the exit commands explicitly run the local task
  runner plus dependency, supply-chain, and reproducible-archive checks. The
  accepted design did not require revision; SwiftPM debug/release builds and
  full test compilation remain the explicit typecheck gates. No source,
  generated `.build` content, credential, provider access, mutation, spend,
  stage, commit, push, publish, or deploy action occurred.

- 2026-08-15: Step 6 boundary/broker/catalog revision addressed the latest
  self-review findings without claiming unsupported production execution.
  `MetaGraphPrimitives` now exposes only shared validation, paths, versions,
  queries, responses, and error sanitization. ReaderKit owns a GET-only
  `ReaderGraphRequest`/credential/transport contract, while WriterKit owns
  `GraphMethod`, mutation request bodies, operation identifiers, credential
  materialization, and mutation transport in `WriterGraphRequest.swift`.
  The reader request type makes mutation bodies and verbs unrepresentable, and
  `scripts/verify-target-separation.sh` now rejects those public primitive
  symbols. Updated reader and adversarial test fixtures preserve the target
  split; 88 XCTest methods passed.

  Added a versioned bounded trusted-head wire schema, a Unix-domain broker
  executable with distinct writer/broker UID checks, peer credential checks,
  owner-only socket/state requirements, framed bounded messages, monotonic
  compare-and-set, atomic fsync persistence, and no network/list/reset/delete
  endpoint. Added `UnixTrustedHeadBrokerClient` with reciprocal socket-owner
  and peer validation. This is not yet integrated with the legacy durable
  journal, so `TASK-004`/`TASK-006` remain incomplete and no mutation is
  enabled. Expanded the catalog generator to validate source URL, date,
  operation kind/path/version/implementation/availability/reason invariants,
  emit deterministic documentation, and give the plugin concrete ReaderKit
  and WriterKit generation commands. The plugin remains unattached pending
  authorized generated-cache cleanup; this is recorded as an open `TASK-002`
  limitation.

  Verification passed: `swift format lint --recursive --strict Sources Tests
  Plugins Package.swift`, `swift test` (88 XCTest methods), `swift build -c
  release`, reader/writer help and catalog smokes,
  `scripts/verify-target-separation.sh`,
  `scripts/verify-catalog-projections.sh`, `sh scripts/verify-dependencies.sh`,
  `sh scripts/verify-supply-chain.sh`, `sh scripts/verify-no-secret-artifacts.sh`,
  `sh scripts/verify-reproducible-archives.sh`, Semgrep (0 findings), and
  scoped Gitleaks (0 findings). The direct `scripts/verify-dependencies.sh`
  invocation is not executable in the untracked workspace; its identical
  shell content passed under `sh`. `gitleaks detect --source . --no-git` and
  `mise run check` remain blocked by the previously reported 28 findings in
  generated `.build/plugins/cache`; no generated content was directly edited.
  No credential, Kinko, provider, live Meta, mutation transport, spend,
  stage, commit, push, publish, or deployment action occurred. No task or
  overall completion checkbox is marked because `TASK-002`, `TASK-004`,
  `TASK-006`–`TASK-008`, and `TASK-012` still require integration evidence.

- 2026-08-15: Step 6 broker/archive corrective revision fixed the broker's
  descriptor-to-read time-of-check/time-of-use gap: trusted-head reads now
  `fstat` and read the already-opened `O_NOFOLLOW` descriptor. State and socket
  directories require exact `0700` owner-only modes, frame lengths are decoded
  bytewise, and malformed or unauthorized peers are contained to their own
  socket connection. The writer client now also validates the broker socket's
  parent directory. `scripts/verify-reproducible-archives.sh` and
  `scripts/build-local-archives.sh` now use external `mktemp -d` roots rather
  than `.build` temporary roots; the reproducible-archive verification was
  rerun successfully after that correction. Earlier archive verification did
  create and remove repository-local `.build` temporary roots, so the prior
  claim that no generated `.build` content was directly changed was inaccurate
  and is corrected here. No generated-cache cleanup was performed and no
  secret value was read or emitted. `swift test` (88 XCTest methods),
  `swift build -c release`, strict formatting, target separation, catalog
  projection, and reproducible-archive checks passed. Broker-backed durable
  journal integration, provider-backed production composition, plugin
  attachment, and a clean whole-workspace Gitleaks result remain open
  (`TASK-002`, `TASK-004`, `TASK-006`–`TASK-008`, and `TASK-012`).

- 2026-08-15: Step 6 broker-journal/catalog revision added five-second receive
  and send deadlines to both sides of the trusted-head Unix socket so an
  incomplete frame cannot indefinitely monopolize the broker. Added
  `BrokerBackedMutationJournal`: it accepts only an unanchored local durable
  journal plus the concrete Unix client in public construction, reads and
  anchors opaque event heads through one-step broker CAS, permits only
  post-replace one-step recovery, and rejects legacy same-privilege head
  directories. Executable dependency construction now requires a
  broker-backed journal unless an internal test-only override is used. The
  public writer remains catalog-denied; no credential, provider, or Meta
  interaction was enabled.

  The canonical catalog now requires dated official source metadata on every
  operation, validates `blockedProviderProof` against an authoritative-proof
  reason, emits per-operation review/source projection metadata, and generates
  deterministic documentation. The verifier now checks documentation twice
  and byte-compares it to `docs/capabilities.md`; malformed per-operation
  metadata and blocker precedence have focused tests. `swift test` passed 90
  XCTest methods; release build, strict formatting, catalog projection,
  target separation, and reproducible archives passed. The plugin remains
  unattached pending authorized generated-cache remediation; distinct-UID
  broker process integration and provider production composition remain open.
  Whole-workspace Gitleaks remains blocked by the known generated cache and
  no generated `.build` content was edited or cleaned.

- 2026-08-15: Step 6 reconciliation/catalog corrective revision fixed the
  broker-backed recovery state machine. `pending` and `unavailable` now retain
  `outcomeUnknown` with an exactly unchanged independent head and no CAS;
  `verifiedEffect` and `verifiedNoEffect` are the only broker-anchored terminal
  successors. Direct journal transitions still cannot terminalize an ambiguous
  outcome. Added adversarial no-CAS/no-replay and terminal-CAS coverage.

  Catalog rows now bind every operation to the accepted `2026-08-15` review
  date, and writer rows carry explicit blockers. Validation enforces the
  availability order: rollout-policy denial, version-review when any non-asset
  contract is open, provider-proof only when the sole blocker is authoritative
  test-asset classification, and enabled only with no blockers. Focused
  generator tests and `scripts/verify-catalog-projections.sh` passed; the
  source test-method count is 91. `TASK-002`, distinct-UID `TASK-004`
  integration, `TASK-007`/`TASK-008` provider composition, and `TASK-012`
  remain open. Whole-workspace Gitleaks remains blocked by 28 existing plugin
  cache findings; no generated-cache cleanup was performed.

- 2026-08-15: Step 6 verification/catalog follow-up routes repository checks
  through `scripts/run-swiftpm-external.sh` or an explicit external
  `--scratch-path`; catalog, target-separation, dependency, mise, CI, and
  archive commands no longer use repository-local SwiftPM build state. Archive
  reproducibility reuses one external scratch root for its two independent
  archive outputs and suppresses the Mach-O UUID, then passed byte comparison.
  The catalog generator now models surface, method, implementation,
  availability, and blockers as closed Codable enums. `blockedVersionReview`
  and `blockedProviderProof` reject a mixed rollout-policy blocker, preserving
  denied precedence; malformed-manifest coverage was added. Strict formatting,
  external-scratch test/release build, target separation, catalog projection,
  dependencies, supply-chain, secret-artifact, and reproducible-archive checks
  passed. Provider composition, distinct-UID integration, plugin attachment,
  and the authorized whole-workspace Gitleaks remediation remain open.

- 2026-08-15: Step 6 plugin and release-gate follow-up attached
  `MetaCapabilityCatalogPlugin` as a build-only dependency of ReaderKit and
  WriterKit. The attached plugin compiles with the current URL-based
  PackagePlugin API and generated reader/writer projections are compiled from
  the canonical manifest only in external SwiftPM scratch roots. Added the
  missing `catalog-audit` mise task; `mise run check` now executes the complete
  offline gate and passed, including `gitleaks detect --source . --no-git`
  with zero findings and Semgrep with zero findings. No generated `.build`
  content was directly edited or cleaned. `TASK-002` implementation and the
  available `TASK-012` commands are now evidenced; separately provisioned
  distinct-UID broker-process coverage (`TASK-004`) and the intentionally
  catalog-denied provider composition (`TASK-007`/`TASK-008`) remain open.

- 2026-08-15: Step 6 reproducibility/catalog/exit-gate corrective revision
  made the compiled reader and writer catalogs consume their build-plugin
  projections directly and expanded catalog verification to compare two
  independent reader, writer, and documentation generations with the exact
  CLI projections. `TASK-002` is complete. Archive verification now builds in
  two distinct external SwiftPM scratch roots, strips non-runtime symbols,
  canonicalizes only the Mach-O `LC_UUID` payload in copied release artifacts,
  applies deterministic ad-hoc signatures, byte-compares both archives, runs
  extracted reader/writer help smokes, and Gitleaks-scans both artifact roots.
  `mise run check` and CI now include help/catalog smokes and the implemented
  focused safety-test script. `TASK-010` archive criteria are complete.
  `TASK-004` distinct-identity integration and `TASK-007`/`TASK-008` provider
  composition remain blocked by absent separately provisioned OS identities
  and authoritative provider contracts; mutable operations remain catalog
  denied and fail-closed. No credential, provider, Kinko, Meta, staging,
  commit, push, publication, or deployment action occurred.

## 10. Risks and controls

- **Meta contract drift:** Official paths, fields, versions, permissions, and
  sandbox semantics can change. Keep dated source URLs per operation, re-review
  mutable claims, update fixtures, and fail closed on stale/incomplete rows.
- **False production claims:** Catalog presence, safe syntax, or passing fakes
  may be mistaken for readiness. Keep implementation and availability
  independent and require exact production adapters before transport.
- **Capability leakage:** Shared targets or runtime catalog filtering can expose
  writer behavior to readers. Enforce compile-time projections, package graph,
  symbol/string inspection, and separate archives.
- **Policy bypass:** New aliases or nested values may hide activation/spend.
  Use one bounded recursive canonical classifier, immutable typed values,
  exact authorization, and deny unknown/ambiguous input.
- **Proof confusion:** Public identity or proof for one operation/asset may be
  reused incorrectly. Bind provider evidence to principal, target, operation,
  version, purpose, freshness, request, and reconciliation strategy.
- **Crash/replay ambiguity:** A send can outlive a process or broker CAS. Anchor
  `inFlight` before transport and `outcomeUnknown` before reconciliation; allow
  only identical one-step recovery CAS and never automatic replay.
- **Broker compromise or denial of service:** Distinct OS identity and storage
  isolate heads but do not eliminate privileged compromise or socket outage.
  Fail closed on peer/permission/state mismatch and retain this residual risk.
- **Secret exposure:** Environment inheritance or diagnostics can leak tokens.
  Delay the one allowlisted Kinko environment read, use a closed auth header,
  sanitize bounded outputs, and scan source/artifacts without accessing values.
- **Untracked workspace loss:** The entire repository is untracked. Preserve
  all existing files, avoid destructive Git/filesystem commands, and record
  only scoped edits.
