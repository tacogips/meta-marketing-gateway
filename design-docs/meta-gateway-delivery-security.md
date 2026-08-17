# CLI, Testing, Documentation, Packaging, and Security

**Feature ID:** `meta-delivery-security`
**Feature title:** CLI, testing, documentation, packaging, and security
**Issue reference:** `workflow:codex-design-and-implement-review-loop-session-732/communication:comm-002452`
**Workflow mode:** `issue-resolution`
**Status:** Accepted for implementation planning
**Review date:** 2026-08-15
**Implementation plan:** `impl-plans/meta-gateway-delivery-security.md`
**Codex agent reference:** `../google-marketing-gateway`

## 1. Purpose and Scope

This feature defines the delivery shell for a production-quality Swift gateway
to Meta's Graph and Marketing APIs: command UX, executable separation, mock and
adversarial testing, Kinko-only credential injection, documentation, SwiftPM
packaging, release artifacts, secret scanning, and final security-review gates.

The broader repository owns the generic Graph client, typed Ads-domain APIs,
models, pagination, transport, and reader/writer service behavior. This feature
turns those capabilities into a safe and releasable package. It must preserve a
generic relative-path surface so future Graph endpoints do not require a new
transport implementation, while preventing that surface from becoming an
arbitrary HTTP proxy or bypassing the reader/writer boundary.

This design does not authorize a live mutation, release, publish, deployment,
commit, or push. It does not store or migrate credentials. All implementation
and verification remain local and non-billable unless the user separately
approves a bounded live check.

## 2. Repository and Reference Findings

| Area | Finding | Design consequence |
|---|---|---|
| Target repository | The repository root is empty and unborn at planning time. | The plan must bootstrap package, tests, docs, CI, and release metadata rather than assume existing targets. |
| Reference repository | `../google-marketing-gateway` is a Swift 6 SwiftPM CLI with separate reader/writer/admin/compatibility executables, a shared core, deterministic tests, mise tasks, and Homebrew release guidance. | Reuse its capability-separated target and verification patterns, but do not copy its credential persistence or Google-specific product model. |
| Credential constraint | Kinko is the only credential store and `kinko exec --env KEY[,KEY...] -- command` supports an explicit environment allowlist. | The gateway accepts credential values only from allowlisted process environment keys injected at execution; no `.env`, credential file, command argument, standard-input, keychain, or package configuration source is supported. |
| Meta documentation | Meta API versions, access tiers, permissions, test-asset availability, and endpoint behavior can change. | Version and permission claims are release-time inputs. Tests use fixtures; every live run must recheck official Meta documentation first. |
| Security workflow | The available source-security workflow separates deterministic secret, gitleaks, SAST, dependency, supply-chain, harness, triage, and adversarial passes. | Release acceptance requires traceable output from each applicable method and closure of every verified high or medium finding. |

## 3. Goals and Non-goals

### Goals

- Ship distinct reader and writer Swift client types and CLI products with a
  shared core, while keeping writer APIs out of the reader client's public
  surface and writer routes out of the reader executable.
- Provide predictable human help and stable machine-readable JSON envelopes,
  exit codes, dry-run behavior, and redacted diagnostics.
- Expose generic Graph operations through a fixed Meta origin, a centrally
  selected API version, relative paths, closed headers, bounded inputs, and
  capability-specific clients.
- Make writer execution two-phase and fail closed: generic planning is offline;
  typed preview may perform only declared read observations after local
  validation; mutation apply requires an exact reviewed artifact and runs only
  through the writer executable.
- Achieve broad deterministic coverage with injected transports, clocks,
  randomness, file systems, credential resolvers, and non-secret fixture data.
- Document Kinko-only setup and commands without ever teaching `.env` or inline
  secret patterns.
- Produce reproducible SwiftPM builds and locally verifiable release archives,
  checksums, SBOM/provenance inputs, and Homebrew metadata without publishing.
- Require secret scanning, static analysis, dependency/supply-chain review, and
  independent adversarial review before release acceptance.

### Non-goals

- Storing, refreshing, exporting, printing, debugging, or backing up Meta
  credential material.
- Supporting caller-selected URL schemes, hosts, ports, proxy destinations,
  authorization headers, cookies, or arbitrary transport headers.
- Automatically discovering or choosing production ad accounts.
- Performing paid delivery, creating billable campaigns, or using production
  assets as part of normal tests or release verification.
- Publishing a GitHub release, Homebrew formula/cask, package registry version,
  or deployment in this workflow.
- Promising a current Graph/Marketing API version or sandbox feature beyond the
  official-documentation recheck date.

## 4. SwiftPM and Product Boundaries

The package uses Swift tools version 6 and targets macOS 14 or later. Exact
names align with the accepted Graph foundation and typed-domain plans:

| Product/target | Visibility and responsibility |
|---|---|
| `MetaMarketingGatewayCore` | Library target containing shared request/transport primitives plus distinct public `MetaGraphReader`/`MetaMarketingReader` and `MetaGraphWriter`/`MetaMarketingWriter` capability types. Shared execution internals are not public escape hatches. |
| `MetaMarketingGatewayReader` | Executable target/product `meta-marketing-gateway-reader`; composition exposes generic and typed reads and contains no writer CLI route or mutation executor entry point. |
| `MetaMarketingGatewayWriter` | Executable target/product `meta-marketing-gateway-writer`; composition owns generic and typed mutation preview/plan/apply and may use readers for preflight or reconciliation. |
| `MetaMarketingGatewayCoreTests` | Contract, capability, CLI, transport, redaction, URL, file, plan/journal, and adversarial tests, split into focused files by responsibility. |

Prefer `swift-argument-parser` from Apple's official repository for generated
help and parser correctness if the shared CLI implementation adopts a package
dependency. Pin any adopted release exactly in `Package.swift` and
`Package.resolved`. A dependency-free parser is acceptable only if its behavior
has equivalent parser, help, and adversarial coverage. Add no runtime package
dependency without a documented need, license check, dependency audit, and
supply-chain review.

The release binary names stay separate. There is no combined executable or
mode flag that could accidentally promote a reader process into writer mode.
Distinct public client types cannot downcast to shared transport or to the other
capability. Package/API review verifies this type boundary; CLI routing and
binary smoke tests verify the executable boundary.

## 5. CLI Contract

### 5.1 Global behavior

Both executables support `--help`, `--version`, a dedicated validated
`--api-version v<major>.<minor>` option for network commands,
`--output json|jsonl`, `--request-id`, and bounded timeout/retry flags.
Human-readable output is for terminal use; JSON/JSONL is the stable automation
contract. Machine envelopes
contain `ok`, `operation`, `requestId`, `apiVersion`, `data` or `error`, and
safe pagination/rate-limit metadata. They never contain environment snapshots,
credentials, raw authorization material, raw provider error bodies, or complete
request URLs.

Exit codes are stable:

| Code | Meaning |
|---:|---|
| 0 | Success or successfully generated offline plan. |
| 2 | CLI syntax or local validation failure. |
| 3 | Missing/invalid credential reference after local validation. |
| 4 | Safe provider rejection, including permission or rate limit. |
| 5 | Transport/timeout failure. |
| 6 | Writer plan, confirmation, stale-plan, policy, or spend-gate rejection. |
| 70 | Sanitized internal error. |

Validation order is parser -> local schema/bounds -> capability/policy -> plan
integrity -> credential resolution -> transport. Help, version, plan, invalid
input, and rejected operations do not resolve credentials.

### 5.2 Reader commands

The reader has these top-level groups:

```text
meta-marketing-gateway-reader graph get --api-version vNN.N ...
meta-marketing-gateway-reader ads <typed-domain> <read-operation> ...
meta-marketing-gateway-reader catalog list ...
meta-marketing-gateway-reader auth status
```

`graph get` accepts a supported explicit API version through the dedicated
option, a single relative Graph node/edge path, declared query
parameters, field selection, and pagination controls. It does not accept a URL,
origin, scheme, port, HTTP method, header, token, app secret, cookie, or version
embedded in the path. The version is validated centrally and cannot alter the
origin or escape the first path segment. Typed reporting operations that legitimately use `POST`
remain typed reader APIs; the generic reader command is GET-only so an unknown
future mutation cannot be smuggled through a reader process.

Pagination returns validated cursors or an opaque next-page token. Provider
`paging.next` URLs are never followed directly and never printed: the client
extracts only allowlisted cursor data and reconstructs the next request through
the same fixed-origin builder.

### 5.3 Writer commands

The writer has typed domain routes and generic Graph planning:

```text
meta-marketing-gateway-writer graph post|delete --api-version vNN.N ... --plan <secure-file>
meta-marketing-gateway-writer graph post|delete --apply <secure-plan> --confirm <full-digest>
meta-marketing-gateway-writer ads <typed-domain> preview --request <secure-file>
meta-marketing-gateway-writer ads <typed-domain> apply --preview <secure-file> --confirm <full-digest>
```

Generic `--plan` and typed `preview` perform no credential lookup and no
mutation. A typed preview may make an explicitly labeled reader preflight only
when its descriptor requires current state. The resulting secure artifact is a
mode-0600, canonical JSON plan containing only non-secret intent: schema
version, operation id, API version, method, normalized relative path, canonical
query/body digest, resource identifiers, risk class, estimated spend delta when
applicable, creation/expiry time, and confirmation digest. Secret values,
authorization, `appsecret_proof`, response data, and environment names are not
stored.

Generic `--apply` and typed `apply` reopen the plan with no-follow semantics,
verify owner/mode/type, size, canonical encoding, digest, expiry, repository
schema/version, exact full confirmation digest, and policy before resolving
credentials. The executor
reconstructs the request; it never trusts a full URL or headers from the file.
Raw body values and file contents are never copied into the plan. The separate
secure request file is bound by identity, size, and digest and rechecked at
apply; typed previews expose only explicitly safe summaries.

Generic writer operations are intentionally available for future endpoints but
are never unconstrained:

- method is only `POST` or `DELETE`; typed APIs may add other reviewed verbs;
- origin is exactly `https://graph.facebook.com` and is not an input;
- API version comes from the package's supported-version policy, not the path;
- path is relative, normalized once, length/segment bounded, and rejects empty
  segments where unsafe, dot segments, encoded separators, userinfo, controls,
  fragments, backslashes, absolute/protocol-relative URLs, and host-like input;
- query/body sizes, JSON depth, scalar lengths, and collection counts are
  bounded; duplicate or ambiguous keys are rejected;
- authorization, access token, app secret, `appsecret_proof`, cookies, host,
  method override, and forwarding/proxy fields are rejected in all user input;
- apply defaults to denied for billing, access control, account deletion,
  payment, funding, budget increase, publish/activate, or unknown spend impact
  until a typed reviewed policy explicitly allows it;
- retries are disabled for non-idempotent writes unless a typed operation has a
  provider-supported idempotency contract or safe reconciliation strategy.

## 6. Credentials and Kinko Boundary

Credential material exists only in Kinko and, for the lifetime of one child
process, its explicitly allowlisted environment. The documented production
keys are:

| Key | Use | Output/storage rule |
|---|---|---|
| `META_ACCESS_TOKEN` | Bearer token for Graph requests. | Required for network operations; never accepted as an argument or serialized. |
| `META_APP_SECRET` | Optional server-side derivation of `appsecret_proof` when policy requires it. | Never sent directly, logged, or persisted. |
| Descriptor-approved command key | Optional additional secret such as a reviewed upload-session credential. | Must be centrally allowlisted, explicitly named in `kinko exec --env`, command-scoped, and treated exactly like other secrets. |

Non-secret resource identifiers may be supplied as CLI input. Configuration may
name which environment keys are expected, but cannot contain credential values,
secret aliases that resolve outside Kinko, shell expressions, or fallback
values.

Documentation uses only this invocation shape:

```bash
kinko exec --env META_ACCESS_TOKEN -- \
  swift run meta-marketing-gateway-reader graph get \
  --api-version vNN.N --path me --fields id
```

Commands that need fewer keys use a smaller allowlist. Never document `--all`,
`.env`, `export`, inline assignments, token arguments, shell interpolation,
`kinko get`, `kinko show`, or redirection of credential output. The gateway
must not enumerate the environment, spawn diagnostic subprocesses with secrets,
or copy credential strings into long-lived tasks, crash reports, receipts, or
debug descriptions. Derived `appsecret_proof` is handled as credential material
and zeroized on a best-effort basis after request construction.

## 7. Network, Error, and Data Safety

- The only production API origin is the exact HTTPS host
  `graph.facebook.com`; redirects are disabled. A separately reviewed upload
  host may be added only when official endpoint documentation requires it and
  the operation has a fixed host policy.
- TLS verification uses platform defaults; no trust-all mode, custom CA CLI
  flag, HTTP downgrade, arbitrary proxy target, or redirect following exists.
- Authorization uses the `Authorization` header. URL/query rendering redacts
  access tokens, `appsecret_proof`, signed requests, and secret-like parameters.
- Provider errors are decoded into an allowlist of safe fields such as HTTP
  status, Meta error code/subcode, transient flag, safe category, trace id, and
  operation id. Provider messages and raw bodies are not emitted by default.
- Response/request bytes are bounded. Large insights and export results stream
  to an owner-only file using atomic creation, a maximum byte count, and a
  non-secret receipt; partial files are deleted or clearly marked incomplete.
- Every request receives an internal correlation id. User-provided request ids
  are charset/length bounded and never become a header without canonicalization.
- Logs are structured, disabled for bodies and headers, and safe at every level.
  A debug flag may increase timing/state diagnostics but never relax redaction.

## 8. Test Strategy

### 8.1 Deterministic layers

1. Pure unit tests cover path normalization, version selection, canonical JSON,
   field/query encoding, bounds, redaction, error projection, risk policy,
   confirmation, expiry, and spend arithmetic.
2. Request-contract tests use an injected recording transport and assert exact
   method/host/path/query/header/body shape without network access.
3. CLI tests invoke parsers/dispatch in process with recording credential and
   transport adapters. They assert validation-before-credentials and stable
   stdout/stderr/exit envelopes.
4. File tests use fresh temporary directories and cover mode, owner, symlink,
   non-regular file, replacement race, size, JSON depth, digest, and atomicity.
5. End-to-end mock tests use a loopback-only server or injected transport with
   scripted pagination, async insights polling, throttling, transient failures,
   malformed responses, and partial streams.
6. Packaging tests build release configuration, inspect linked products, run
   help/version smoke tests, unpack archives, verify checksums/SBOM inputs, and
   prove the reader archive cannot dispatch writer commands.

Fixtures contain obviously synthetic ids and generated canaries such as
`TEST_SECRET_CANARY_<random>` supplied at test runtime. No fixture resembles a
real Meta token, app secret, email, business id, ad account, or private URL.
Golden files are limited to sanitized JSON and request shapes.

### 8.2 Adversarial matrix

Tests must include:

- absolute, protocol-relative, encoded-host, userinfo, mixed-case host,
  suffix-host, port, fragment, dot-segment, double-encoded, Unicode confusable,
  null/control, CRLF, backslash, oversized, and traversal path inputs;
- duplicate query keys, nested token-like fields, method override, header
  smuggling, content-type confusion, decompression/response bombs, and malformed
  UTF-8/JSON;
- credential canaries in arguments, environment, URLs, headers, bodies,
  provider messages, errors, retries, receipts, debug descriptions, and crashes,
  with absence asserted across stdout, stderr, logs, plans, and artifacts;
- reader attempts to call POST/DELETE, writer apply without a plan, altered or
  stale plans, mismatched body digest, insecure/symlinked plan files, confirmation
  mismatch, concurrent replay, ambiguous retry, and spend overflow/rounding;
- redirects, DNS/host substitution through crafted input, pagination next-URL
  poisoning, rate-limit header abuse, cancellation, timeout, and partial writes;
- arbitrary decoded JSON fields and unknown provider error shapes, proving they
  cannot reach logs or stable output without an explicit allowlist.

Fuzz/property tests target path and query normalization, JSON depth/size,
canonical plan encoding, redaction, and decoder resilience. A corpus of each
fixed regression remains in the repository with non-secret inputs.

### 8.3 Meta test assets and live checks

Local mocks are authoritative for CI. If a live check becomes necessary, first
recheck official Meta documentation for current Graph/Marketing API versions,
permissions, access tiers, and available sandbox/test assets. Use
`taco-dev-sandbox@mutvar.com` for interactive Meta setup and prefer a Meta
sandbox/test ad account and non-delivering assets.

Default live smoke tests are read-only and zero-spend. The accepted v1 writer
policy denies live spend effects and authorizes USD 0. A future separately
reviewed live writer test would require user approval, a recorded asset/account
allowlist, a preview, an immediate cleanup plan, and an enforced aggregate
ceiling strictly below USD 20 for the entire workflow. Unknown spend impact
fails closed. Billable campaign creation is never a release prerequisite.

## 9. Documentation Contract

Implementation produces:

- `README.md`: supported products, reader/writer boundary, quick start, safe
  Kinko command, current limitations, and links to detailed docs;
- `SECURITY.md`: threat model, supported versions, private reporting process,
  credential rules, redaction guarantees, and response expectations;
- `docs/cli.md`: complete generated command/help examples, JSON schema, exit
  codes, plan/apply flow, pagination, and safe error behavior;
- `docs/authentication.md`: Kinko-only key setup and minimal `--env` allowlists,
  without secret retrieval or `.env` alternatives;
- `docs/testing.md`: mocks, fixtures, sandbox/test-asset policy, live-test gate,
  canary rules, and spend ceiling;
- `docs/releasing.md`: local archive/checksum/SBOM/verification flow and the
  explicit separately authorized publish step;
- `CHANGELOG.md`, `LICENSE`, `CONTRIBUTING.md`, and API documentation generated
  from public Swift declarations.

Every mutable Meta claim includes an official Meta source URL and checked date.
The implementation must recheck, not silently copy, version/access/test-asset
claims at release time. Starting points checked for this design are Meta's
Marketing API overview, Graph API versioning, rate limiting, error handling,
request security, and official Business SDK repository:

- <https://developers.facebook.com/documentation/ads-commerce/marketing-api/overview>
- <https://developers.facebook.com/docs/graph-api/guides/versioning>
- <https://developers.facebook.com/docs/graph-api/overview/rate-limiting/>
- <https://developers.facebook.com/docs/graph-api/guides/error-handling/>
- <https://developers.facebook.com/docs/graph-api/guides/secure-requests/>
- <https://github.com/facebook/facebook-python-business-sdk>

The URLs are sources, not hardcoded assertions that a particular endpoint,
permission, or sandbox feature is currently available.

## 10. Packaging and Release Artifacts

SwiftPM is the source package. Development tasks are exposed through `mise` but
all essential verification also has direct `swift` equivalents. The package
commits `Package.resolved` for executable reproducibility and records Swift,
macOS, Xcode, dependency, and artifact versions.

A local release build creates, without publishing:

- separate versioned archives for reader and writer binaries per supported
  macOS architecture, each containing `LICENSE`, notices, and completion files;
- SHA-256 checksums and a manifest mapping source revision, toolchain,
  dependency lock digest, artifact digest, and build command;
- SPDX or CycloneDX SBOM covering SwiftPM and packaged files;
- generated API documentation and a Homebrew formula template referencing the
  final archive/checksum without embedding credentials or machine-local paths;
- provenance input suitable for later signed attestations. Signing,
  notarization, upload, tap modification, and publication are separate,
  explicitly authorized operations.

Artifacts are assembled in a fresh temporary directory. Archive member paths
are normalized and inspected for traversal, symlinks, secrets, `.env`, build
cache, source-control metadata, private URLs, and absolute machine paths.
Rebuilding the same revision/toolchain should produce identical content or a
documented nondeterministic-field exception that is removed before acceptance.

## 11. Security Gates

Release acceptance is fail-closed and ordered:

1. Diff scope, generated-file, license, and documentation review.
2. Format/lint, strict-concurrency build, full tests, fuzz corpus, release-build,
   archive inspection, and reader/writer separation smoke tests.
3. Repository secret-pattern scan and `gitleaks detect --no-git --redact`.
   Missing gitleaks is a coverage gap, not a pass.
4. Deterministic SAST and manual review of URL construction, redirects,
   credentials, logging, file handling, subprocesses, plan replay, arithmetic,
   decoding, concurrency, and error boundaries.
5. Dependency vulnerability/license audit, lockfile review, package-source
   verification, CI pinning, build-script review, SBOM review, and
   supply-chain/config scan. Network audits run only when explicitly enabled.
6. Threat-model/harness recon followed by repository-specific triage.
7. Independent adversarial verification that deduplicates and reranks findings.
8. Fix every verified high or medium finding, rerun all deterministic methods,
   and document accepted low findings as residual risk with an owner and review
   date.

No stage, commit, push, release, publish, deploy, or live billable operation is
part of a gate. Security reports and command transcripts must be redacted and
must not capture the injected environment.

## 12. Decisions

| Decision | Rationale |
|---|---|
| Separate public client types and executable routes. | The accepted foundation keeps shared execution in one core target; type capability and executable routing together prevent a CLI mode flag from upgrading reader behavior. |
| Keep generic reader GET-only and generic writer two-phase. | Supporting future endpoints is required, but verb/effect ambiguity and accidental mutation demand a conservative capability boundary. |
| Fix origin and select API version outside user path input. | This preserves endpoint breadth without creating an arbitrary proxy, SSRF primitive, or version-policy bypass. |
| Use Kinko-injected environment values only. | It satisfies the sole-store constraint while keeping credentials outside files, arguments, shell history, and repository state. |
| Make mocks authoritative and live tests optional. | CI needs deterministic, non-billable coverage; Meta access tiers and test assets are external and mutable. |
| Generate local release artifacts before any publish decision. | Artifact correctness and security can be reviewed without external state changes. |
| Treat a missing scanner/auditor as a coverage gap. | Silent tool absence cannot satisfy a security gate. |
| Prefer one exactly pinned official CLI dependency, or prove equivalent dependency-free behavior. | Generated help is valuable, while a narrow reviewed dependency surface limits supply-chain risk. |

## 13. Risks and Mitigations

| Risk | Severity | Mitigation |
|---|---:|---|
| Generic Graph routing becomes arbitrary HTTP or a reader mutation path. | High | Fixed origin/version, relative normalized path, closed headers, GET-only generic reader, two-phase writer, adversarial URL tests. |
| Credentials leak through CLI, plans, logs, errors, paging URLs, crash output, or release artifacts. | High | Kinko-only injection, no secret input flags/files, bearer headers, safe-field projections, canary tests, artifact inspection, secret/gitleaks gates. |
| Writer replay/retry creates duplicate durable or billable effects. | High | Canonical expiring plan, exact confirmation, replay guard, no blind retry, typed reconciliation/idempotency, spend-risk denylist. |
| Reader and writer implementation drift weakens separation. | High | Separate products/targets, dependency-direction tests, reader archive smoke tests, no combined executable. |
| Meta versions, permissions, rate limits, and sandbox/test assets change. | Medium | Official-doc checked dates, single version policy, fixture versioning, release-time recheck, no live test as acceptance dependency. |
| Dependency or release automation is compromised. | High | Minimal exact dependency, lock/source review, pinned CI actions, SBOM, supply-chain scan, provenance, publish kept separate. |
| Secret scan fixtures cause false positives or real-looking examples normalize unsafe practice. | Medium | Generate canaries at runtime, use unmistakably synthetic placeholders, manually classify every scan match. |
| Archive reproducibility differs across Apple toolchains. | Medium | Record toolchain and manifest, normalize metadata, compare two local builds, document and eliminate variable fields. |

## 14. Design Review Record

### Self-review

Decision: **accepted after corrections**.

- High design defect: a fully generic Graph request could bypass origin and
  reader/writer controls. Addressed by fixed-origin/version construction,
  GET-only generic reader, and guarded writer plan/apply.
- High design defect: accepting tokens as ordinary CLI/config input would
  violate Kinko-only storage and expose shell history. Addressed by removing all
  credential arguments/files/stdin and documenting only minimal `kinko exec
  --env` allowlists.
- Medium design defect: following Meta `paging.next` directly could bypass the
  fixed-origin builder or print token-bearing URLs. Addressed by cursor-only
  extraction and local request reconstruction.
- Medium design defect: release tests could depend on mutable Meta sandbox
  support. Addressed by authoritative mocks and a separately approved,
  official-doc-rechecked live gate.

### Independent review pass

Decision: **accepted after corrections; no open high or medium findings**.

- High design defect: plan/apply initially needed explicit tamper, expiry,
  secure-file, replay, and ambiguous-retry rules. Those requirements are now in
  Sections 5.3, 8, and 11.
- Medium design defect: package separation needed enforceable API and routing
  boundaries, not only distinct command names. Cross-feature reconciliation showed the accepted
  foundation uses one shared core target, so Section 4 now makes distinct public
  capability types and executable routing/smoke tests the enforceable boundary.
- Medium design defect: secret scanning alone omitted dependency, build-chain,
  archive, and adversarial coverage. Section 11 now defines all deterministic
  and independent gates and treats missing tools as gaps.
- Medium design defect: the first draft diverged from sibling contracts on CLI
  version selection, generic writer command shape, plan body contents, and the
  base Kinko key set. Sections 5 and 6 now use a dedicated validated
  `--api-version`, `graph post|delete --plan/--apply`, body-free plans, and the
  shared access-token/app-secret contract with descriptor-approved extensions.

Plan-only concerns are intentionally deferred to the implementation plan:
concrete file ownership, task ordering, progress checkboxes, exact completion
criteria, and executable verification commands.

## 15. Design Verification

```bash
test -f design-docs/meta-gateway-delivery-security.md
rg -n "Kinko|kinko exec --env|reader|writer|gitleaks|USD 20|Independent review" \
  design-docs/meta-gateway-delivery-security.md
git diff --check -- design-docs/meta-gateway-delivery-security.md
git diff --no-index -- /dev/null design-docs/meta-gateway-delivery-security.md
```
