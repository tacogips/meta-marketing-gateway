# Typed Ads Reader Domains

**Feature ID**: `meta-ads-reader`

**Feature title**: Typed Ads reader domains

**Issue**: `workflow:codex-design-and-implement-review-loop-session-732/communication:comm-002452`

**Workflow mode**: `issue-resolution`

**Status**: Accepted for implementation planning

**Reviewed**: 2026-08-15

**Reference repository**: `../google-marketing-gateway`

## 1. Purpose

Add a read-only, typed Swift and CLI layer for the most-used Meta Marketing API
resources without weakening the endpoint-complete generic Graph API core. The
typed layer covers ad accounts, campaigns, ad sets, ads, ad creatives, and
insights; explicit field selection; bounded filters; cursor pagination; and
local capability discovery.

The generic core remains the escape hatch for current or future official Graph
API endpoints. Typed conveniences provide safer construction and decoding for
known reader operations, but do not claim that their compiled field enums are a
complete or permanently current representation of Meta's surface.

## 2. Scope

### Included

- Typed `get` and connection `list` reads for ad accounts, campaigns, ad sets,
  ads, and ad creatives.
- Typed synchronous insights reads for ad account, campaign, ad set, and ad
  nodes.
- Explicit field selection with domain-specific field names and no implicit
  request for all fields.
- Typed structural filtering with a reviewed field/operator/value matrix.
- Forward and backward cursor pagination without following provider-returned
  URLs.
- Typed response envelopes that preserve unknown JSON fields for API drift.
- Local, credential-free capability discovery that distinguishes typed,
  generic-only, implemented, and unavailable operations.
- Reader CLI commands and JSON output suitable for automation.
- Deterministic tests using injected HTTP transport, fixtures, and Meta test
  assets where an integration check is explicitly authorized.

### Excluded

- Creates, updates, deletes, status changes, budget changes, uploads, previews,
  publishing, or any other mutation.
- Async insights report creation/polling and large result materialization in
  this slice. Those remain available only through a separately reviewed generic
  reader operation if the generic core classifies them as non-mutating.
- Automatic traversal of every page, retries that can create unbounded work,
  arbitrary field expansion expressions, arbitrary filter JSON, or following
  `paging.next`/`paging.previous` URLs.
- A runtime claim that Meta's API schema can be fully discovered from the
  network. Capability discovery is the gateway's versioned local contract.
- Live campaign or billing activity. No paid action is needed for this feature.

## 3. Dependencies and Ownership

This feature consumes, but does not redesign, the repository-wide foundation:

| Dependency | Required contract | Owner |
|---|---|---|
| Generic Graph core | Fixed `https://graph.facebook.com` origin, explicit effective `GraphAPIVersion`, `GraphPath`/`GraphQuery`, `MetaGraphReading`, injected transport, shared JSON value/response model, and sanitized errors | Generic core feature |
| Reader/writer split | Reader executable cannot dispatch mutating descriptors | Safety/CLI foundation |
| Credentials | Access token resolved only from an allowlisted environment variable injected by Kinko | Credential foundation |
| Operation catalog | Stable operation IDs, capability, availability, version support, and dispatchability | Generic core/capability foundation |
| CLI envelope | Stable JSON success/error output and exit-code policy | CLI foundation |

If a shared type or path is named differently when the foundation lands, the
implementation may adapt file names without changing the behavioral contracts
in this document. This feature owns only reader-domain models, builders,
catalog entries, CLI routing, tests, and associated docs.

## 4. Version and Source Policy

Meta Marketing API fields and versions are time-sensitive. On 2026-08-15, the
official Meta Marketing API documentation rendered examples with Graph API
`v26.0`. That observation is evidence for the initial fixture/version matrix,
not permission to scatter `v26.0` literals throughout the code.

- One shared `GraphAPIVersion` value supplies the effective request version.
- The package defines a tested typed compatibility matrix. The first matrix
  entry is `v26.0`.
- A version unsupported by the typed matrix fails locally for typed commands.
  It may still be used by the generic core if that core's own policy permits it.
- Capability output reports the effective version, typed tested versions, and
  last schema-review date.
- Version selection is required at typed client initialization and through the
  shared `--api-version` option on every network CLI command; it is never an
  arbitrary URL or host override.
- Updating a typed version requires official-doc review, fixture refresh,
  decoding/request tests, and a catalog update.

Official sources reviewed:

- `https://developers.facebook.com/docs/marketing-api/overview/`
- `https://developers.facebook.com/docs/marketing-api/reference/ad-account/campaigns/`
- `https://developers.facebook.com/docs/marketing-api/reference/ad-account/adsets/`
- `https://developers.facebook.com/docs/marketing-api/reference/ad-account/ads/`
- `https://developers.facebook.com/docs/marketing-api/reference/ad-account/adcreatives/`
- `https://developers.facebook.com/docs/marketing-api/insights/`
- `https://developers.facebook.com/docs/graph-api/results/`
- `https://developers.facebook.com/docs/graph-api/guides/versioning/`

## 5. Public Swift API

The reader exposes an injected client rather than global state:

```swift
public protocol MetaAdsReading: Sendable {
    func adAccounts(_ request: AdAccountListRequest) async throws -> GraphPage<AdAccount>
    func adAccount(_ request: AdAccountGetRequest) async throws -> AdAccount
    func campaigns(_ request: CampaignListRequest) async throws -> GraphPage<Campaign>
    func campaign(_ request: CampaignGetRequest) async throws -> Campaign
    func adSets(_ request: AdSetListRequest) async throws -> GraphPage<AdSet>
    func adSet(_ request: AdSetGetRequest) async throws -> AdSet
    func ads(_ request: AdListRequest) async throws -> GraphPage<Ad>
    func ad(_ request: AdGetRequest) async throws -> Ad
    func adCreatives(_ request: AdCreativeListRequest) async throws -> GraphPage<AdCreative>
    func adCreative(_ request: AdCreativeGetRequest) async throws -> AdCreative
    func insights(_ request: InsightsRequest) async throws -> GraphPage<InsightRow>
    func capabilities(_ request: CapabilityRequest) -> CapabilityDocument
}
```

Concrete request names may be grouped by generic helper protocols internally,
but public domain types remain explicit. Every request is `Sendable` and
validates before credential resolution or transport.

### Identifiers

- `AdAccountID` accepts canonical `act_<ASCII digits>` and a digits-only input
  that it canonicalizes once. It never accepts `/`, `?`, `#`, whitespace,
  Unicode digits, percent escapes, or an empty suffix.
- `CampaignID`, `AdSetID`, `AdID`, and `AdCreativeID` are distinct public types.
  Their initial typed form accepts non-empty ASCII digits only.
- The generic core retains a separately validated opaque node/path surface for
  endpoints whose official identifiers do not fit these typed IDs.
- Typed IDs are redacted from credential/provider errors unless the stable CLI
  error schema explicitly identifies an invalid user-supplied argument.

### Domain models

Models expose a conservative stable core, with all selected fields optional
except `id` when Meta returns it:

| Model | Initial typed fields |
|---|---|
| `AdAccount` | `id`, `accountId`, `name`, `accountStatus`, `currency`, `timezoneName`, `businessName`, `createdTime` |
| `Campaign` | `id`, `accountId`, `name`, `objective`, `status`, `effectiveStatus`, `buyingType`, `startTime`, `stopTime`, `createdTime`, `updatedTime` |
| `AdSet` | `id`, `accountId`, `campaignId`, `name`, `status`, `effectiveStatus`, `optimizationGoal`, `billingEvent`, `startTime`, `endTime`, `createdTime`, `updatedTime` |
| `Ad` | `id`, `accountId`, `campaignId`, `adsetId`, `name`, `status`, `effectiveStatus`, `creative`, `createdTime`, `updatedTime` |
| `AdCreative` | `id`, `accountId`, `name`, `title`, `body`, `status`, `thumbnailURL`, `objectStoryId`, `createdTime` |
| `InsightRow` | identity/date dimensions plus requested metrics represented with lossless provider-compatible scalar wrappers |

Provider enums use tolerant value types: known cases are conveniences and an
`unknown(String)` case preserves newly introduced values. Metrics that Meta
encodes as decimal or integer strings are not decoded through binary floating
point. `InsightValue` preserves the original JSON scalar/object/array so action
metrics and future shapes are lossless.

Every model retains unconsumed selected properties in
`additionalFields: [String: JSONValue]`. Secrets, request headers, and paging
URLs are never placed there. A missing requested field is not a decode failure;
it remains `nil`, while malformed types produce an error identifying only the
field name and expected shape.

## 6. Typed Operation Matrix

Stable catalog IDs and provider paths are:

| Operation ID | Typed input | Fixed provider path |
|---|---|---|
| `meta.ads.ad-accounts.list` | user node (`me` by default), fields, page | `/{user-id-or-me}/adaccounts` |
| `meta.ads.ad-accounts.get` | ad account ID, fields | `/{act_account_id}` |
| `meta.ads.campaigns.list` | ad account ID, fields, filters, page | `/{act_account_id}/campaigns` |
| `meta.ads.campaigns.get` | campaign ID, fields | `/{campaign_id}` |
| `meta.ads.ad-sets.list` | ad account ID, fields, filters, page | `/{act_account_id}/adsets` |
| `meta.ads.ad-sets.get` | ad set ID, fields | `/{adset_id}` |
| `meta.ads.ads.list` | ad account ID, fields, filters, page | `/{act_account_id}/ads` |
| `meta.ads.ads.get` | ad ID, fields | `/{ad_id}` |
| `meta.ads.ad-creatives.list` | ad account ID, fields, filters, page | `/{act_account_id}/adcreatives` |
| `meta.ads.ad-creatives.get` | ad creative ID, fields | `/{creative_id}` |
| `meta.ads.insights.read` | subject, fields, attribution/time options, filters, page | `/{subject_id}/insights` |

All eleven provider operations are HTTP `GET`. The shared builder inserts the effective
version as the first path component and percent-encodes query items. Typed code
does not accept origin, raw path, method, headers, query dictionaries, access
tokens, or app secrets.

Capability discovery is not a provider operation and does not receive a fake Ads
operation descriptor. `MetaAdsCapabilityCatalog` supplies typed descriptors to
the shared local `catalog list` route.

The ad-account list's only symbolic node is the closed `me` case. Support for a
different user ID uses a strict typed numeric ID and is not a raw path string.

## 7. Field Selection

Every provider request requires a non-empty `FieldSelection<DomainField>`.
There is no wildcard and no implicit default field set in the Swift API. The CLI
may expose named presets (`identity`, `delivery`, `summary`) whose exact ordered
fields are returned by capability discovery and versioned with the package.

- Field enums serialize only their official raw names.
- Duplicate fields are removed while preserving first occurrence.
- The serialized comma-separated value is capped at 16 KiB UTF-8 locally.
- Nested Graph field expansion syntax, braces, parentheses, dots, commas in a
  raw field, aliases, and caller-supplied expressions are rejected by the typed
  layer.
- A field must be listed for the selected domain and effective typed version.
- Callers needing an unmodeled official field use the generic reader surface;
  they do not smuggle it through a typed command.

This boundary prevents accidental data over-fetch and keeps capability output
honest. Adding a field is source-compatible through new static members and is
verified against current official documentation.

## 8. Filtering

Connection and insights list requests accept an ordered array of
`MetaAdsFilter<Field>`. A filter contains one typed field, a closed
`FilterOperator`, and a `FilterValue` JSON scalar or homogeneous scalar array.

- The typed compatibility matrix owns permitted field/operator/value-shape
  combinations per domain and version.
- The initial public operators are only those confirmed in the official docs
  and fixtures during implementation; the design does not invent or pass
  through arbitrary operator strings.
- The filter array is JSON-encoded once into the official `filtering` query
  parameter by `JSONEncoder`, never by string concatenation.
- At most 50 filters and 64 scalar array members per filter are accepted, with
  a 64 KiB encoded filter limit. These are gateway safety limits, not claims
  about Meta limits.
- Controls, non-finite numbers, raw JSON fragments, and mixed-shape arrays are
  rejected locally.
- Provider-only semantic errors remain sanitized provider failures; the client
  does not pretend to validate every cross-field rule.

Named status filtering such as `effective_status` may have a convenience
builder, but it compiles to the same typed filter representation.

## 9. Pagination

```swift
public struct PageRequest: Sendable, Equatable {
    public var limit: Int?
    public var direction: CursorDirection?
}

public enum CursorDirection: Sendable, Equatable {
    case after(PageCursor)
    case before(PageCursor)
}
```

- `after` and `before` are mutually exclusive by construction.
- `PageCursor` is opaque, non-empty, at most 16 KiB UTF-8, and rejects ASCII
  controls. It is never logged.
- `limit`, when supplied, is 1...500 as a gateway work bound. A domain/version
  can advertise a lower supported maximum in capability metadata.
- The shared `GraphPage<T>` contains `data`, the exact validated opaque cursor values, and
  `hasNextPage` / `hasPreviousPage`. Cursors are returned only in the intended
  result paging object so the caller can continue; they are never normalized,
  logged, or copied into errors. The page does not expose provider
  next/previous URLs.
- The decoder extracts only `paging.cursors.before` and
  `paging.cursors.after`. A next request is rebuilt from the original typed
  operation, fixed origin/path/version, original fields/filters, and returned
  cursor.
- No automatic page loop exists in the core typed method. A convenience async
  sequence, if later added, must require explicit `maxPages` and `maxItems`.

Provider-returned paging URLs are treated as untrusted response data and are
never followed, preventing origin/version/query injection and token reflection.

## 10. Insights

`InsightsSubject` is a closed enum for ad account, campaign, ad set, and ad IDs.
`InsightsRequest` requires non-empty typed `InsightField` selection and supports:

- optional `level`, constrained to levels valid for the subject;
- either a typed `datePreset` or a validated inclusive `timeRange`, never both;
- optional positive `timeIncrement` within the capability matrix;
- ordered typed `breakdowns` and `actionBreakdowns` with duplicates removed;
- typed `actionAttributionWindows`, sorting, filters, and one page request;
- optional summary request only where explicitly advertised.

Dates are strict Gregorian `YYYY-MM-DD` values. The start date must not be after
the end date. Breakdown compatibility changes across versions; the local matrix
rejects only combinations known to be invalid and otherwise lets Meta decide.
Capability output labels such validation as `structural` or `provider` so
callers do not mistake a local list for exhaustive provider semantics.

The response preserves metric strings and action arrays losslessly. No money is
converted between currencies, no attribution value is recomputed, and no
timezone normalization is inferred. Synchronous responses share the same page
and size bounds as other reads. Async job IDs or polling URLs are not accepted
by this typed slice.

## 11. Capability Discovery

Capability discovery is local and requires no credentials or network. The Swift
API and `meta-marketing-gateway-reader catalog list --product ads
[--domain <name>] [--api-version <tested-version>] --output json` return a
stable schema:

```json
{
  "schemaVersion": 1,
  "effectiveAPIVersion": "v26.0",
  "lastReviewed": "2026-08-15",
  "domains": [
    {
      "id": "campaigns",
      "operations": ["meta.ads.campaigns.get", "meta.ads.campaigns.list"],
      "availability": "typed",
      "fields": ["id", "name", "status"],
      "filtering": "structural",
      "pagination": ["after", "before"]
    }
  ]
}
```

The actual output is generated from the same descriptors/matrices used for
validation, never a duplicate handwritten list. Entries state:

- domain, operation ID, capability (`reader`), dispatchability, and availability;
- supported typed API versions and effective version;
- fields, presets, filter operators/value shapes, page bounds;
- insights subjects, levels, time options, breakdowns, and validation strength;
- whether the generic core can represent an operation not covered by typing.

Unknown versions or domains are explicit local errors. Capability output never
reports token presence, environment-variable names, account IDs, permissions,
business IDs, or live provider reachability.

## 12. CLI Contract

Commands mirror the operation matrix under `meta-marketing-gateway-reader ads`:

```text
ads ad-accounts list --fields <csv> [page flags]
ads ad-accounts get --account-id <id> --fields <csv>
ads campaigns|ad-sets|ads|ad-creatives list --account-id <id> --fields <csv> [--filter-file <path>] [page flags]
ads campaigns|ad-sets|ads|ad-creatives get --id <id> --fields <csv>
ads insights read --subject <kind:id> --fields <csv> [insights flags] [--filter-file <path>] [page flags]
catalog list --product ads [--domain <name>] [--api-version <tested-version>] --output json
```

Every network `ads` command also requires the shared
`--api-version <tested-version>` option. The offline `catalog list` accepts the
same option to inspect a tested matrix but does not resolve credentials.

The exact page flags are `--limit <1...500>`, `--after <cursor>`, and
`--before <cursor>`; `--after` and `--before` are mutually exclusive. The CLI
ad-account list is the closed `me` case. A non-default user node is available
only through the typed Swift request until a separately reviewed CLI need
exists.

The filter file is a JSON array of typed objects:

```json
[
  {
    "field": "effective_status",
    "operator": "IN",
    "value": ["ACTIVE"]
  }
]
```

Each field/operator/value is validated against the selected domain/version
matrix. Extra keys and raw nested JSON fragments are rejected.

`--filter-file` is optional, regular-file-only, terminal-symlink-rejecting,
UTF-8 JSON with a 64 KiB limit-plus-one read. It decodes into the typed filter
schema; it is not arbitrary provider JSON. Duplicate/unknown flags and stdin
fallback are rejected. Mutating command words are absent from the reader.

Normal output is a deterministic JSON envelope containing operation ID,
effective API version, `data`, and validated paging metadata. Human-readable
help may list field presets but never credentials. Raw request/response debug
logging is not provided.

## 13. Credentials, Privacy, and Errors

Kinko is the only credential store. Repository config may contain only a safe
environment-variable reference, never an access token or app secret. Documented
invocation is equivalent to:

```bash
kinko exec --env META_ACCESS_TOKEN -- \
  swift run meta-marketing-gateway-reader ads campaigns list \
  --api-version v26.0 --account-id act_123456789 --fields id,name
```

Only the explicit `META_ACCESS_TOKEN` allowlist (or a profile-specific safe
name selected by the credential foundation) is injected. No `.env` file is
created or read. Tokens are sent in the authorization mechanism selected by the
generic core, are redacted from errors, and are never written to result JSON,
logs, fixtures, snapshots, command history examples, or capability output.

Validation and file errors occur before credential resolution. Provider errors
retain an allowlisted status, stable Meta error code/subcode when safe, trace ID
when safe, and a generic message; raw request URLs, headers, bodies, and provider
messages that may reflect query values are not printed. Tests use sentinel
secrets and assert their absence from all outputs.

## 14. Response and Work Bounds

- The shared transport enforces timeout and response-body limits before decode.
- A single typed call returns one page only.
- Field, filter, cursor, filter-file, and page-size bounds are validated locally.
- JSON decoding is depth- and byte-bounded by the generic core.
- Rate-limit headers may be projected into coarse, non-secret telemetry only if
  the shared foundation defines and tests the projection; this feature does not
  expose raw headers.
- Retries are owned by the generic core and must be bounded, read-only, and
  cancellation-aware. This feature adds no hidden retry loop.

## 15. Deterministic Verification Contract

Tests must prove:

- every typed operation maps to its exact `GET` path and catalog ID;
- type-separated IDs reject path/query injection and account canonicalization is
  deterministic;
- required fields, deduplication, ordering, version/domain validation, and all
  field-expression rejection cases;
- filters serialize once, enforce matrix/value/count/byte limits, and never
  accept raw operator or raw JSON passthrough;
- before/after exclusivity, cursor/limit boundaries, paging decode, and request
  reconstruction without following URLs;
- tolerant enum and unknown-field decoding, lossless decimal/action insight
  shapes, malformed selected-field errors, and response bounds;
- insights date/time/level/breakdown structural rules and query encoding;
- capabilities are generated from dispatch descriptors, need no credential,
  and distinguish typed from generic-only coverage;
- validation failures resolve no credential and send no request;
- reader routing exposes no mutation and cannot dispatch writer operations;
- sentinel bearer/app-secret values never appear anywhere; filter/cursor values
  never appear in errors, help, capabilities, logs, or diagnostics. An exact
  validated cursor may appear only in the intended result paging object;
- all HTTP behavior uses injected fakes. Optional authorized integration tests
  use only Meta test assets and perform no billable or mutating action.

## 16. Review Record

### Design self-review

Decision: **accepted after correction**.

The first pass had three design defects. It allowed a forward-compatible raw
field escape inside typed requests, exposed provider paging URLs, and left
insights number decoding as ordinary `Double`. The accepted design removes raw
typed fields in favor of the generic core, reconstructs pages only from opaque
cursors and fixed typed requests, and preserves provider metric representations
losslessly. These are design defects because they change the public and security
contracts.

The self-review also clarified required non-empty selections, Kinko invocation,
filter-file bounds, version gating, and the local nature of capabilities.

### Independent adversarial design review

Decision: **accepted after correction**.

A separate adversarial pass found two medium design defects: pagination cursors
had no log/redaction rule, and capability output could be mistaken for live
permission discovery. The accepted design treats cursors as sensitive opaque
values, excludes them from logs, and declares discovery local, credential-free,
and non-probing. A subsequent design-plan consistency pass found one additional
medium design defect: describing returned cursors as "sanitized" could authorize
altering an opaque value and break continuation. The accepted wording now
requires exact validated cursor return only in the intended result paging
object. Exact page flags and the closed filter-file shape were also made
explicit as a low-severity clarity correction.

A final cross-feature reconciliation against the accepted Graph foundation and
delivery design found four medium integration defects: the typed design named
a second version type, returned a second page envelope, and omitted the shared
required `--api-version` option while inventing a parallel `capabilities` CLI
route. The accepted design now reuses `GraphAPIVersion` and `GraphPage`, requires
the shared version option for network commands, and contributes Ads descriptors
to `catalog list`. No parallel transport, credential, pagination, or CLI
foundation remains.

The pass also tested arbitrary-origin/version injection, nested field expansion,
filter JSON injection, terminal symlink and unbounded-file reads, ID path
injection, response drift, provider-error reflection, reader-to-writer routing,
secret persistence, and accidental paid activity. No high or medium design
finding remains.

## 17. Acceptance Criteria

- [x] Typed domain, fields, filters, pagination, insights, and capability
  contracts are explicit.
- [x] Typed coverage and endpoint-complete generic coverage are separated.
- [x] API drift, unknown fields/enums, and version support have defined behavior.
- [x] Kinko-only credentials and explicit environment allowlisting are normative.
- [x] Reader-only routing, bounds, redaction, and no-follow pagination are
  testable.
- [x] Self-review and independent adversarial review have no unresolved high or
  medium design findings.
- [x] No implementation, network call, spend, commit, or push is authorized by
  this design document.

## 18. Risks

| Risk | Mitigation |
|---|---|
| Meta versions and fields evolve quickly. | Central tested-version matrix, official-doc review date, tolerant response types, generic fallback. |
| Typed API falsely implies exhaustive provider validation. | Capability metadata labels structural versus provider validation. |
| Paging links can redirect or leak tokens. | Ignore provider URLs and rebuild from fixed operation plus bounded cursors. |
| Insights values lose precision or shape. | Preserve original JSON-compatible scalar/action representations. |
| Broad field/filter inputs recreate a generic tunnel. | Closed typed matrices; unmodeled inputs use the separately governed generic core. |
| Reader credentials could reach mutating routes. | Reader-only catalog dispatch, no mutation commands, negative routing tests. |
| Tests accidentally touch live assets or incur spend. | Injected fakes by default; Meta test assets only for separately authorized integration checks. |
