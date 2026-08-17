# CLI, Testing, Documentation, Packaging, and Security Implementation Plan

**Feature ID:** `meta-delivery-security`
**Feature title:** CLI, testing, documentation, packaging, and security
**Issue reference:** `workflow:codex-design-and-implement-review-loop-session-732/communication:comm-002452`
**Workflow mode:** `issue-resolution`
**Status:** In progress; bootstrap and initial safeguards implemented
**Design reference:** `design-docs/meta-gateway-delivery-security.md`
**Codex agent reference:** `../google-marketing-gateway`
**Plan review date:** 2026-08-15

## 1. Purpose

Implement the accepted delivery and security design for the new Swift Meta
Marketing gateway. The result is a locally buildable and testable SwiftPM
package with distinct reader and writer client types and executables,
a fixed-origin generic Graph CLI, guarded writer plan/apply, Kinko-only runtime
credentials, deterministic mocks, adversarial coverage, complete operator and
release documentation, locally verified artifacts, and closed security gates.

This plan does not authorize staging, committing, pushing, publishing,
deploying, signing/notarizing, or creating billable Meta assets. Local mocks and
Meta test assets are preferred; live verification is optional, separately
approved, and strictly below USD 20 aggregate spend.

## 2. Accepted Design Decisions

- Build distinct public `MetaGraphReader`/`MetaMarketingReader` and
  `MetaGraphWriter`/`MetaMarketingWriter` capability types in the shared
  `MetaMarketingGatewayCore` library plus separate
  `meta-marketing-gateway-reader` and `meta-marketing-gateway-writer`
  executable targets.
- Do not ship a combined executable or a mode flag that upgrades reader to
  writer behavior.
- Keep generic reader Graph requests GET-only. Route typed non-mutating POST
  operations through reviewed typed reader APIs.
- Keep generic writer Graph requests behind offline canonical `plan` and exact
  `apply` confirmation, secure-file checks, expiry, replay protection, and
  spend/effect gates.
- Build every request from exact `https://graph.facebook.com`, a centrally
  supported API version, and normalized relative input; reject user origins,
  full URLs, versions in paths, headers, auth fields, redirects, and proxies.
- Resolve credential values only from `META_ACCESS_TOKEN`, optional
  `META_APP_SECRET`, and centrally allowlisted command-specific secret keys
  injected by a minimal `kinko exec --env` allowlist after all possible local
  validation.
- If the shared CLI adopts Apple's official `swift-argument-parser`, pin it to
  an exact reviewed release. Otherwise require equivalent parser/help security
  tests. Review every runtime dependency before adoption.
- Treat mocks as release-authoritative and any live Meta check as an optional,
  official-documentation-rechecked activity.
- Build release artifacts locally and verify them without publishing.
- Fail release if any verified high or medium security finding remains, or if a
  required security tool is missing without an explicitly documented gap.

## 3. Deliverables

- [ ] SwiftPM manifest, lockfile, target skeleton, entry points, version source,
  resource rules, and exact dependency declaration.
- [ ] Distinct reader and writer public client types whose protocols expose no
  cross-capability downcast or raw shared-executor escape hatch.
- [ ] Stable reader/writer CLI help, version, JSON/JSONL envelopes, exit codes,
  validation ordering, catalog routes, and redacted diagnostics.
- [ ] Fixed-origin generic GET reader route and generic POST/DELETE writer
  plan/apply route integrated with the broader generic Graph client.
- [ ] Kinko-only credential resolver and documentation; no credential flags,
  `.env`, credential files, stdin, keychain, or fallback source.
- [ ] Injected mock transport, credential resolver, clock, randomness, file
  operations, and scripted loopback fixtures.
- [ ] Unit, contract, CLI, end-to-end mock, property/fuzz corpus, concurrency,
  redaction, secure-file, replay, retry, pagination, and adversarial tests.
- [ ] README, security policy, authentication, CLI, testing, contributing,
  release, changelog, license, and generated API-doc configuration.
- [ ] Mise tasks and pinned CI definitions for lint, test, build, scans, package,
  artifact verification, and release dry run.
- [ ] Separate reader/writer release archives, SHA-256 manifest, SBOM,
  provenance input, API docs, and Homebrew formula template generated locally.
- [ ] Secret, gitleaks, SAST, dependency/license, supply-chain/config,
  threat-model, triage, and independent adversarial review evidence with all
  verified high/mid findings closed.

## 4. Task Breakdown

### TASK-000: Reconcile fanout contracts and bootstrap repository policy

**Depends on:** Accepted feature-local design.
**Parallelizable:** No.
**Write scope:** `AGENTS.md`, `.gitignore`, `.gitattributes`, `.swift-version`,
`mise.toml`, initial directory skeleton, and coordination notes required by
other accepted feature plans.

**Work:**

- Inspect all accepted design documents and implementation plans before naming
  shared targets or public protocols. Resolve conflicts in favor of the parent
  issue's reader/writer split, generic endpoint completeness, and Kinko-only
  secret boundary; record any cross-feature decision in the owning design
  before source implementation.
- Add ignore rules for `.build/`, release staging, coverage/fuzz output,
  temporary plan/request/output files, `.env*`, credentials, tokens, secret
  scan reports, crash dumps, and local Meta/Kinko state. Do not ignore source,
  lockfiles, sanitized fixtures, or checked-in release scripts.
- Establish Swift 6/macOS 14, formatting, linting, line-ending, generated-file,
  and no-real-secret fixture policy.
- Inspect the reference repository's target, mise, test, and packaging patterns
  without copying Google-specific credentials, endpoints, or live-operation
  limits.

**Completion criteria:**

- [ ] Shared target names and protocol ownership agree with every accepted
  feature design.
- [ ] Repository policy explicitly bans credential persistence and real-looking
  fixture secrets.
- [ ] Ignore rules cover local sensitive/transient material while keeping
  auditable source and lockfiles visible.
- [ ] No stage, commit, push, publish, deploy, or live API action occurred.

### TASK-001: Create SwiftPM product and dependency boundaries

**Depends on:** TASK-000.
**Parallelizable:** No.
**Write scope:** `Package.swift`, `Package.resolved`, `Sources/` entry points and
module skeletons, `Tests/` skeletons, version source.

**Work:**

- Declare the `MetaMarketingGatewayCore` library, separate
  `MetaMarketingGatewayReader` and `MetaMarketingGatewayWriter` executable
  targets/products, and `MetaMarketingGatewayCoreTests`, matching the accepted
  Graph and typed-domain plans.
- Keep reader and writer clients as distinct public capability types. Hide the
  raw executor/transport and prevent either client from downcasting to the
  other capability. Keep writer CLI routes and executor composition out of the
  reader executable.
- If adopted, pin `swift-argument-parser` to an exact reviewed release from
  Apple's official repository and commit the resolved graph. A dependency-free
  parser must meet the same help/parser/adversarial criteria. Add no other
  runtime dependency without review.
- Add version/build metadata that reads no Git remote, environment secret, or
  machine-local path at runtime.
- Add API-surface, parser-routing, and binary smoke tests that fail if the reader
  client gains writer methods/raw-executor escape hatches or the reader
  executable gains writer commands.

**Completion criteria:**

- [ ] `swift package describe` lists the shared core library and exactly the two
  intended executable products/targets.
- [ ] Both executable help commands build and run locally.
- [ ] Reader client API inspection contains no mutation/apply/raw-executor
  method, and reader help/routing contains no writer route.
- [ ] Dependency source, exact version, license, and lock digest are reviewed.

### TASK-002: Implement shared CLI envelopes and validation pipeline

**Depends on:** TASK-001 and the core transport/model contracts from sibling
feature plans.
**Parallelizable:** No; reader/writer CLI tasks depend on it.
**Write scope:** CLI support in `MetaMarketingGatewayCore`, executable entry
points, core and CLI tests.

**Work:**

- Implement common help/version/output/retry/timeout/request-id options and the
  stable exit-code mapping from the design.
- Define Codable JSON/JSONL success and safe-error envelopes; centralize stdout
  and stderr routing and guarantee one terminal machine envelope per command.
- Implement ordered dispatch: parse, local schema/bounds, capability/policy,
  plan integrity where applicable, credential resolution, then transport.
- Reject all credential, URL/origin, version-in-path, authorization/header,
  cookie, proxy, redirect, and secret-file flags at parser/schema boundaries.
- Centralize safe diagnostics and prove `--help`, `--version`, plan, invalid,
  and denied commands never call the credential resolver or transport.

**Completion criteria:**

- [ ] Help and machine envelopes are snapshot-tested and documented.
- [ ] Exit codes match the design for syntax, credential, provider, transport,
  writer-policy, and internal failures.
- [ ] Runtime-generated credential canaries are absent from stdout, stderr,
  safe logs, errors, debug descriptions, and receipts.
- [ ] Invalid or denied commands make zero credential and transport calls.

### TASK-003: Deliver reader CLI and safe generic GET routing

**Depends on:** TASK-002 and sibling reader/generic Graph client APIs.
**Parallelizable:** Yes, with TASK-004 and TASK-005 after TASK-002 interfaces
stabilize.
**Write scope:** reader library/CLI integration and reader tests.

**Work:**

- Add `graph get`, typed `ads` reader groups, catalog listing, and redacted auth
  status routes without exposing writer commands.
- Accept one normalized relative path, bounded query parameters/fields, and
  pagination controls. The generic reader chooses GET; it accepts no method.
- Construct requests from the fixed Meta origin and central version policy.
  Disable redirects and rebuild pagination using validated cursors rather than
  following or printing provider next URLs.
- Stream large results to secure bounded files where the core response policy
  requires it; return a sanitized receipt.
- Test absence/rejection of POST, DELETE, plan, apply, activate/publish, access,
  billing, and unknown-effect operations before credentials.

**Completion criteria:**

- [ ] Every reader request is exact-host HTTPS with a central version and no
  user-controlled header/origin/method.
- [ ] Host/path/pagination adversarial cases make zero network calls.
- [ ] Reader binary and public reader client cannot dispatch a generic mutation.
- [ ] Typed readers remain reachable and their non-mutating POST exceptions do
  not widen generic reader behavior.

### TASK-004: Deliver writer canonical plan/apply and effect gates

**Depends on:** TASK-002 and sibling writer/generic Graph client APIs.
**Parallelizable:** Yes, with TASK-003 and TASK-005.
**Write scope:** writer library/CLI integration, secure plan files, replay state,
policy code, and writer tests.

**Work:**

- Implement offline generic `graph post|delete ... --plan` and typed Ads
  `preview` routes. Generic planning makes no credential or network call; typed
  preview may perform only descriptor-declared read observations after complete
  local validation. Canonicalize safe intent, risk classification, version/path/method,
  body/query digests, creation/expiry, and confirmation digest.
- Atomically create owner-only plan files and reopen them without following
  symlinks. Bound type, owner, mode, bytes, nesting, scalar/collection size,
  schema, and canonical representation; detect replacement races.
- Implement apply-time digest, expiry, confirmation, resource, body, package
  schema/version, credential profile consistency, and spend-policy checks before
  credential resolution.
- Add process-safe replay protection and explicit ambiguous-outcome handling.
  Disable blind retries for non-idempotent mutations and require typed
  idempotency or reconciliation before enabling retry.
- Deny generic billing, access control, account deletion, funding/payment,
  publish/activate, budget increase, or unknown-spend operations. Enable such
  effects only through separately reviewed typed policies.
- Represent money in integral minor units or an exact decimal type; reject
  overflow, negative bounds, currency ambiguity, and an aggregate estimate at
  or above USD 20.

**Completion criteria:**

- [ ] Generic plan performs no credential or network access. Typed preview makes
  no mutation and only its declared reader observations. Neither artifact
  contains a credential, environment snapshot, header, proof, raw provider
  response, or full URL.
- [ ] Tamper, expiry, confirmation mismatch, insecure file, body replacement,
  replay, concurrency, ambiguous retry, and spend-bound tests fail closed.
- [ ] Apply reconstructs fixed-origin requests and cannot trust method, host,
  headers, or authorization from an unvalidated file.
- [ ] No writer test performs a live API call or billable action.

### TASK-005: Implement the Kinko-only runtime credential boundary

**Depends on:** TASK-002 and credential interfaces from sibling client work.
**Parallelizable:** Yes, with TASK-003 and TASK-004.
**Write scope:** environment credential adapter, configuration schema,
redaction/lifetime support, and focused tests.

**Work:**

- Add an injected resolver that accepts only `META_ACCESS_TOKEN`, optional
  `META_APP_SECRET`, and centrally allowlisted command-scoped secret keys from
  the child process environment.
- Allow non-secret configuration to name required keys but structurally reject
  embedded secret values, fallback strings, shell expressions, credential
  paths, `.env`, stdin, keychain, and alternate environment key names.
- Use bearer authorization and derive `appsecret_proof` only when the reviewed
  operation/profile policy requires it. Treat the proof as a secret and keep
  credential lifetime inside request construction/execution.
- Prevent environment enumeration, secret-bearing debug descriptions, child
  process propagation, URL logging, crash/receipt persistence, and provider-body
  reflection.
- Add tests with runtime-generated canaries and recording resolvers to prove all
  locally decidable failures precede credential access.

**Completion criteria:**

- [ ] Repository/documentation offers no operational credential source other
  than minimal `kinko exec --env` injection.
- [ ] Credentials never appear in CLI arguments, files, stdout/stderr, logs,
  plans, paging, errors, tests, artifacts, or debug output.
- [ ] Commands needing fewer credentials document and accept smaller Kinko
  allowlists; `--all` is never used.
- [ ] Tests distinguish missing credentials safely without revealing which
  other secret values or profiles exist.

### TASK-006: Build deterministic mock and contract-test infrastructure

**Depends on:** TASK-001 and stable transport/client protocols.
**Parallelizable:** Yes, with TASK-002 through TASK-005 once protocol seams are
agreed.
**Write scope:** test-support code, non-secret fixtures, loopback mock server,
and unit/integration tests.

**Work:**

- Provide injected recording/scripted transports, credential resolver, clock,
  UUID/random bytes, sleeper/backoff, file operations, and safe output sinks.
- Add fixture builders for typed Ads domains and generic Graph responses,
  pagination, async insights polling, throttling, transient/permanent errors,
  malformed/oversized bodies, cancellation, and partial streaming.
- Generate secret canaries at runtime; keep committed ids, emails, URLs, tokens,
  account data, and payloads unmistakably synthetic.
- Add request-contract assertions for exact method/host/version/path/query,
  allowlisted headers, body bytes/digest, retry count, and credential timing.
- Add loopback-only end-to-end tests without changing the production origin
  policy; test code injects transport behavior, not a production base-URL flag.

**Completion criteria:**

- [ ] Default `swift test` requires no network, Kinko unlock, Meta account, or
  billable asset.
- [ ] Fixtures and snapshots pass secret/private-URL/real-identifier review.
- [ ] Mock scripts deterministically cover pagination, async jobs, rate limits,
  transient errors, cancellation, and partial streams.
- [ ] Production binaries contain no mock-base-URL or trust-bypass flag.

### TASK-007: Add adversarial, property, concurrency, and regression coverage

**Depends on:** TASK-003 through TASK-006.
**Parallelizable:** Yes by test focus area, but merge and rerun as one suite.
**Write scope:** tests and fuzz/property corpora only, plus narrowly scoped fixes
to verified failures.

**Work:**

- Cover the complete URL/path/query/header/body attack matrix in the design,
  including encoding ambiguity, Unicode/control input, SSRF/redirect attempts,
  header smuggling, pagination poisoning, and response bombs.
- Cover secret canaries in every input/output/error/log/artifact channel and
  unknown provider JSON fields.
- Cover writer plan tamper/race/replay/concurrent apply, stale versions, changed
  bodies, retry ambiguity, exact-money overflow/rounding, risk denial, and
  cleanup receipts.
- Add deterministic property tests and a checked-in non-secret regression
  corpus for path/query normalization, canonical JSON, redaction, bounded
  decoding, and plan verification.
- Run address sanitizer and thread sanitizer in separate jobs where supported;
  record unsupported combinations as explicit coverage gaps with alternatives.

**Completion criteria:**

- [ ] Every adversarial category from design Section 8 has at least one named
  test and hostile local inputs cause zero unauthorized transport calls.
- [ ] Sanitizer/property tests are deterministic or document seeds and replay.
- [ ] Every fixed security regression has a non-secret repository test.
- [ ] No verified high or medium test finding remains open.

### TASK-008: Write operator, developer, security, and API documentation

**Depends on:** TASK-002 through TASK-007 behavior stabilized.
**Parallelizable:** Yes, with initial TASK-009 work; final examples wait for
stable help/output.
**Write scope:** `README.md`, `SECURITY.md`, `CONTRIBUTING.md`, `CHANGELOG.md`,
`LICENSE`, `docs/`, DocC configuration/catalogs, generated-help checks.

**Work:**

- Document exact reader/writer behavior, supported/unsupported operations,
  JSON envelopes, exit codes, plan/apply, pagination, safe errors, file bounds,
  and troubleshooting without raw provider bodies.
- Document only minimal Kinko commands, for example:

  ```bash
  kinko exec --env META_ACCESS_TOKEN -- \
    swift run meta-marketing-gateway-reader graph get \
    --api-version vNN.N --path me --fields id
  ```

  Never document `--all`, `.env`, exports, inline assignments, token flags,
  secret retrieval, or credential redirection.
- Document mock-first testing, Meta test/sandbox asset preference, use of
  `taco-dev-sandbox@mutvar.com` for interactive setup, optional read-only smoke,
  separate approval for writers, cleanup, and aggregate spend strictly under
  USD 20.
- Add official Meta source URLs and checked dates for mutable version,
  permission, access-tier, rate-limit, and test-asset claims; recheck them on the
  implementation/release date.
- Generate API documentation and assert public reader docs contain no writer
  apply API.

**Completion criteria:**

- [ ] Fresh-user instructions can build, test, and run help without credentials.
- [ ] Every credential-bearing example uses `kinko exec --env` with an explicit
  minimal key list and contains no plausible secret value.
- [ ] Mutable Meta claims cite an official source and checked date.
- [ ] Generated CLI help and public API docs match tests and package products.

### TASK-009: Implement CI, local release packaging, and artifact verification

**Depends on:** TASK-001, TASK-006, and stable CLI version/help; final gate waits
for TASK-007 and TASK-008.
**Parallelizable:** Yes for initial scripts/workflows; final verification is
serialized.
**Write scope:** `mise.toml`, `.github/workflows/`, `scripts/`,
`packaging/homebrew/`, SBOM/provenance configuration, release tests.

**Work:**

- Add direct Swift and mise tasks for resolve, format-check, lint, build, tests,
  sanitizers, dependency inspection, scans, docs, package, and artifact verify.
- Pin GitHub Actions by full commit SHA with a nearby reviewed release comment;
  use least permissions, no untrusted fork secrets, no `pull_request_target`
  checkout/build, no mutable action tags, and no publish permissions in CI.
- Build separate architecture/version reader and writer archives in a fresh
  temporary staging root; normalize permissions, ordering, timestamps, and
  member paths.
- Generate SHA-256 manifest, dependency/package manifest, SPDX/CycloneDX SBOM,
  provenance input, API docs, and Homebrew formula template without publishing.
- Inspect unpacked artifacts for path traversal, symlinks, `.env`, credentials,
  build cache, VCS data, crash/fuzz/scan output, absolute machine paths, and
  private URLs. Smoke-test help/version and reader rejection/absence of writer.
- Build twice with the same toolchain and compare manifests. Eliminate or
  explicitly isolate every nondeterministic field before acceptance.

**Completion criteria:**

- [ ] CI is read-only and least-privileged; release/upload jobs do not exist or
  require a separate reviewed workflow and explicit authorization.
- [ ] Reader and writer archives are separate, complete, checksum-valid, and
  free of credentials/transient/private-path content.
- [ ] SBOM and provenance inputs match the exact dependency lock and artifacts.
- [ ] Reproducibility comparison passes for normalized contents.
- [ ] No artifact was uploaded, signed, notarized, published, or deployed.

### TASK-010: Run final deterministic and independent security-review gates

**Depends on:** TASK-001 through TASK-009 complete.
**Parallelizable:** No; final fail-closed gate.
**Write scope:** Narrow fixes for verified findings and redacted local evidence;
do not commit raw scanner output containing sensitive paths/data.

**Work:**

- Confirm diff scope, generated files, licenses, docs, full tests, sanitizer
  evidence, release archives, target separation, and that no live/billable or
  external mutation occurred.
- Run repository secret patterns and gitleaks with redaction. Manually classify
  every match; placeholders and test field names do not excuse a real value.
- Run deterministic SAST plus manual URL, redirect, credential, logging, file,
  subprocess, replay, money, decoder, concurrency, and error-boundary review.
- Audit dependency vulnerabilities/licenses, exact lock/source, action SHAs,
  package scripts/plugins, release tooling, SBOM, and supply-chain/config.
- Run the packaged source-security workflow with network audits disabled unless
  explicitly authorized. Preserve method-specific evidence for secrets,
  gitleaks, static analysis, dependencies, supply chain, harness recon, triage,
  and adversarial verification.
- Fix every adversarially verified high or medium finding, rerun all
  deterministic gates, and record low residual risks with owner/review date.

**Completion criteria:**

- [ ] Required tools ran successfully; any unavailable tool is an explicit
  unresolved coverage gap and prevents acceptance unless equivalent evidence is
  independently reviewed and documented.
- [ ] No verified high or medium security finding remains.
- [ ] Every accepted low finding has rationale, owner, compensating control,
  and review date.
- [ ] Full lint, tests, build, scans, package, artifact inspection, and second
  independent adversarial pass succeed after the final fix.
- [ ] Worktree remains unstaged and uncommitted; no push/publish/deploy/live
  billable action occurred.

## 5. Dependencies and Execution Order

```text
TASK-000
  -> TASK-001
       -> TASK-002 -> TASK-003 --\
                   -> TASK-004 ----> TASK-007 -> TASK-008 --\
                   -> TASK-005 --/               TASK-009 ---> TASK-010
       -> TASK-006 ------------------------------/
```

- TASK-000 reconciles all fanout designs before this feature creates shared
  package names or interfaces.
- TASK-001 is the product-boundary foundation.
- TASK-002 stabilizes parser/output/validation contracts.
- TASK-003, TASK-004, and TASK-005 may proceed in parallel after TASK-002;
  TASK-006 may start when transport seams from TASK-001 are stable.
- TASK-007 integrates adversarial coverage after behavior and mocks exist.
- TASK-008 and TASK-009 can overlap, but artifact examples/help must use the
  stabilized CLI and final release verification waits for tests/docs.
- TASK-010 is serialized after all implementation deliverables.

External dependencies are the sibling feature implementations of core Graph
transport, typed Ads APIs, pagination/async jobs, error models, and reader/writer
policies. This plan may add delivery adapters and tests but must not silently
redesign those public contracts; conflicts return to the owning design.

## 6. Design-to-Plan Consistency Matrix

| Accepted design area | Plan coverage | Acceptance evidence |
|---|---|---|
| Separate reader/writer client types and executables | TASK-001, TASK-003, TASK-004 | Package describe, API inspection, parser routing, reader rejection smoke. |
| Stable CLI and validation-before-credentials | TASK-002 | Snapshot/exit-code tests and recording resolvers. |
| Fixed-origin generic Graph surface | TASK-003, TASK-004, TASK-007 | Exact request contracts and URL adversarial suite. |
| Writer plan/apply, replay, retry, spend gates | TASK-004, TASK-007 | Secure-file, digest, concurrency, money, and effect-policy tests. |
| Kinko-only credentials | TASK-005, TASK-008 | Resolver/canary tests and docs scan for prohibited patterns. |
| Mock-first and optional Meta test assets | TASK-006, TASK-007, TASK-008 | Network-free test suite and separately gated live instructions. |
| Documentation contract and official source dates | TASK-008 | Docs inventory, generated help, official-source review. |
| SwiftPM/release artifacts | TASK-001, TASK-009 | Lock audit, archives, checksums, SBOM, provenance, reproducibility. |
| Secret and final security-review gates | TASK-007, TASK-009, TASK-010 | Redacted method-specific scan/review evidence and zero open high/mid. |

## 7. Progress Tracking

- [ ] `TASK-000`: Reconcile fanout contracts and bootstrap repository policy.
- [ ] `TASK-001`: Create SwiftPM product and dependency boundaries.
- [ ] `TASK-002`: Implement shared CLI envelopes and validation pipeline.
- [ ] `TASK-003`: Deliver reader CLI and safe generic GET routing.
- [ ] `TASK-004`: Deliver writer canonical plan/apply and effect gates.
- [ ] `TASK-005`: Implement the Kinko-only runtime credential boundary.
- [ ] `TASK-006`: Build deterministic mock and contract-test infrastructure.
- [ ] `TASK-007`: Add adversarial, property, concurrency, and regression tests.
- [ ] `TASK-008`: Write operator, developer, security, and API documentation.
- [ ] `TASK-009`: Implement CI, local release packaging, and verification.
- [ ] `TASK-010`: Run final deterministic and independent security gates.

Progress updates must include date, task, files changed, commands run, pass/fail,
security findings by severity/method, spend (expected USD 0), and explicit
confirmation that no stage/commit/push/publish/deploy occurred. A task checkbox
may be checked only when all its completion criteria and relevant tests pass.

- 2026-08-15: Reconciled accepted names/contracts and bootstrapped `Package.swift`,
  separate reader/writer products, core tests, `.gitignore`, `mise.toml`,
  README, SECURITY, and CONTRIBUTING. Implemented fixed-origin validation,
  Kinko-only credential resolution, machine JSON success/error envelopes, and
  mock-first focused tests. `mise run lint`, `mise run test`, `mise run build`,
  executable help smoke tests, and `git diff --check` passed. No high/medium
  verified finding from this initial slice; CI/release packaging, independent
  scan tools, and final review remain blocking unchecked work. Spend was USD 0;
  no stage, commit, push, publish, deploy, or live API action occurred.
- 2026-08-15: Self-review corrections fixed descriptor-based secure file I/O,
  canonical-plan tamper detection, reader missing-credential exit code 3,
  provider rejection exit code 4, and typed paging decoding. `mise run lint`,
  `mise run test`, and `mise run build` passed. Security/release/CI tasks remain
  explicitly unchecked and block final acceptance.
- 2026-08-15: Added pinned read-only GitHub Actions CI, target-separation audit,
  and local separate reader/writer release-archive plus SHA-256 manifest task.
  Local `mise run target-audit`, `mise run package-local`, lint, test, and build
  passed. SBOM, reproducibility comparison, and independent security gates
  remain unchecked.
- 2026-08-15: Self-review correction: verified the checkout SHA against the
  upstream `v4.2.2` tag, recorded CI provenance/toolchain logging, and replaced
  copied binary directories with normalized `.tar.gz` archives, checksums,
  SBOM/provenance inputs, unpacked-content checks, and a two-build byte-for-byte
  reproducibility task. `mise run package-verify` passed. Final security gates
  remain unchecked.

## 8. Verification Commands

### Plan-document verification

```bash
test -f design-docs/meta-gateway-delivery-security.md
test -f impl-plans/meta-gateway-delivery-security.md
rg -n "TASK-00|Completion criteria|Kinko|kinko exec --env|gitleaks|USD 20" \
  impl-plans/meta-gateway-delivery-security.md
git diff --check -- design-docs/meta-gateway-delivery-security.md \
  impl-plans/meta-gateway-delivery-security.md
git diff --no-index -- /dev/null impl-plans/meta-gateway-delivery-security.md
```

### Implementation build and test gate

```bash
swift --version
swift package resolve
swift package describe
swift package show-dependencies --format json
swift build
swift build -c release
swift test --parallel
swift test --sanitize=address
swift test --sanitize=thread
swift run meta-marketing-gateway-reader --help
swift run meta-marketing-gateway-writer --help
swift run meta-marketing-gateway-reader --version
swift run meta-marketing-gateway-writer --version
mise run format-check
mise run lint
mise run test
mise run package
mise run verify-release
```

Run address and thread sanitizer commands as separate jobs. If the selected
Swift/macOS toolchain does not support one, record the failure and substitute an
independently reviewed concurrency/memory check; do not silently drop coverage.

### Diff, secret, dependency, and artifact gate

```bash
git status --short --untracked-files=all
git diff --check
rg -n --hidden -g '!.git/**' -g '!.build/**' \
  '(access[_-]?token|app[_-]?secret|client[_-]?secret|Bearer[[:space:]]|BEGIN (RSA|EC|OPENSSH|PRIVATE) KEY)'
gitleaks detect --no-git --redact --source .
swift package show-dependencies --format json
mise run dependency-audit
mise run supply-chain-audit
mise run verify-release
```

Every `rg`/gitleaks result receives manual classification because safe field
names and redaction tests can match; no plausible credential value may remain.

### Packaged source-security loop

```bash
riela package install codex-source-security-check-loop
riela package install codex-design-and-implement-review-loop
riela workflow run codex-source-security-check-loop \
  --variables '{"workflowInput":{"targetPath":".","runNetworkAudits":"false","maxFindings":50,"constraints":["Kinko is the only credential store.","Use only explicit kinko exec --env allowlists.","Do not stage, commit, push, publish, or deploy.","Keep fixes scoped to verified findings.","Prefer mocks and Meta test assets; do not perform billable actions."]}}' \
  --output jsonl --verbose --no-auto-improve
```

### Optional live read smoke, separately approved

Before this command, recheck official Meta documentation, confirm the selected
asset is test/sandbox and non-delivering, and use
`taco-dev-sandbox@mutvar.com` if interactive setup is required:

```bash
kinko exec --env META_ACCESS_TOKEN -- \
  swift run meta-marketing-gateway-reader graph get \
  --api-version vNN.N --path me --fields id
```

Do not run a live writer apply as a release gate. V1 live-spend policy authorizes
USD 0. Any future separately reviewed writer check must record preview,
allowlisted test asset, cleanup, exact spend, and an aggregate workflow spend
strictly below USD 20.

## 9. Overall Completion Criteria

- [ ] All TASK-000 through TASK-010 criteria are checked with dated evidence.
- [ ] Reader/writer client types and executable routes are capability separated,
  and the generic surface cannot change origin/version/headers or mutate
  through reader.
- [ ] Writer plan/apply resists tamper, stale/replay/concurrency, retry
  ambiguity, unsafe files, and unknown/bounded spend.
- [ ] Kinko is the sole credential store and every operational command uses a
  minimal explicit `kinko exec --env` allowlist.
- [ ] Full tests are deterministic, mock-first, non-network, and non-billable;
  any live check is separately approved and uses Meta test assets.
- [ ] Documentation, package lock, CI, separate archives, checksums, SBOM,
  provenance input, API docs, and Homebrew template match verified behavior.
- [ ] Secret, gitleaks, SAST, dependency/license, supply-chain/config,
  threat-model, triage, and independent adversarial gates pass after final fixes.
- [ ] No verified high or medium security finding or unexplained scanner gap
  remains; accepted lows are documented residual risks.
- [ ] No stage, commit, push, release, publish, deploy, signing/notarization, or
  billable campaign creation occurred under this plan.

## 10. Implementation Plan Review Record

### Self-review

Decision: **accepted after corrections**.

- Plan-only high defect: the initial task order could let CLI work establish
  target boundaries before sibling fanout contracts were reconciled. Added
  TASK-000 and made TASK-001 the serialized package foundation.
- Plan-only medium defect: deliverables lacked explicit progress evidence and
  checkbox rules. Added Section 7 with per-task dated evidence requirements.
- Plan-only medium defect: build/test commands did not prove release artifacts
  or reader archive separation. Added TASK-009, direct smoke commands, package
  and artifact verification criteria.
- Design defect found during plan review: cross-feature contract comparison
  found target-layout, API-version, generic command, plan-body, and base Kinko
  key drift. The design was corrected to match the accepted foundation before
  this plan was accepted.

### Independent review pass

Decision: **accepted after corrections; no open high or medium findings**.

- Plan-only high defect: final security review was previously a single generic
  scan and could pass when a tool was absent. TASK-010 now separates secret,
  gitleaks, SAST, dependency, supply-chain, harness, triage, and adversarial
  evidence, treats missing tools as gaps, and requires complete reruns.
- Plan-only high defect: Kinko compliance lacked an executable minimal-allowlist
  verification path. TASK-005, TASK-008, and the optional read smoke now specify
  exact `kinko exec --env` usage and prohibit `--all` or alternate stores.
- Plan-only medium defect: release completion could be mistaken for permission
  to publish. TASK-009 and overall criteria explicitly stop at local artifacts.
- Plan-only medium defect: optional live checks lacked an authoritative
  mutable-doc recheck and identity. TASK-008 and verification now require
  official Meta sources, Meta test assets, and
  `taco-dev-sandbox@mutvar.com` for interactive setup.
- Design defect found during independent plan review: none after the preceding
  cross-feature correction.

Both design and implementation plan are accepted. Implementation remains wholly
pending and must not be reported complete until every checkbox and final gate is
satisfied.

## 11. Addressed Feedback

- 2026-08-15: Local archive evidence now contains checked archive hashes,
  package/source inventory digests, toolchain capture, SPDX checksums, and a
  provenance input bound to both archives. The reproducibility task compares
  archive, manifest, SBOM, and provenance bytes. Independent security gates and
  release completion criteria remain unchecked.
- 2026-08-15: Corrected the generated SPDX document into distinct reader and
  writer package records with defined SPDX identifiers and document
  relationships. Added `scripts/validate-spdx.sh`; local packaging verifies its
  required SPDX structure and the reproducibility task reruns that validation.
  This is a generator-specific structural check, not a replacement for an
  independent SPDX/security scan; final security gates remain unchecked.
- 2026-08-15: Added deterministic local secret-name/token-shape and
  supply-chain pin/no-runtime-dependency audits to `mise.toml`. They are
  compensating local checks only; missing gitleaks, SAST, dependency/license,
  supply-chain/config, adversarial, and independent-review evidence remains a
  release-blocking gap. No files were staged and no live API activity occurred.
- 2026-08-15: Added deterministic regressions for terminal retry evidence,
  post-fetch pagination deadlines, pull-based multipart streaming, strict typed
  CLI validation, and programmatic filter validation. Local `mise run check`,
  target/package, secret, and supply-chain audits remain passing. Gitleaks,
  SAST, dependency/license, independent supply-chain/config, adversarial, SPDX,
  and final independent security-review gates remain unchecked blockers.
- 2026-08-15: Added deterministic durable-journal restart/tombstone and exact
  insight-subject/path regressions. The concrete fixed-origin multipart path is
  locally verified with the transport boundary retained separate from ordinary
  Graph requests. `mise run test` passes offline; independent security gates
  remain release-blocking.
- 2026-08-15: Bounded multipart response receipt collection and narrowed the
  enabled upload route to provider-revalidated `act_<id>/adimages`; `advideos`
  remains disabled. Added journal hash-chain/tamper and typed account-list
  coverage. Independent security gates remain unchecked blockers.
- 2026-08-15: Added deterministic offline writer apply/reconciliation coverage:
  principal/asset/USD 0 evidence is required before a single mocked transport
  send, durable success receipts suppress duplicate sends, and an unknown
  outcome remains blocked after reconciliation reports pending. This does not
  replace the missing production provider integrations, crash/rotation/compaction
  coverage, or independent security gates; all corresponding completion criteria
  remain unchecked.
- 2026-08-15: Added an isolated `URLProtocol` contract test for file-backed
  multipart request streaming, authorization header handling, and oversized
  receipt rejection. The test remains entirely local and makes no Meta request.
- 2026-08-15: Added expiry, same-identity credential-rotation, pre-send retry,
  redirect-denial, authentication-challenge-denial, and oversized-receipt
  cancellation regressions. Local evidence is stronger, but the independent
  security gates and incomplete release criteria remain unchecked.
- 2026-08-15: Corrected the upload delegate so platform-default server-trust validation remains
  enabled while non-TLS authentication challenges and all redirects are denied. Added send-boundary
  expiry coverage proving a plan that expires during verification is not sent. All task checkboxes,
  production writer wiring, and independent security gates remain unchecked.
- 2026-08-15: Extended send-boundary coverage through the asynchronous journal transition: expiry
  at that point leaves a `failedSafeToRetry` record and performs zero transport sends.
- 2026-08-15: Added deterministic journal compaction, terminal-only namespace rotation,
  independently stored trusted heads for rollback detection, and before/after atomic-replacement
  crash checkpoints. Added nominal tolerant typed-reader records with lossless drift retention.
  `mise run check` remains the local gate; production writer wiring remains incomplete and unchecked.
- 2026-08-15: Independent local scans are now available and passed: `gitleaks detect --no-git
  --redact --source .` found no leaks; `semgrep scan --config p/default --metrics off --error .`
  found zero findings; `osv-scanner --recursive .` found no package sources because SwiftPM has no
  dependencies; `syft dir:. --exclude './.build' --output spdx-json` generated an external SBOM;
  and `trivy fs --scanners vuln,secret,misconfig --skip-dirs .build --quiet .` reported no findings.
  These do not complete the remaining integration, adversarial, and final independent-review criteria.
- 2026-08-15: Added accepted command aliases `mise run package`, `mise run verify-release`, and
  `mise run dependency-audit`; the latter confirms the current SwiftPM dependency graph is empty.
  Release archives and target separation verify locally. Trivy reports its Swift/config scanners as
  unsupported for this repository, so that result is recorded as a scoped scanner limitation rather
  than a clean vulnerability/misconfiguration result. Final adversarial and independent review
  criteria remain unchecked.
- 2026-08-15: Added journal-retirement and stale-trusted-anchor adversarial regressions. The
  source-security workflow, production writer integration, complete typed-reader acceptance matrix,
  independent SPDX schema validation, and unsupported Trivy vulnerability/misconfiguration coverage
  remain explicit unchecked release blockers.
- 2026-08-15: Ran the packaged `codex-source-security-check-loop` through Riela with network
  audits disabled. It created `codex-source-security-check-loop-session-738` but failed before
  scanning because the package-owned `source-security-scan.bash` lacks execute permission; this is
  recorded as an adapter/package blocker, not a clean gate. Independent SPDX schema validation and
  the final adversarial review remain unchecked.
- 2026-08-15: As a read-only fallback for the package permission defect, invoked the identical
  package scanner through `bash` with generated `.build` output and planning/design documents
  excluded from source-code coverage. It scanned 34 repository code/config files with zero secret,
  gitleaks, static, dependency, or supply-chain findings; network dependency audits stayed disabled.
  A fresh Syft SPDX JSON was parsed for required SPDX document fields, but this is structural
  validation only and does not satisfy the independently maintained SPDX schema-validator criterion.
- 2026-08-15: Re-ran the packaged source-security workflow through Riela as
  `codex-source-security-check-loop-session-740`; its deterministic scan and harness recon are
  recorded in that in-progress session. Installed the independently maintained `spdx-tools` 0.8.3 package in
  an isolated temporary directory and validated `.build/independent-sbom.spdx.json` with
  `parse_from_file` plus `validate_full_spdx_document`. Final adversarial workflow stages and
  production writer/typed-reader completion remain unchecked.
- 2026-08-15: Session `codex-source-security-check-loop-session-740` resumed
  after a stalled triage attempt. Its completed static triage classified the
  Markdown command and generated `.build` plist DTD alerts as false positives,
  and verified `TRIAGE-AUTH-001` (medium) in writer asset/path binding. The
  narrowly scoped source/test fix is recorded in the writer plan; adversarial
  verification and final workflow review are still running. Added an offline
  focused typed-reader acceptance suite and processed synthetic fixture;
  `swift test --filter MetaAdsReaderAcceptanceTests` and the two named writer
  regressions pass. All TASK-000 through TASK-010 boxes remain unchecked until
  every respective completion criterion has dated evidence. No stage, commit,
  push, publish, deploy, live request, mutation, credential persistence, or
  spend occurred.
- 2026-08-15: The resumed packaged source-security session
  `codex-source-security-check-loop-session-740` completed with exit code 0.
  Its adversarial verifier accepted the `TRIAGE-AUTH-001` canonical
  asset-path/returned-evidence fix; no adversarially verified high or medium
  finding remains. Scanner Markdown and generated `.build` plist candidates
  were documented false positives/duplicates. Runtime and network behavior
  remain explicit coverage gaps, and generated-build scan noise plus the
  all-untracked provenance baseline are accepted low risks. TASK-010 cannot be
  checked until its TASK-001 through TASK-009 dependencies and all final
  criteria are complete.

- Scoped all planned documentation to
  `design-docs/meta-gateway-delivery-security.md` and this implementation plan;
  implementation file paths are future deliverables, not changes in this
  planning worker.
- Made workflow mode, issue reference, feature identity, reference repository,
  no-commit/no-publish rule, Kinko-only credentials, explicit allowlists, mocks,
  Meta test assets, official-doc rechecks, and sub-USD-20 ceiling explicit.
- Separated design defects from plan-only defects in both review records.
- Added design-plan mapping, dependencies, task-level completion criteria,
  progress tracking, verification commands, and final acceptance criteria.
- Closed every self-review and independent-review high or medium finding before
  marking the documents accepted.
