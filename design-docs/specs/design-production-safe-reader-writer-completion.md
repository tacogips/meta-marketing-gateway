# Production-Safe Reader and Writer Completion

**Issue reference:** `inline-workflow:codex-design-and-implement-review-loop-session-745`

**Workflow mode:** `issue-resolution`

**Review mode:** `adversarial`

**Risk:** `critical`

**Status:** Proposed for Step 3 review

**Contract review date:** 2026-08-15

**Codex-agent references:** None supplied

**Behavioral reference:** `../google-marketing-gateway`

## 1. Outcome and precedence

This design completes the gateway as two capability-separated products: an
evolving, read-only Meta Graph/Marketing API client and a production-composed
writer that can express mutations but sends bytes only after every durable,
identity, asset, authorization, reconciliation, credential, and USD 0 gate has
passed.

This document is the issue-specific authority when an older design or plan
conflicts with it. In particular, every earlier sub-USD-20 statement is
superseded: this workflow and the resulting first production policy authorize
exactly USD 0. Existing journal/authentication hardening in
`design-docs/specs/design-mutation-authorization-journal-authentication.md`
remains required unless this document is stricter.

The current source is a useful safety foundation, not the requested production
result. The reader exposes 11 typed operations over ad accounts, campaigns, ad
sets, ads, ad creatives, and insights. The writer executable constructs
`MetaGraphWriter` without apply dependencies, so every apply fails closed. That
is safe but is not production composition. The repository contains 76 XCTest
methods, which is the preservation baseline.

## 2. Official contract ledger

Only official Meta sources support mutable provider claims. The following pages
were rechecked on 2026-08-15:

- [Marketing API overview](https://developers.facebook.com/documentation/ads-commerce/marketing-api/overview)
- [Graph API versioning](https://developers.facebook.com/docs/graph-api/guides/versioning/)
- [Ad-account campaign edge](https://developers.facebook.com/documentation/ads-commerce/marketing-api/reference/ad-account/campaigns)
- [Ad-account ad-set edge](https://developers.facebook.com/documentation/ads-commerce/marketing-api/reference/ad-account/adsets)
- [Ad-account ad edge](https://developers.facebook.com/documentation/ads-commerce/marketing-api/reference/ad-account/ads)
- [Ad-account ad-creative edge](https://developers.facebook.com/documentation/ads-commerce/marketing-api/reference/ad-account/adcreatives)
- [Marketing API sandbox](https://developers.facebook.com/documentation/ads-commerce/marketing-api/sandbox/)
- [Graph API results and pagination](https://developers.facebook.com/docs/graph-api/results/)
- [Graph API secure requests](https://developers.facebook.com/docs/graph-api/guides/secure-requests/)

The four inspected Ads reference pages currently declare `v25.0`, not
`v26.0`, as their current reference version. The repository's typed matrix,
fixtures, tests, and README currently claim `v26.0`; they must not be presented
as an authoritative current contract. Typed operations remain fail-closed until
their single catalog authority is changed to a currently documented version and
its fields and fixtures are revalidated. The initial reviewed version for this
rollout is `v25.0`.

The campaign, ad-set, and ad creation references show `status=PAUSED` examples.
That supports a stricter gateway invariant: typed creation fixes `status` to
`PAUSED`, rejects caller attempts to provide another status through any carrier,
and never offers `ACTIVE` creation or transition. Ad-creative creation is not a
serving operation by itself, but it is still account-bound and proof-gated.

The official sandbox page establishes a provider sandbox surface, but the
public contract reviewed here does not establish one universal response field
that proves an arbitrary target account is non-billable for every mutation
family. Therefore no operation inherits test eligibility merely from an ID,
name, caller flag, fixture, or mock. Each writer operation remains individually
fail-closed, but its reason is precise: policy-prohibited operations are
`denied`; operations lacking a complete reviewed mutation, principal-identity,
or reconciliation contract are `blockedVersionReview`; only an operation whose
other contracts and policy are complete but whose remaining gap is
machine-verifiable test/non-billable asset proof is `blockedProviderProof`.
This is an evidence gap, not a claim that Meta lacks all test facilities.

Every catalog entry records its official URLs and `lastReviewed=2026-08-15`.
Changing a version, field, path, permission, proof strategy, or status behavior
requires a new dated review and fixture update.

## 3. Capability boundaries and package shape

The package has four runtime boundaries, one build-only catalog toolchain, and
no combined executable:

| Boundary | Allowed responsibility | Forbidden responsibility |
|---|---|---|
| Shared Graph core | Relative paths, canonical query/body values, version ledger, fixed-origin URL creation, bounded sanitized responses. | Credentials, mutation policy decisions, raw all-method transport, CLI dispatch. |
| Reader client and executable | Typed Ads reads, generic relative-path `GET`, reader-only batch semantics, local catalog discovery. | Mutation verbs, mutation credentials, writer policy/downcast, plan/apply/reconcile. |
| Writer client and executable | Typed and generic plan/confirm/apply, exact-operation policy, provider verification, durable state, reconciliation. | Reader escape hatches, direct execute, implicit operation descriptors, unclassified send. |
| Trusted-head broker | Local Unix-domain read/compare-and-set service over broker-owned durable heads. It runs under a distinct OS identity and is packaged only with the writer. | Graph credentials, mutation bodies, journal access, arbitrary replacement/deletion, reader linkage, or network listeners. |
| Build-only catalog toolchain | Validate one canonical manifest and emit capability-specific Swift source and documentation projections. | Runtime products, network access, credentials, dispatch, or inclusion of the manifest/generator in release archives. |

### 3.1 SwiftPM ownership and compile-time catalog projections

`Package.swift` must declare these exact target ownership boundaries:

| Target | Source ownership | Direct dependencies and generated input |
|---|---|---|
| `MetaGraphPrimitives` | `Sources/MetaGraphPrimitives/`: Graph version/path validation, canonical scalar/query/body values, fixed-origin URL construction, bounded sanitized envelopes. It owns no URL session, credential, catalog, CLI, Ads model, dispatch, or mutation type. | Foundation only. |
| `MetaMarketingGatewayReaderKit` | `Sources/MetaMarketingGatewayReaderKit/`: reader Ads models/filters, typed reader, generic `GET`, GET-only transport, pagination/batch, `ReaderCapabilityCatalog`, and `ReaderCLI`. | `MetaGraphPrimitives` plus build-plugin output `GeneratedReaderCapabilityCatalog.swift`. |
| `MetaMarketingGatewayWriterKit` | `Sources/MetaMarketingGatewayWriterKit/`: writer request models, plan/confirmation, exact policy, principal/asset verification, journal, reconciliation, Kinko environment adapter, a closed GET transport usable only by cataloged verification/reconciliation adapters, mutation transport, `WriterCapabilityCatalog`, broker client, and `WriterCLI`. It exposes no generic reader API. | `MetaGraphPrimitives`, `MetaTrustedHeadProtocol`, plus build-plugin output `GeneratedWriterCapabilityCatalog.swift`; never `MetaMarketingGatewayReaderKit`. |
| `MetaTrustedHeadProtocol` | `Sources/MetaTrustedHeadProtocol/`: bounded versioned request/response and head/CAS value types only. | Foundation only; no Graph or journal dependency. |
| `MetaMarketingGatewayReaderCommand` | `Sources/MetaMarketingGatewayReader/main.swift`: construct only `ReaderCLI`, render its sanitized envelope, return its exit status. | `MetaMarketingGatewayReaderKit` only. |
| `MetaMarketingGatewayWriterCommand` | `Sources/MetaMarketingGatewayWriter/main.swift`: construct only `WriterCLI` and production writer dependencies, render its sanitized envelope, return its exit status. | `MetaMarketingGatewayWriterKit` only. |
| `MetaMarketingGatewayTrustedHeadBroker` | `Sources/MetaMarketingGatewayTrustedHeadBroker/`: peer authentication, Unix-domain protocol server, broker-owned persistence, and CAS. | `MetaTrustedHeadProtocol` only. |
| `MetaCapabilityCatalogGenerator` | `Sources/MetaCapabilityCatalogGenerator/`: strict manifest decoding, cross-row validation, deterministic reader/writer/doc projection. | Build tool only; Foundation only. |
| `MetaCapabilityCatalogPlugin` | `Plugins/MetaCapabilityCatalogPlugin/plugin.swift`: invoke the generator for the attached reader or writer target. | Build-tool dependency on `MetaCapabilityCatalogGenerator`; never a runtime dependency. |

Public product-to-target mapping is fixed:

| Product | Sole target |
|---|---|
| Library `MetaMarketingGatewayReader` | `MetaMarketingGatewayReaderKit` |
| Library `MetaMarketingGatewayWriter` | `MetaMarketingGatewayWriterKit` |
| Executable `meta-marketing-gateway-reader` | `MetaMarketingGatewayReaderCommand` |
| Executable `meta-marketing-gateway-writer` | `MetaMarketingGatewayWriterCommand` |
| Executable `meta-marketing-gateway-trusted-head-broker` | `MetaMarketingGatewayTrustedHeadBroker` |

There is no `MetaMarketingGatewayCore` product. The generator and plugin are
not products. Test targets mirror ownership:
`MetaGraphPrimitivesTests`, `MetaMarketingGatewayReaderKitTests`,
`MetaMarketingGatewayWriterKitTests`, `MetaTrustedHeadBrokerTests`, and
`MetaCapabilityCatalogGeneratorTests`.

`Catalog/meta-capabilities.json` is the sole catalog authority. It is not a
SwiftPM resource and is never copied or linked into a runtime target. Every
operation row has exactly one surface, `reader` or `writer`; shared domains use
separate operation IDs rather than a `both` row. The build plugin invokes the
generator with a fixed surface determined from the attached target, never from
a runtime argument:

- the reader projection contains only reader operation IDs, `GET` methods,
  reader implementation/availability data, reviewed versions/paths, and public
  source metadata; its generated Swift types have no mutation effect,
  confirmation, provider-proof, reconciliation, or authorization fields;
- the writer projection contains only writer operation IDs and the complete
  closed mutation policy, proof, reconciliation, review, and USD 0 fields; and
- the documentation projection targets the committed
  `docs/capabilities.md`, is generated in check mode from the same manifest,
  and cannot change runtime artifacts.

The generated files are compiled directly into their owning kit. Catalog CLI
commands enumerate their kit's static generated projection; no runtime surface
filter parses or carries the full manifest. The plugin and generator may read
the full manifest during the build but are not linked into either executable.
The plugin declares `Catalog/meta-capabilities.json` as an input and the one
surface-specific Swift file as its output so manifest changes invalidate both
kit builds. Generation fails on duplicate IDs, `both`, reader mutation fields
or non-GET methods, incomplete writer policy, invalid sources/review dates, or
unstable sort. Capability-specific tests and exhaustive generated operation-ID
types—not the generator inspecting Swift source—fail on catalog/dispatch
mismatch.

The compile-time dependency graph is:

```text
MetaMarketingGatewayReaderCommand -> MetaMarketingGatewayReaderKit -> MetaGraphPrimitives
MetaMarketingGatewayWriterCommand -> MetaMarketingGatewayWriterKit -> MetaGraphPrimitives
                                                        \-> MetaTrustedHeadProtocol
MetaMarketingGatewayTrustedHeadBroker --------------------> MetaTrustedHeadProtocol
MetaMarketingGatewayReaderKit ..build only..> MetaCapabilityCatalogPlugin
MetaMarketingGatewayWriterKit ..build only..> MetaCapabilityCatalogPlugin
MetaCapabilityCatalogPlugin ..build only..> MetaCapabilityCatalogGenerator
MetaCapabilityCatalogGenerator ..input only..> Catalog/meta-capabilities.json
```

There is no reader runtime or link dependency path to writer kit, writer
CLI/policy/transport, trusted-head protocol, broker, generator, or canonical
manifest. ReaderKit has only the explicitly shown build-tool edge; plugin,
generator, and manifest bytes never enter its module or product. A
`GraphReading` capability cannot accept mutation methods, and writer transport
is not publicly recoverable from primitives. Package-graph tests plus reader
archive symbol/string inspection enforce this boundary.

The Google gateway is a behavioral and structural reference for product
separation, catalog discovery, deterministic CLI envelopes, and release
artifact checks. Meta-specific Graph paths, access-token behavior, sandbox
evidence, and mutation policy are designed here and are not copied from Google.
Unlike the reference package, this critical-risk gateway has no compatibility
or admin executable and splits reader and writer library targets instead of
placing both capabilities in one public library. It adds one private
infrastructure executable, `meta-marketing-gateway-trusted-head-broker`, to the
writer archive only; that broker exposes no marketing or administrative route.

### 3.2 Concrete Google reference mapping

Reference paths below are relative to this repository. They are behavioral
inputs, not files to copy:

| Reference artifact | Observed reusable behavior | Meta target and intentional divergence |
|---|---|---|
| `../google-marketing-gateway/Package.swift` | Named core library plus thin, mode-specific executable targets. | Replace the current all-capabilities `MetaMarketingGatewayCore` product with the exact target graph in Section 3.1. Do not reuse the reference compatibility/admin products or its one public all-capabilities core. |
| `../google-marketing-gateway/Sources/GoogleMarketingGatewayCore/OperationCatalog.swift` | One encoded catalog combines implemented and planned inventory; validation requires complete metadata and fixed HTTPS origins; dispatch lookup excludes non-implemented rows. | Preserve deterministic validation concepts in build-only `Catalog/meta-capabilities.json`, `Sources/MetaCapabilityCatalogGenerator/`, and `Plugins/MetaCapabilityCatalogPlugin/`. Emit separate reader/writer projections; never place the full or writer-aware catalog in `MetaGraphPrimitives` or the reader target. |
| `../google-marketing-gateway/Sources/GoogleMarketingGatewayCore/GatewayCLI.swift` | Mode-bound help/version/catalog run before credential access; reader input and operation/profile compatibility are validated before token resolution; unknown writer routes fail closed. | Split current `Sources/MetaMarketingGatewayCore/GatewayCLI.swift` into `Sources/MetaMarketingGatewayReaderKit/ReaderCLI.swift` and `Sources/MetaMarketingGatewayWriterKit/WriterCLI.swift`. Keep local help/catalog and pre-credential validation, while writer-only production composition and Kinko injection remain absent from reader linkage. |
| `../google-marketing-gateway/Sources/GoogleMarketingGatewayReader/main.swift` and `../google-marketing-gateway/Sources/GoogleMarketingGatewayWriter/main.swift` | Thin mains select one capability mode and write only the returned stdout/stderr envelope and exit code. | Keep `Sources/MetaMarketingGatewayReader/main.swift` and `Sources/MetaMarketingGatewayWriter/main.swift` thin and capability-fixed. They may not construct or downcast the other client. |
| `../google-marketing-gateway/Sources/GoogleMarketingGatewayCompatibility/main.swift` and `../google-marketing-gateway/Sources/GoogleMarketingGatewayAdmin/main.swift` | Compatibility delegates to reader; admin is a separate mode. | Intentionally do not add Meta equivalents. Compatibility broadens the public surface, and trusted-head repair is not an ordinary admin command in v1. |
| `../google-marketing-gateway/Tests/GoogleMarketingGatewayCoreTests/OperationCatalogTests.swift` | Catalog metadata, fixed origins, planned inventory, and non-dispatchability are executable invariants. | Put manifest/projection validation in `Tests/MetaCapabilityCatalogGeneratorTests/`; put reader catalog/dispatch tests in `Tests/MetaMarketingGatewayReaderKitTests/` and writer policy/dispatch tests in `Tests/MetaMarketingGatewayWriterKitTests/`. |
| `../google-marketing-gateway/Tests/GoogleMarketingGatewayCoreTests/GatewayCLITests.swift` | Negative option tests, token non-echo, mode routing, profile/product isolation, and sanitized provider failures. | Split these categories between reader-kit and writer-kit tests. Substitute exact Meta bindings and Kinko-only environment names; never copy token fixtures or OAuth profile behavior. |
| `../google-marketing-gateway/scripts/build-homebrew-release.sh` | Validates version/target/output paths, builds a selected product, generates checksums, and states that build does not publish. | Keep the same validation/no-publish properties in `scripts/build-local-archives.sh`; build separate reader and writer archives, include the broker only in the writer archive, and retain SBOM/provenance/checksum output without adding Homebrew publication. |
| `../google-marketing-gateway/scripts/build-homebrew-cask-release.sh` | Separates dry-run planning from signing/notarization side effects and enumerates credential environment names without values. | Reuse only explicit side-effect planning and secret-name documentation. Do not sign, notarize, publish, or add Apple credential handling in this workflow. |
| `../google-marketing-gateway/scripts/smoke-reader-auth.sh` | Uses an isolated temporary root and asserts a credential lifecycle command does not create unexpected token state. | Reuse temporary-root cleanup and negative-state assertions in Meta offline CLI smokes. Diverge by never creating token stores or auth lifecycle commands; Kinko remains external and is not invoked by verification. |
| Target `scripts/verify-target-separation.sh`, `scripts/verify-no-secret-artifacts.sh`, and `scripts/verify-reproducible-archives.sh` | Existing Meta-local checks already express the intended stronger artifact boundary. | Extend these local scripts rather than importing release code blindly: assert broker placement, no writer symbols in reader artifacts, no secret/local-path material, checksums, SBOM/provenance, and reproducible reader/writer/broker packaging. |

## 4. Versioned capability catalog

One local, deterministic manifest is the authority for both compile-time
catalog projections, both CLIs, documentation, and tests. Each entry contains:

- stable operation ID and exactly one surface (`reader` or `writer`);
- operation kind (`publicRead`, `mutation`, or writer-internal
  `verificationRead`) and exposure (`publicCLI` or `internalAdapter`);
- reviewed Graph version, method, exact normalized path template, and domain;
- implementation state (`typed`, `generic`, `planned`, or `absent`) separately
  from availability (`enabled`, `blockedVersionReview`,
  `blockedProviderProof`, or `denied`);
- official source URLs, review date, and a precise reason for any block.

Fields after that are kind-specific. `publicRead` contains only its allowed
query/response metadata. Writer-internal `verificationRead` contains a closed
query schema, verifier purpose, bound mutation-operation IDs, required
principal/asset response shape, permissions, and freshness. `mutation`
contains its closed query/body schema, fixed values, serving/spend effect,
confirmation class, required authenticated principal shape, target derivation,
test-asset proof strategy, and reconciliation strategy. The generator rejects
fields from another kind rather than silently dropping them.

Catalog output is secret-free and deterministically sorted. Reader and writer
catalog commands expose separately generated compile-time projections; neither
contains or runtime-filters the other surface. A test fails when generated
projection, CLI dispatch, typed APIs, documentation, and manifest entries drift.

### 4.1 Major Ads domain disposition

| Domain | Reader disposition | Writer disposition for this rollout |
|---|---|---|
| Ad accounts and authenticated identity | Public typed account get/list and separately named public identity reads only; their output is never accepted as writer proof. | Writer-internal `verificationRead` entries own principal and asset identity GETs through WriterKit's closed transport. They have no public CLI dispatch and bind one verifier purpose and mutation operation. Rename/update remains `blockedVersionReview`; permissions, ownership, funding, billing, and account-status writes are denied. |
| Campaigns | Typed get/list. | Typed paused create and narrowly typed paused-safe update are designed; activation, positive budget/liability, delete/archive, and unproved targets remain individually blocked or denied. |
| Ad sets | Typed get/list. | Typed paused create and paused-safe update are designed; serving, bids, budgets, schedules, targeting expansion, delete/archive, and unproved targets remain blocked or denied. |
| Ads | Typed get/list. | Typed paused create and paused-safe update are designed; activation and unproved targets remain blocked or denied. |
| Ad creatives | Typed get/list. | Non-serving typed create/update may be cataloged; still blocked until account proof and exact reconciliation exist. |
| Insights | Typed reads for account, campaign, ad set, and ad. | No writer operation. |
| Images and videos | Typed metadata reads are required catalog entries; generic `GET` remains available. | Image/video uploads remain `blockedVersionReview`; resumable video upload is separately blocked until its host/session contract is reviewed. |
| Custom audiences | Typed read coverage or an explicit `implementation=generic` entry is required. | Create/update/delete and customer-data upload are denied in this rollout. |
| Pixels, events, conversions, leads | Typed read coverage or explicit `implementation=generic` entries are required. | Event submission and lead mutation are denied; sensitive payloads never enter plans or journals. |
| Catalogs and product sets | Typed read coverage or explicit `implementation=generic` entries are required. | Writes remain `blockedVersionReview` or denied by effect; they cannot fall through generic authorization. |
| Business assets, permissions, billing, funding | Read capability is explicit and least-privilege. | Every mutation is denied. |

`implementation=planned` means a credential-free offline analysis can be
constructed and reviewed but apply is impossible. Availability uses strict
precedence: `denied` for rollout-policy prohibitions; otherwise
`blockedVersionReview` when any mutation, version, field, principal-identity,
or reconciliation contract is incomplete or stale; otherwise
`blockedProviderProof` only when the sole remaining blocker is authoritative
machine-verifiable test/non-billable asset proof; otherwise `enabled` when all
required contracts and proof strategy are reviewed. Implementation and
availability remain independent: a `planned` or `absent` entry cannot dispatch
even when its availability is `enabled`, and transport additionally requires
every production adapter and dependency. A lower state cannot mask a
higher-priority denial or contract gap. None of the blocked or unimplemented
states may be reported as production mutation support.

### 4.2 Required operation families

The initial catalog contains these stable entries even when implementation or
provider evidence is incomplete:

| Surface | Required operation IDs | Initial disposition |
|---|---|---|
| Existing typed readers | `meta.ads.ad-accounts.list|get`, `meta.ads.campaigns.list|get`, `meta.ads.ad-sets.list|get`, `meta.ads.ads.list|get`, `meta.ads.ad-creatives.list|get`, `meta.ads.insights.read` | `typed`; `blockedVersionReview` until the existing 11-operation matrix is revalidated and migrated from `v26.0` to `v25.0`, then `enabled`. |
| Public identity reader | `meta.graph.identity.get` | `planned`; `blockedVersionReview` until its official public-read endpoint, fields, permissions, and version are reviewed. It is never accepted as writer proof. |
| Additional major readers | `meta.ads.images.list|get`, `meta.ads.videos.list|get`, `meta.ads.custom-audiences.list|get`, `meta.ads.pixels.list|get`, `meta.ads.leads.list|get`, `meta.ads.catalogs.list|get`, `meta.ads.product-sets.list|get`, `meta.ads.business-assets.list` | `planned`; `blockedVersionReview` with a precise missing-reference reason. A safe generic `GET` remains available only under its own policy. |
| Writer verification reads | `meta.writer.principal.verify`, plus one operation-specific asset verification and reconciliation-read ID for each non-denied mutation | `internalAdapter`; `blockedVersionReview` until its official endpoint, identity fields, permissions, purpose binding, freshness, and response contract are reviewed; never public Reader or CLI operations. |
| Paused object writers | `meta.ads.campaigns.create-paused|update-paused`, `meta.ads.ad-sets.create-paused|update-paused`, `meta.ads.ads.create-paused|update-paused` | `planned`; initially `blockedVersionReview` because principal-identity and reconciliation contracts remain incomplete. After those reviews, each entry moves to `blockedProviderProof` only while authoritative asset proof remains unavailable, then to `enabled` contract status while `planned` still prevents dispatch. |
| Non-serving creative writers | `meta.ads.ad-creatives.create-non-serving|update-non-serving` | Same staged rule: initially `blockedVersionReview`, then `blockedProviderProof` only for the sole authoritative asset-proof gap, then `enabled` contract status while unimplemented. |
| Media writers | `meta.ads.images.upload`, `meta.ads.videos.upload` | `planned`; `blockedVersionReview`, including upload host/session and provider-proof review. |
| Destructive Ads writers | `meta.ads.campaigns.delete`, `meta.ads.ad-sets.delete`, `meta.ads.ads.delete`, `meta.ads.ad-creatives.delete` | `denied` for this rollout. |
| Account-control writers | `meta.ads.ad-accounts.rename`, plus permissions, ownership, status, billing, and funding families | Rename is `blockedVersionReview`; all control/financial operations are `denied`. |
| Sensitive/data writers | custom-audience membership/upload, pixel/event submission, lead mutation | `denied`. |
| Catalog/product writers | create, update, delete for catalogs and product sets | `planned` and `blockedVersionReview`, or `denied` when destructive; never implicit generic authority. |

The `a|b` notation above expands to separate operation IDs; catalog JSON never
emits a compound ID. A missing entry is a release failure, not an implicit
generic capability.

### 4.3 Per-operation provider-evidence gaps

Availability is decided per operation entry, even when several entries share a
target account. The initial evidence ledger is:

| Operation entries | Mutation contract reviewed | Provider test/non-billable proof reviewed | Initial blockers |
|---|---|---|---|
| `meta.ads.campaigns.create-paused`, `meta.ads.campaigns.update-paused` | Campaign edge, 2026-08-15 | Sandbox page, 2026-08-15 | `missingMachineVerifiableAssetClassification`, `missingPrincipalIdentityContract`, `missingReconcilerContract`; initially `blockedVersionReview`. |
| `meta.ads.ad-sets.create-paused`, `meta.ads.ad-sets.update-paused` | Ad-set edge, 2026-08-15 | Sandbox page, 2026-08-15 | Same three independently recorded blockers; campaign proof may not satisfy either entry; initially `blockedVersionReview`. |
| `meta.ads.ads.create-paused`, `meta.ads.ads.update-paused` | Ad edge, 2026-08-15 | Sandbox page, 2026-08-15 | Same three independently recorded blockers; ad-set proof may not satisfy either entry; initially `blockedVersionReview`. |
| `meta.ads.ad-creatives.create-non-serving`, `meta.ads.ad-creatives.update-non-serving` | Ad-creative edge, 2026-08-15 | Sandbox page, 2026-08-15 | `missingMachineVerifiableAssetClassification`, `missingPrincipalIdentityContract`, `missingReconcilerContract`; initially `blockedVersionReview`. |
| Account rename, image/video upload, catalog/product writes | No complete operation-specific official contract review in this issue | Not reviewed | `blockedVersionReview`; these entries cannot be relabeled `blockedProviderProof` until method, fields, proof, and reconciliation have all been reviewed. |
| Deletes, activation, permissions, ownership, billing, funding, audience membership/upload, pixel/event submission, lead mutation | Provider syntax does not change the rollout decision | Not applicable | `denied` by destructive, serving, financial, or sensitive-data policy. |

The reviewed sandbox page documents the provider surface but did not expose a
public response property in this review that this gateway can read to prove the
exact target non-billable. Each blocker includes the checked URL, check date,
required missing evidence, and affected operation ID in catalog JSON. Closing a
blocker for one entry does not close any other entry automatically.
An entry moves from `blockedVersionReview` to `blockedProviderProof` only after
the catalog validator proves all non-asset-proof blocker fields are empty and
complete reviewed principal-identity and reconciliation contracts are present.
Once the authoritative asset-proof contract is reviewed, availability becomes
`enabled`; a missing verifier implementation remains `implementation=planned`
or a missing production dependency and never masquerades as a proof gap.

## 5. Generic relative-path Graph fallback

The generic fallback preserves endpoint evolution without becoming an
arbitrary proxy:

1. It accepts a normalized relative Graph node/edge only. Scheme, authority,
   port, user info, fragments, empty/dot segments, encoded separators,
   traversal, alternate origin, redirects, caller headers, auth query fields,
   cookies, proxies, and control characters are rejected locally.
2. URL construction fixes HTTPS and `graph.facebook.com`. Any separately
   documented upload host is a distinct typed capability, never a generic
   origin parameter.
3. The reader generic route is `GET` only and accepts only a currently reviewed
   version from the local version ledger. Pagination follows only same-origin,
   same-version provider links after reconstructing their validated relative
   path and query.
4. The writer generic route may canonicalize and plan `POST` or `DELETE` for a
   future relative endpoint. Planning does not authorize transport. Apply
   requires a catalog entry whose operation ID, version, method, exact path
   template, target binding, query/body schema and relevant values match the
   canonical request.
5. A syntactically safe unknown relative endpoint may produce only a
   credential-free offline analysis with `catalogMatch=null`,
   `transportEligibility=false`, and reason `unknownOperation`. Credentialed
   preview/apply rejects it before credential resolution. An unknown
   field/value, unsupported media type, duplicate key, ambiguous number,
   excessive nesting, static catalog blocker, or missing production adapter is
   likewise denied before credential resolution, journal mutation, or
   transport.

Thus endpoint expressibility and endpoint authority remain independent. There
is no runtime descriptor supplied by a caller and no risk label capable of
turning an unknown generic request into an enabled write.

## 6. Writer state and exact authorization

The writer exposes three distinct flows; an artifact from one flow cannot be
reinterpreted as another:

1. Credential-free offline plan:
   `parse -> canonicalize -> static catalog lookup -> classify availability and effects -> exact local policy checks -> emit offlinePlan`.
   It never reads an environment credential, invokes Kinko, opens a network
   connection, reads or changes the journal/broker, or obtains provider
   evidence. It may describe `enabled`, `blockedVersionReview`,
   `blockedProviderProof`, `denied`, or safe unknown-relative-path results, but
   always fixes `transportEligibility=false`. Apply rejects `offlinePlan`
   regardless of later confirmation.
2. Credentialed provider preview:
   `parse -> canonicalize -> require implemented+enabled exact entry -> local policy+configuration checks -> resolve allowlisted credential -> writer-internal principal GET -> operation-specific asset GET -> emit providerVerifiedPlan`.
   Any `denied`, `blockedVersionReview`, `blockedProviderProof`, planned-only,
   unknown, unsafe, or misconfigured entry stops before credential resolution.
   Preview is read-only and never reads or changes journal/head state. Its plan
   binds sanitized principal/asset evidence digests and expiries, exact catalog
   revision, request digest, sanitized writer-configuration digest, and
   `planKind=providerVerified`.
3. Credentialed apply:
   `parse providerVerifiedPlan -> validate digest/expiry/catalog/confirmation/config/USD0 -> read journal+trusted head -> resolve allowlisted credential -> reverify principal+asset by writer-internal GET -> lock and revalidate journal+head -> journal prepare -> in-flight anchor -> at-most-one send -> outcome-unknown anchor -> reconcile -> terminal anchor`.
   Apply never accepts an offline plan. No credential is read until all first
   phase local and durable-state checks pass; no journal record changes until
   fresh provider verification and the locked second state check pass; and no
   mutation bytes are sent until the in-flight record and head are durable.

Denial points are fixed. Invalid syntax, unknown network operation, static
catalog blocker, non-implemented dispatch, unsafe status/spend/body, invalid
plan/confirmation/configuration, or stale/mismatched journal/head denies before
`KinkoEnvironmentCredentials.resolve`. A missing/non-allowlisted environment
name denies after local checks but before any provider call or journal change.
Provider authentication, principal, asset, freshness, or proof mismatch denies
after credential resolution and read-only GETs but before journal mutation or
mutation transport. A state race found by the locked second check also denies
before journal mutation or transport. Journal/head failures after persistence
follow Section 7.2 and never authorize replay.

The exact-operation authorization key binds the reviewed API version, operation
ID, method, normalized path template and resolved target, canonical query/body
schema and values, media type, serving/spend effects, requested liability,
principal, asset-proof strategy, reconciliation strategy, idempotency key,
journal namespace, and plan digest. Caller-supplied descriptors are claims only
and cannot weaken or create an authorization.

Typed create builders force `PAUSED` where Meta exposes status. They reject
`ACTIVE`, status aliases, positive budget/spend liability, and serving schedules
whether present in path, query, form, JSON, nested JSON, or future aliases.
Ad-creative creation has `nonServing` effect, not `safeWithoutProof` effect.

The authorization lattice is monotonic:

`standard < highImpact < destructive < denied`

Unknown is never standard. A stronger acknowledgement cannot override
`denied`, missing provider proof, missing reconciliation, unsupported version,
or USD 0 policy. Batch writer execution is absent; independent plans may not be
combined to bypass per-operation or aggregate gates.

## 7. Production writer composition

The writer executable builds production dependencies only for an implemented
and `enabled` catalog entry. The complete composition includes:

- an owner-controlled durable journal with atomic replace, fsync, cross-process
  locking, authenticated event chains, permanent idempotency binding, receipts,
  outcome-unknown tombstones, terminal-only compaction, and explicit namespace
  rotation;
- the v1 trusted-head backend: a local Unix-domain compare-and-set broker
  running under a distinct OS identity, with a broker-owned state directory
  inaccessible to the writer process. The writer connects only to an
  owner-controlled socket and pins the expected broker peer identity. Startup
  rejects a missing/symlinked/broadly writable socket, the same writer/broker
  identity, an unexpected peer, or an unanchored namespace;
- a provider principal verifier that obtains fresh app and actor identity from
  authenticated read-only Meta responses during preview and again at apply,
  then matches both identities to the plan and journal key;
- an operation-specific provider asset verifier that returns fresh evidence for
  the exact account/asset derived from the normalized request and proves the
  catalog-required non-billable/test classification;
- an operation-specific read-only reconciler that can distinguish verified
  effect, verified no effect, pending, and unavailable without replaying;
- the built-in exact-operation authorization registry and USD 0 policy; and
- `KinkoEnvironmentCredentials`, resolved only after every local gate and only
  from the explicitly allowlisted environment names of the selected operation.

Production construction is all-or-nothing. Missing principal, proof,
reconciler, journal, trusted head, exact authorization, or credential wiring
does not fall back to a mock or the dependency-free writer. The CLI reports a
sanitized capability denial. Test doubles are available only to test targets
and never set catalog status to enabled.

The principal verifier itself is a provider-contract gate. Before any writer
entry becomes enabled, its catalog record must cite the official identity
endpoint, response fields for both app and actor, required permissions, and a
credential carrier that does not put a secret in the request URL. If that
contract is absent or ambiguous, availability remains
`blockedVersionReview`. Only after the mutation, principal, and reconciliation
contracts are complete may a missing authoritative asset classification use
`blockedProviderProof`.

### 7.1 Identity and credential flow

Kinko is the sole credential store. Secret values never appear in repository
files, request/plan files, CLI arguments, stdin, docs, fixtures, environment
dumps, logs, errors, stdout/stderr, journals, receipts, or crash diagnostics.
The operator launches a network operation through an explicit minimal
`kinko exec --env META_ACCESS_TOKEN -- <command>` invocation. The initial
allowlist contains only `META_ACCESS_TOKEN`; any future app-secret environment
name or need is a separately reviewed catalog change. The process rejects
credential-like CLI values and does not enumerate or dump its environment.

Help, version, catalog, and offline-plan commands are launched without
`kinko exec`; they neither require nor inspect `META_ACCESS_TOKEN`. If that name
is already present accidentally, these command paths never call the credential
adapter. Credentialed preview, apply, and reconciliation are the only command
paths intended for `kinko exec`. Even there, `KinkoEnvironmentCredentials`
does not read the allowlisted value until the Section 6 local denial point has
passed. Preview then performs only the two closed writer-verifier GET classes.
Apply repeats those GETs before any journal mutation, and reconciliation reads
the credential only after validating an exact recoverable journal/head state;
it performs only its cataloged read-only provider query before a definitive
forward journal transition.

The credential is passed in the HTTPS authorization header by a closed
transport. It is never accepted as a query item. Provider errors are bounded and
sanitized before crossing the transport boundary. Principal and asset evidence
contain non-secret IDs, timestamps, proof type, API version, and response
digests only; they contain no token or raw response.

### 7.2 Journal, trusted heads, and reconciliation

Journal records and trusted heads use the authenticated schema defined by the
prior accepted mutation-authentication design. The plan binds the journal
namespace, while the trusted head binds record identity, retained boundary, and
latest event. Missing, stale, rolled-back, legacy, or mismatched state fails
closed. Ordinary apply cannot repair a head or migrate a legacy record.

The initial production backend is selected: a local
`meta-marketing-gateway-trusted-head-broker` process listens on one Unix-domain
socket and persists heads in its own owner-only directory. The broker runs as a
different OS user from the writer; the writer user has no filesystem access to
the head directory. Socket permissions admit only the configured writer group,
and both peers verify OS peer credentials. A same-user broker configuration is
invalid. The protocol is local-only, length-bounded, versioned, and carries only
namespace, record identity, expected head, proposed head, and sanitized result.
It never carries credentials, request bodies, provider responses, or journal
events.

The broker exposes only `readHead` and `compareAndSetHead`. It validates schema,
record identity, retained boundary, digest shapes, expected prior head, and
strictly monotonic sequence before atomic replace and fsync. It exposes no
delete, reset, arbitrary write, list-all, network listener, or ordinary repair
operation. A missing head or a disagreement that is not exactly one validated
forward transition stays fail-closed; neither the CLI nor an operator can
reset, replace, or move a head backward. A mounted-directory backend, remote
service, in-process file store, and Kinko-backed head state are not production
options in v1. Tests may use a package-internal in-memory broker fake, which
cannot satisfy production composition.

Once transport is permitted, every result—including an apparent success—is
first persisted and anchored as `outcomeUnknown`. A response is an observation,
not provider reconciliation. Apply never automatically retries that operation.
Only its cataloged read-only reconciler may transition to `succeeded` or
`failedSafeToRetry`; `pending` and `unavailable` remain non-retryable. A later
retry from `failedSafeToRetry` is a new, separately confirmed apply only when
the exact catalog entry permits it. The original record remains terminal: a
retry requires a new plan digest, idempotency key, journal key, and record
identity and must repeat every authorization and evidence gate. It never
transitions the old `failedSafeToRetry` record back to `inFlight`.
Reconciliation repeats principal, asset, target, version, request-digest, and
proof checks before its provider read.

Every journal transition uses a record/head compare-and-set protocol:

1. Validate the current record and independently read trusted head against the
   expected prior anchor.
2. Atomically replace and fsync the journal record.
3. Compare-and-set the trusted head from the expected prior anchor to the new
   anchor through the separately protected backend.
4. On disagreement, stop normal apply and enter the bounded recovery rules
   below; no new plan or transport is allowed for that journal namespace.

The `inFlight` record and its trusted head must both be durable before mutation
transport. If the journal write succeeds but its head update is interrupted,
the recovery controller may retry only the identical expected-old-to-new CAS
after validating that the journal contains exactly one authenticated successor,
the successor is `inFlight`, and no transport can have started before that head
became durable. It cannot rewrite the candidate or execute the mutation during
recovery.

Post-transport recovery uses this exact sequence model. Let `J_n` be the
authenticated, broker-anchored `inFlight` event at sequence `n`, with event hash
`h_n`. Let `H_n` be the full broker head for the same record identity and
retained boundary, with `finalSequence=n` and `finalHash=h_n`. `J_k` always has
`sequence=k` and `previousHash=h_(k-1)`; `H_k` names `finalSequence=k` and
`finalHash=h_k`.

A terminal event binds a non-secret `reconciliationClaimDigest` over the
canonical operation ID, request digest, target, reviewed version, provider
object/effect-or-absence identity, and terminal classification. Fresh recovery
evidence may have a new observation timestamp, but it must authenticate the
same principal and asset and reproduce that claim digest exactly.

| Observed durable state | Required recovery action | Broker CAS |
|---|---|---|
| Record and head both end at `J_n=inFlight` / `H_n` after transport may have been permitted. | Never send or replay. Append and fsync `J_(n+1)=outcomeUnknown`; its authenticated payload binds the sanitized transport-observation digest when one exists, otherwise an explicit no-observation marker. | `expectedOld=H_n`, `proposedNew=H_(n+1)`. |
| Record ends at the single successor `J_(n+1)=outcomeUnknown`, but the broker remains at `H_n`. | Validate the exact successor and retry no other work. | `expectedOld=H_n`, `proposedNew=H_(n+1)`. |
| Record and broker both end at `J_(n+1)=outcomeUnknown` / `H_(n+1)`; reconciliation returns `pending` or `unavailable`. | Append nothing; retain `outcomeUnknown` and block retry. | None. |
| Record and broker both end at `J_(n+1)=outcomeUnknown` / `H_(n+1)`; fresh reconciliation returns `verifiedEffect`. | Append and fsync `J_(n+2)=succeeded`, binding the reconciliation claim and its digest. | `expectedOld=H_(n+1)`, `proposedNew=H_(n+2)` derived from that new event. |
| Record and broker both end at `J_(n+1)=outcomeUnknown` / `H_(n+1)`; fresh reconciliation returns `verifiedNoEffect`. | Append and fsync `J_(n+2)=failedSafeToRetry`, binding the verified-absence claim and its digest. | `expectedOld=H_(n+1)`, `proposedNew=H_(n+2)` derived from that new event. |
| Record contains the single terminal successor `J_(n+2)=succeeded`, while the broker remains at `H_(n+1)`. | Re-run fresh reconciliation. Only `verifiedEffect` that reproduces the event's exact `reconciliationClaimDigest` may validate the existing event; do not append or replace it. | `expectedOld=H_(n+1)`, `proposedNew=H_(n+2)` derived from the existing event. |
| Record contains the single terminal successor `J_(n+2)=failedSafeToRetry`, while the broker remains at `H_(n+1)`. | Re-run fresh reconciliation. Only `verifiedNoEffect` that reproduces the event's exact `reconciliationClaimDigest` may validate the existing event; do not append or replace it. | `expectedOld=H_(n+1)`, `proposedNew=H_(n+2)` derived from the existing event. |
| Any reconciliation is mismatched or ambiguous, a candidate is not the exact next sequence/hash/state, more than one unanchored successor exists, or a terminal event directly follows `J_n=inFlight`. | Quarantine the namespace as stale untrusted state. | None. |

Thus recovery always anchors the existing `outcomeUnknown` successor before a
terminal event can be appended. An unanchored candidate is immutable: recovery
may neither rewrite, delete, replace, compact, nor skip it, and may not append a
later event while it is unanchored. The only permitted recovery write to the
broker is the table's identical one-step forward CAS. Provider evidence never
authorizes a two-sequence jump. Trusted-head compare-and-set rejects backward
sequence, wrong record identity, wrong retained boundary, and unexpected prior
head.

## 8. USD 0 and test-asset rules

The live-spend ceiling and aggregate workflow budget are both USD 0.

- Any positive requested liability is denied.
- Any operation capable of activating delivery is denied even when its explicit
  numeric liability is zero.
- Missing/old/mismatched provider evidence is classified as live and denied.
- A caller label, local allowlist of IDs, email domain, account name, mock,
  fixture, or previous success is not provider proof.
- Evidence is operation-specific and fresh at both preview and apply. Proof for
  a campaign create does not authorize an ad-set write, delete, upload, or a
  different account.
- Capability gaps are isolated: one unsupported operation remains blocked
  without disabling safe reads or misrepresenting another writer operation.

No workflow verification invokes a live Meta read or mutation, reads a Kinko
value, creates a credential, or spends money. Provider-backed readiness is
established by contract and production composition tests; actual credentialed
execution requires a later, separately authorized operator event.

## 9. CLI behavior mapping

| Behavior | Reader CLI | Writer CLI |
|---|---|---|
| Help/version | Local, credential-free, exit 0. | Local, credential-free, exit 0. |
| Catalog | `catalog list`, reader entries only. | `catalog list`, writer entries including precise blocked reasons. |
| Generic fallback | `graph get` with relative path and reviewed version. | `graph post|delete plan` emits a non-executable offline analysis, including for a safe unknown path; credentialed preview/apply requires an exact implemented+enabled entry. |
| Typed Ads | Typed list/get/insights and explicitly cataloged gaps. | Offline analysis may show any disposition; preview/apply/reconcile exists only for exact implemented+enabled paused/non-serving entries. |
| Credentials | Resolved after local validation for an authorized network read. | Never inspected for help/version/catalog/offline plan. Preview resolves only after static enabled/policy checks. Apply resolves only after verified-plan, confirmation, configuration, USD 0, and initial journal/head checks. Reconcile resolves only for an exact recoverable state. |
| Runtime state configuration | None. | One owner-only, non-secret `--writer-config` file names the journal namespace/location, broker socket path, expected broker OS identity, and permitted operation IDs; it cannot select another backend, contains no credential value, and is bound into the plan by a sanitized configuration digest. |
| Output | Bounded sanitized JSON; no raw response by default. | Bounded sanitized plan/receipt state; no request body, token, raw proof, or raw provider error. |

No Cursor- or Codex-agent-specific command behavior was supplied. CLI parsing
and rendering remain thin adapters over their owning kit's generated catalog
and policy. Reader CLI has no writer-policy module to call. An adapter may
translate arguments and sanitized errors, but it cannot classify operations,
synthesize proof, repair journals, select credentials, or reinterpret a denial.
The writer configuration may only further restrict built-in enabled operations;
it cannot create an entry, clear a blocker, or elevate availability.

Writer command forms are fixed for this rollout:

```text
meta-marketing-gateway-writer graph post|delete --api-version vNN.N --request-file request.json --plan-out offline-plan.json
kinko exec --env META_ACCESS_TOKEN -- meta-marketing-gateway-writer graph post|delete --api-version vNN.N --request-file request.json --preview-out verified-plan.json
kinko exec --env META_ACCESS_TOKEN -- meta-marketing-gateway-writer graph post|delete --api-version vNN.N --request-file request.json --apply verified-plan.json --confirm FULL_PLAN_DIGEST
kinko exec --env META_ACCESS_TOKEN -- meta-marketing-gateway-writer reconcile --plan verified-plan.json
```

`--plan-out` and `--preview-out` are mutually exclusive. Offline output records
no evidence and can never satisfy `--apply`. Preview and reconciliation are
read-only provider operations, but they are credentialed and therefore excluded
from this workflow's smoke verification. Plan files contain no credential, raw
provider response, or raw evidence.

## 10. Validation and release gates

Tests must cover the positive safe path and prove every denial happens before
credentials, journal changes, or transport as appropriate. Required adversarial
families include alternate-origin/path encoding, version drift, path/query/body
policy parity, `ACTIVE` and budget smuggling, authorization downgrade, proof
reuse across assets/operations, principal mismatch, stale evidence, journal/head
rollback, post-plan tampering, expiry races, crash boundaries, concurrent apply,
unknown outcome, reconciliation mismatch, secret-shaped diagnostics, and reader
to writer capability escalation.

Flow tests must prove availability precedence
`denied > blockedVersionReview > blockedProviderProof > enabled`; writer-internal
identity reads are absent from ReaderKit and have no public CLI dispatch;
an availability-enabled but `planned` entry remains non-dispatchable;
offline planning never resolves credentials or touches network/journal/broker;
blocked preview/apply denies before credential resolution; provider mismatch
denies after read-only verification but before journal mutation; and apply reads
the credential only after verified-plan, confirmation, configuration, USD 0,
and initial journal/head validation.

Crash-boundary tests must separately prove that a pre-transport journal-ahead
candidate can complete only the identical forward CAS without sending bytes;
that `inFlight` recovery never sends and first persists `outcomeUnknown`; that
an unanchored `outcomeUnknown` can only receive the identical `H_n` to
`H_(n+1)` CAS; that reconciliation appends terminals only after `H_(n+1)` is
durable; that an unanchored terminal can only receive the identical
`H_(n+1)` to `H_(n+2)` CAS after matching fresh reconciliation; that direct
terminal successors, rewrites, skips, two-sequence advances, and replays are
rejected; that `failedSafeToRetry` cannot return the same record to `inFlight`;
and that unavailable or ambiguous reconciliation remains blocked and
non-retryable.

The implementation gate records, without live Meta access:

```text
swift build
swift test
swift build -c release
swift run meta-marketing-gateway-reader --help
swift run meta-marketing-gateway-writer --help
swift run meta-marketing-gateway-reader catalog list
swift run meta-marketing-gateway-writer catalog list
swift test --filter GraphSecurityTests.testWriterTreatsBodyStatusAndBudgetAsHighImpact
swift test --filter GraphSecurityTests.testWriterRejectsEachWeakerCallerAuthorizationClaimBeforeSideEffects
swift test --filter GraphSecurityTests.testWriterRejectsAuthorizationAssetPathMismatch
swift test --filter GraphSecurityTests.testReconcileRejectsMismatchedAssetEvidence
swift test --filter GraphSecurityTests.testSpendSafetyRequiresFreshProviderVerifiedNonBillableAssetAndUSDZero
swift test --filter GraphSecurityTests.testTrustedHeadRejectsDigestTampering
swift test --filter GraphSecurityTests.testRecoveryAnchorsOutcomeUnknownBeforeReconciliation
swift test --filter GraphSecurityTests.testRecoveryNeverSkipsUnanchoredCandidate
swift test --filter GraphSecurityTests.testRecoveryAnchorsOnlyMatchingExistingTerminalCandidate
swift test --filter GraphSecurityTests.testFailedSafeToRetryRequiresNewRecordIdentity
swift test --filter MetaCapabilityCatalogGeneratorTests
swift test --filter MetaMarketingGatewayReaderKitTests.testReaderProjectionContainsNoWriterRowsOrPolicyFields
swift test --filter MetaMarketingGatewayWriterKitTests.testWriterProjectionRequiresCompletePolicy
swift test --filter MetaMarketingGatewayWriterKitTests.testAvailabilityPrecedenceIsFailClosed
swift test --filter MetaMarketingGatewayWriterKitTests.testPlannedEnabledOperationCannotDispatch
swift test --filter MetaMarketingGatewayReaderKitTests.testWriterVerificationReadsAreAbsent
swift test --filter MetaMarketingGatewayWriterKitTests.testOfflinePlanNeverResolvesCredentialOrTouchesSideEffects
swift test --filter MetaMarketingGatewayWriterKitTests.testBlockedPreviewDeniesBeforeCredentialResolution
swift test --filter MetaMarketingGatewayWriterKitTests.testApplyCredentialResolutionOccursAfterLocalAndInitialHeadChecks
swift test --filter MetaMarketingGatewayWriterKitTests.testProviderMismatchPrecedesJournalMutation
swift package dump-package
swift package describe --type json
scripts/verify-target-separation.sh
scripts/verify-catalog-projections.sh
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
design_check_output="$(git diff --no-index --check /dev/null design-docs/specs/design-production-safe-reader-writer-completion.md 2>&1 || test $? -eq 1)"
test -z "$design_check_output"
```

Package inspection must also prove separate reader/writer archives, the broker
present only in the writer archive, expected executables and library modules
only, no credential-bearing files, no absolute workstation paths, and no reader
linkage to writer CLI, broker client, or mutation transport.
`scripts/verify-target-separation.sh` must parse `swift package dump-package`
and inspect reader symbols/strings to prove there is no dependency or emitted
identifier for `MetaMarketingGatewayWriterKit`, `MetaTrustedHeadProtocol`,
`MetaMarketingGatewayTrustedHeadBroker`, writer operation IDs, mutation verbs,
proof/reconciliation policy fields, or writer CLI routes.
`scripts/verify-catalog-projections.sh` must regenerate both projections and
documentation twice into separate temporary directories, prove byte-for-byte
determinism, compare the documentation projection with the committed catalog
documentation, compare projection JSON with each built CLI's `catalog list`,
and reject reader rows with writer fields or methods other than `GET`; it never
writes generated `.build/` content directly.
Temporary scan reports stay outside the repository and contain no secret value.

Passing mocks proves orchestration and fail-closed behavior; it does not prove a
Meta asset is non-billable. Availability follows Section 4 precedence: missing
mutation, identity, or reconciliation contracts remain
`blockedVersionReview`; only a sole remaining authoritative asset-proof gap is
`blockedProviderProof`; policy-prohibited operations remain `denied`; missing
code or adapters remain an implementation/dependency blocker rather than a
provider-proof state.

## 11. Rollout constraints

1. Correct the current `v26.0` typed authority to the revalidated `v25.0`
   catalog before claiming typed compatibility. Generic version syntax alone is
   not a support claim.
2. Replace `MetaMarketingGatewayCore` with the Section 3.1 target graph; add the
   build-only manifest generator and compile-time reader/writer projections
   before enabling production composition.
3. Add the writer-only trusted-head broker product, distinct-identity operator
   contract, bounded Unix-domain protocol, peer checks, CAS persistence, and
   writer-archive-only packaging before production apply composition.
4. Land exact policy, typed paused builders, provider adapters, reconciliation,
   writer-internal identity reads, split offline/preview/apply flows, and
   production composition behind default-deny catalog states.
5. Enable operations one at a time only after their official proof gap closes
   and focused adversarial tests pass.
6. Update README, SECURITY, operator guidance, implementation-plan checklists,
   Package.swift, and release scripts from the same catalog authority.
7. Preserve or improve the 76-test baseline, release build, Gitleaks zero, and
   Semgrep zero results. No stage, commit, push, publish, deploy, live mutation,
   credential access, or spend is part of this rollout verification.

## 12. Decisions and residual risks

Decisions:

- Use one versioned capability catalog as the behavioral authority.
- Generate separate reader-only and writer-only Swift catalogs from one
  build-only manifest; runtime targets never contain or filter the other
  surface, and shared primitives own no catalog or dispatch.
- Apply availability precedence `denied > blockedVersionReview >
  blockedProviderProof > enabled`; use `blockedProviderProof` only when
  authoritative asset proof is the sole remaining blocker.
- Keep public Reader identity reads distinct from writer-internal,
  non-dispatchable verification reads owned by WriterKit.
- Keep offline plans credential-free and permanently non-executable; only an
  enabled credentialed preview may emit a provider-verified plan accepted by
  apply, with credentials resolved at the fixed Section 6 denial points.
- Treat current official Ads references as `v25.0`; fail closed on the
  repository's unverified `v26.0` typed claim.
- Keep generic reads expressive and generic writes plan-expressive but
  transport-ineligible without an exact built-in operation entry.
- Default typed campaign, ad-set, and ad creation to immutable `PAUSED`; never
  offer activation or positive liability in this rollout.
- Require all production writer dependencies and operation-specific provider
  proof/reconciliation; mocks never satisfy production readiness.
- Select the distinct-OS-identity Unix-domain compare-and-set broker as the only
  v1 production trusted-head backend; other backends require a future design.
- Require every possible transport attempt to anchor `outcomeUnknown` at
  sequence `n+1` before reconciliation may append one terminal event at
  sequence `n+2`; recovery never rewrites or skips an unanchored candidate.
- Use Kinko environment injection only and preserve separate reader/writer
  clients, targets, executables, and artifacts.

There are no unresolved user decisions. Provider proof contracts are evidence
blockers handled by per-operation catalog state, not questions that can be
answered by lowering safety. Residual risks are Meta contract drift after the
review date, provider proof granularity, privileged compromise of the broker
identity, Unix-socket denial of service, operation-specific reconciliation
contracts that remain catalog-blocked until complete, and accidental capability
drift. The dated ledger, isolated block states,
peer-authenticated broker boundary, monotonic CAS, exact policy, and adversarial
gates mitigate but do not eliminate those risks.

## 13. Issue-to-design mapping

| Intake requirement | Design sections |
|---|---|
| Official current contracts and dates | 2, 4, 11 |
| Major Ads reader/writer coverage and paused defaults | 4.1, 4.2, 4.3, 6, 8 |
| Safe future relative endpoints | 5 |
| Durable journal and separate trusted heads | 3, 7.2, 10, 11 |
| Authenticated principal and provider test proof | 7, 7.1, 8 |
| Reconciliation and exact authorization | 6, 7.2 |
| Kinko-only credential injection | 7.1 |
| Availability-state precedence and per-operation blockers | 2, 4, 4.2, 4.3, 10 |
| Public Reader versus writer-internal identity reads | 3.1, 4, 4.1, 4.2, 7, 9, 10 |
| Credential-free offline plan versus credentialed preview/apply | 5, 6, 7.1, 9, 10 |
| Individually fail-closed evidence gaps | 2, 4.2, 4.3, 8 |
| Separate targets, compile-time catalog projections, clients/executables, and packaging | 3, 3.1, 3.2, 9, 10 |
| Documentation/operator/checklist consistency | 4, 11 |
| Baseline and required verification | 10, 11 |
| No live mutation, secret access, spend, or repository publication | 8, 10, 11 |
