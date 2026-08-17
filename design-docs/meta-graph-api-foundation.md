# Generic Graph API and Credential Foundation

**Feature ID:** `meta-graph-foundation`

**Feature title:** Generic Graph API and credential foundation

**Issue reference:** `workflow:codex-design-and-implement-review-loop-session-732/communication:comm-002452`

**Workflow mode:** `issue-resolution`

**Status:** Accepted for implementation planning

**Reviewed:** 2026-08-15

**Implementation plan:** `impl-plans/meta-graph-api-foundation.md`

**Codex agent reference:** `../google-marketing-gateway`

## 1. Scope and outcome

This feature establishes the reusable Swift transport and credential boundary for
the Meta Marketing gateway. It must make any current or future Meta Graph API
node or edge expressible without waiting for a typed SDK release, while keeping
typed Ads-domain APIs able to share the same transport. It covers:

- separate reader and writer clients and executables;
- Kinko-only credential injection;
- explicit Graph API versioning;
- generic single, paginated, batch, multipart, and resumable requests;
- bounded retries, response handling, and sanitized diagnostics;
- a generic CLI surface that cannot become an arbitrary HTTP proxy; and
- protocols and fixtures that make all behavior testable without live assets.

Typed Campaign, Ad Set, Ad, Creative, Audience, Insights, Business, Account,
Pixel, Catalog, Lead, and related APIs are downstream features. Authentication
setup in Meta UI, webhook serving, typed model breadth, and live campaign
creation are outside this feature.

## 2. Repository findings and reference disposition

The target repository is an empty Git repository at review time: it has no
package manifest, source, test, or policy files. The reference repository is a
Swift 6 package with core, reader, writer, admin, and compatibility products.
Its useful patterns are protocol-based HTTP injection, redirect rejection,
separate executable modes, pre-credential input validation, and fixture-driven
CLI tests.

The reference repository's OAuth lifecycle, local credential profiles, token
stores, config-based secret discovery, and compatibility executable are not
copied. They conflict with the feature contract that Kinko is the only
credential store. The new package will share structural patterns, not Google
product semantics or credential persistence.

## 3. Official Meta baseline

Implementation must recheck these official pages on the day code behavior is
introduced because versions, limits, retry guidance, hosts, and endpoint
availability can change:

- [Graph API overview](https://developers.facebook.com/docs/graph-api/overview/)
- [Graph API versioning](https://developers.facebook.com/docs/graph-api/guides/versioning/)
- [Graph API changelog](https://developers.facebook.com/docs/graph-api/changelog/)
- [Batch requests](https://developers.facebook.com/docs/graph-api/batch-requests/)
- [Result pagination](https://developers.facebook.com/docs/graph-api/results/)
- [Error handling](https://developers.facebook.com/docs/graph-api/guides/error-handling/)
- [Secure requests](https://developers.facebook.com/docs/graph-api/guides/secure-requests/)
- [Access tokens](https://developers.facebook.com/docs/facebook-login/access-tokens/)
- [Marketing API overview](https://developers.facebook.com/docs/marketing-apis/)

The foundation does not label any numeric Graph version as "latest." A version
is always explicit and visible in the request. Numeric provider limits are
constants with a documentation URL and verification date, not undocumented
assumptions embedded throughout the code.

## 4. Architecture

```text
reader CLI -> MetaGraphReader ----\
                                  -> GraphExecutor -> GraphTransport -> Meta HTTPS
writer CLI -> MetaGraphWriter ----/         |
        |                                   +-> RetryPolicy
        +-> mutation plan/apply gate        +-> ErrorSanitizer

Kinko -- explicit env allowlist -> process environment -> in-memory credentials
```

The package products are:

| Product | Responsibility |
|---|---|
| `MetaMarketingGatewayCore` | Request/response models, credential resolver, transport, pagination, batching, uploads, retries, sanitization, and client protocols. |
| `meta-marketing-gateway-reader` | Generic reads plus later typed reader commands. It never exposes generic `POST` or `DELETE`. |
| `meta-marketing-gateway-writer` | Generic `POST` and `DELETE`, upload flows, and later typed mutates; every generic mutation uses plan/apply controls. It may expose `GET` only for mutation verification. |

There is no all-capabilities compatibility binary. Importable public clients
remain distinct even though they use internal shared execution machinery.

### 4.1 Core types

- `GraphAPIVersion`: validated `v<major>.<minor>` value; required at client
  initialization or per command and serialized as the first URL path segment.
- `GraphPath`: one or more untrusted logical path segments. It rejects schemes,
  hosts, empty segments, dot segments, backslashes, control characters, and
  encoded path separators before applying canonical percent encoding once.
- `GraphQuery`: ordered multimap of names and values so repeated and structured
  parameters survive without accepting a raw query string.
- `GraphRequest`: method, version, path, query, body, expected response kind,
  and safety metadata. It cannot contain an origin or authorization header.
- `GraphResponse`: status, safe headers, raw response bytes, and decoded JSON on
  demand. Response bodies are returned to the caller but never logged.
- `GraphTransport`: `Sendable` protocol accepting a fully validated internal
  request, enabling deterministic fakes.
- `MetaGraphReader` and `MetaGraphWriter`: public capability-specific protocols
  and concrete clients; neither can downcast into the other's capability.

`GraphBody` supports no body, form fields, JSON bytes produced by an encoder,
multipart parts, and a bounded file stream. Generic callers cannot supply raw
HTTP headers. An allowlisted `GraphRequestOption` type covers explicitly needed
Meta options without admitting `Authorization`, `Host`, proxy, redirect, or
content-length overrides.

## 5. Request construction and origin policy

Normal Graph calls use HTTPS and the fixed `graph.facebook.com` origin. Upload
strategies may use only additional Meta origins documented for that exact flow,
such as `graph-video.facebook.com` or `rupload.facebook.com`, behind a distinct
`UploadOrigin` enum. No public initializer accepts a hostname or absolute URL.

All requests must:

1. include an explicit `GraphAPIVersion` in the path;
2. encode logical path and query components exactly once;
3. reject `access_token`, `appsecret_proof`, and equivalent credential fields in
   user-supplied query, form, JSON-auth envelopes, and multipart metadata;
4. inject authorization after all user-controlled validation succeeds;
5. use an ephemeral session, fixed timeouts, and no cookie or URL cache;
6. reject redirects instead of forwarding authorization or upload bytes; and
7. impose request, response, elapsed-time, and decompression bounds.

The generic surface accepts the Graph protocol's supported request methods
(`GET`, `POST`, and `DELETE`) through capability-specific entry points. Method
and business effect are not treated as interchangeable: later typed read
operations that Meta models as `POST` require reviewed reader descriptors and
do not make generic `POST` available in the reader.

This design is endpoint-complete at the protocol layer because callers select a
validated relative node/edge path, ordered parameters, version, supported
method, and supported body strategy. It does not imply that the token has every
permission, the app has review approval, or every endpoint is callable by the
reader binary.

## 6. Kinko-only authentication

Kinko is the credential store and injection boundary. The gateway reads secret
values only from explicitly named environment variables in process memory. It
does not implement login, refresh, exchange, token persistence, `.env` loading,
keychain access, config-file secrets, command-line token flags, stdin token
prompts, or secret-valued defaults.

The initial credential contract is:

| Environment key | Required | Use |
|---|---:|---|
| `META_ACCESS_TOKEN` | yes | Authorization for Graph requests. |
| `META_APP_SECRET` | optional | Compute `appsecret_proof` in memory when the selected policy requires it. |

Invocation is explicit and narrow:

```bash
kinko exec --env META_ACCESS_TOKEN -- \
  swift run meta-marketing-gateway-reader graph get --api-version vNN.N --path me

swift run meta-marketing-gateway-writer graph post --api-version vNN.N \
  --path act_ID/example --request-file request.json --plan-out plan.json

kinko exec --env META_ACCESS_TOKEN,META_APP_SECRET -- \
  swift run meta-marketing-gateway-writer graph post --api-version vNN.N \
  --path act_ID/example --request-file request.json --apply plan.json \
  --confirm PLAN_DIGEST
```

Documentation and scripts must never recommend `kinko exec --all`. The gateway
diagnoses missing variable names, never values. Tokens are placed in the
`Authorization: Bearer` header. If `appsecret_proof` is enabled it is computed
with an injected app secret; references are released when the credential scope
ends, without claiming memory can be reliably zeroed by Swift.

`CredentialSource` is intentionally not a general protocol in the public API;
production uses `KinkoEnvironmentCredentials`. Tests inject a package-internal
fixture provider containing obvious non-secret sentinels. This prevents a later
file-backed implementation from silently becoming supported production policy.

## 7. Capability and CLI safety

### Reader

The reader generic command accepts only `graph get`. It validates version, path,
query input, output limits, and pagination budgets before resolving
`META_ACCESS_TOKEN`. It cannot create a generic body. Later typed report commands
using `POST` must be individually cataloged as logical reads and tested to be
unreachable from the writer-free generic router.

### Writer

The writer generic command accepts `graph post`, `graph delete`, upload, and
batch requests containing mutations. A mutation is a two-step operation:

- `--request-file <file> --plan-out <plan-file>` validates the request source and
  writes a secret-free canonical plan with method, version, relative path,
  parameter names, request-source hash, body hash/size, file metadata, and risk
  classification; it performs no network request and does not resolve
  credentials.
- `--request-file <file> --apply <plan-file> --confirm <plan-digest>` reloads and
  revalidates the request source, recomputes the plan, requires the matching
  digest, resolves credentials only after confirmation, and executes.

Plans never contain response data, body values, file contents, request-file
paths, credential values, or authorization material. A conservative classifier
labels spend, delivery, deletion, access, and unknown high-impact mutations.
High-impact generic CLI apply requires a second explicit risk acknowledgement
bound to the plan digest as `--acknowledge-high-impact <plan-digest>`. It is not
permanently denied, because the generic writer must remain capable of current
and future endpoints; authorization to build the capability is not
authorization to exercise it against live assets. This implementation/review
workflow performs no live mutation and spends USD 0, with USD 20 as a hard
ceiling if a later explicitly authorized check is needed.

### CLI input files

Query/body/batch/plan files must be regular, owner-readable files; symlinks and
files writable by other users are rejected. Readers use descriptor-relative
file paths only where a command explicitly permits them. Every parser enforces
byte, nesting, item-count, string-length, and numeric bounds before credential
resolution. Output files are created atomically with owner-only permissions and
will not overwrite an existing file without an explicit non-default option.

## 8. Pagination

`GraphPage<T>` decodes `data`, optional `summary`, and paging cursors/links while
retaining unknown fields. The iterator defaults to one page; auto-pagination
requires explicit budgets for maximum pages, items, response bytes, and elapsed
time.

The client never blindly fetches `paging.next`. It parses the link, requires
HTTPS, validates an allowed Meta Graph origin and the selected version, rejects
userinfo/fragments/unexpected ports, removes any returned credential query
fields, and reconstructs the next request with the current in-memory
authorization. Cursor cycles and repeated URLs terminate with a safe error.
Callers can instead request the opaque `after` or `before` cursor and build the
next request through the same validated path.

## 9. Batch requests

`GraphBatchRequest` contains individually validated relative subrequests,
optional stable names/dependencies, and optional attached-file references. Each
subrequest passes the same path, query, reserved-auth, body, and capability
checks as a single request. The reader rejects a batch containing any method or
descriptor not permitted for reading; the writer applies plan/digest controls
to the entire canonical batch.

The library validates dependency graphs for missing names and cycles. It
enforces the current documented provider item limit through a dated constant,
plus stricter configurable byte/file budgets. Batch results preserve subrequest
order and expose status, safe headers, decoded body, and a sanitized error per
item. A transport-level failure may be retried under the normal rules; the
executor never automatically replays a mixed or mutating batch after receiving
any provider response.

## 10. Uploads

Small multipart uploads use streaming body parts with generated boundaries and
known lengths. Files are opened only after validation, are not followed through
symlinks, and are checked again after opening to reduce replacement races. File
names are sanitized, MIME types are caller-selected from an allowlist or safely
defaulted, and bytes never enter diagnostics or plans.

Large or resumable uploads use an `UploadSessionDriver` state machine:

```text
start -> transfer(offset...offset+n) -> finish -> completed
                 |                         |
                 +-> query/reconcile ------+
```

Each Meta upload family supplies a reviewed strategy defining official origin,
phase parameters, offset semantics, size limits, and completion decoding.
Generic callers cannot invent an upload host or phase protocol. Resume and
offset reconciliation are supported only within the running command. Provider
session identifiers stay in memory and are never written to local state or
printed. Cross-process resume is deferred until a separately reviewed Kinko
write/read lifecycle exists; the foundation must not persist an upload session
identifier outside Kinko or invent an unsafe handoff path.

## 11. Retry and throttling policy

Retries are bounded exponential backoff with full jitter, an injected clock and
random source, a maximum attempt count, and an elapsed-time budget. The policy
observes safe provider guidance such as HTTP status, structured Graph error
code/subcode, `is_transient`, and retry headers, but all recognized values are
covered by fixtures and linked to the official error-handling documentation.

- `GET` may retry transient transport failures, throttling, and eligible 5xx or
  structured transient errors.
- `POST`, `DELETE`, and a mixed/mutating batch are not automatically retried
  after bytes may have reached Meta unless a reviewed typed operation proves an
  idempotency/reconciliation contract.
- An upload chunk retries only when the strategy can query/reconcile the remote
  offset; completion is not replayed blindly.
- Authentication, permission, validation, policy, and non-transient errors are
  not retried.
- Cancellation stops immediately; concurrency and per-host in-flight work are
  bounded to prevent a retry storm.

The error returned after exhaustion records attempt count and elapsed duration,
not request bodies or credentials.

## 12. Errors, logging, and output

Provider errors are decoded into an internal shape that can recognize `type`,
numeric `code`, numeric `error_subcode`, `is_transient`, and `fbtrace_id`.
Externally safe diagnostics contain operation kind, HTTP status, numeric codes,
transient classification, retry count, and a strictly validated trace ID.
Provider `message`, user title/message, raw headers, raw body, URL query, body
values, file paths, and tokens are omitted by default because they can contain
sensitive data.

The sanitizer performs defense in depth over every error boundary, including
malformed JSON, transport descriptions, redirect locations, multipart failures,
batch subresponses, and unexpected exceptions. It redacts exact in-memory
secret values before rendering and then applies structural patterns for bearer
tokens, `access_token`, `appsecret_proof`, cookies, and URL credentials. Debug
logging is metadata-only and uses parameter names plus sizes/hashes, never
values. Test fixtures place sentinel secrets in every possible carrier and
assert they do not appear in stdout, stderr, thrown descriptions, snapshots, or
plans.

Generic response payloads are user-requested output, not logs. Inline output has
a byte cap. Larger or binary output requires an explicit owner-only output file;
partial files are removed or renamed as incomplete without printing content.

## 13. Public API sketch

```swift
public protocol MetaGraphReading: Sendable {
  func get(_ request: GraphReadRequest) async throws -> GraphResponse
  func pages(_ request: GraphReadRequest, budget: PaginationBudget)
    -> AsyncThrowingStream<GraphPage<Data>, Error>
  func batch(_ request: GraphReadBatch) async throws -> GraphBatchResponse
}

public protocol MetaGraphWriting: Sendable {
  func apply(_ plan: ConfirmedMutationPlan) async throws -> GraphResponse
  func upload(_ plan: ConfirmedUploadPlan) async throws -> GraphResponse
  func batch(_ plan: ConfirmedBatchPlan) async throws -> GraphBatchResponse
}
```

Typed domain modules depend on these protocols and translate typed models into
validated generic requests. They never call `URLSession` directly.

## 14. Test strategy and acceptance criteria

All normal verification uses fake transports and Meta-shaped fixtures. URL
construction tests are table-driven across path characters, repeated query
keys, versions, methods, bodies, and forbidden absolute/encoded forms.
Pagination, batch, upload, and retry tests use deterministic clocks and scripted
responses. CLI subprocess tests use only sentinel variables injected through
`kinko exec --env` where Kinko integration itself is under test; unit tests do
not require a real vault.

The design is satisfied when implementation proves:

- reader code cannot dispatch generic mutation methods and writer apply cannot
  bypass a confirmed canonical plan;
- every request uses a fixed reviewed Meta origin and explicit version;
- Kinko allowlisted environment injection is the only documented production
  credential path and no secret persistence API exists;
- pagination budgets and next-link origin/version checks stop abuse;
- batch subrequests and uploads receive the same validation as single calls;
- retries never ambiguously replay generic mutations;
- sentinel credentials are absent from all diagnostics and artifacts;
- mock tests, lint, build, CLI help, and package checks succeed with USD 0 spend;
  and
- no commit, push, publish, deploy, or live campaign creation occurs.

## 15. Decisions from review

| Decision | Reason |
|---|---|
| Keep public reader and writer protocols separate. | A mode flag on one client is easier to misuse and weaker at compile time. |
| Allow arbitrary validated relative Graph paths, not arbitrary URLs. | This preserves endpoint completeness without creating an authenticated proxy. |
| Require explicit version per client/command. | It prevents unversioned behavior and avoids hard-coding a changing "latest." |
| Restrict generic reader to `GET`. | `POST` may be a logical read only after endpoint-specific review. |
| Require request-source/plan/digest/apply for generic mutations. | The request source remains executable while the separate value-free plan can be reviewed and bound to it. |
| Add digest-bound high-impact acknowledgement instead of permanent denial. | Safety defaults remain strong without contradicting endpoint-complete generic execution. |
| Reconstruct pagination links. | Provider links can contain credentials and must not be trusted as ready-to-send URLs. |
| Disable ambiguous mutation retries. | Meta endpoints do not share one universal idempotency guarantee. |
| Make resumable upload behavior strategy-specific. | Upload hosts and phase contracts differ and are time-sensitive. |
| Keep tests and default verification offline. | Mocks and Meta test assets satisfy this foundation without spend or durable effects. |

## 16. Risks and mitigations

| Risk | Mitigation |
|---|---|
| A relative-path escape turns the SDK into an arbitrary proxy. | Typed path/query components, canonical encoding, fixed origin enums, redirect rejection, adversarial URL tests. |
| Kinko secrets leak through CLI, errors, plans, or pagination URLs. | No token flags/files, reserved-key rejection, header injection last, next-link reconstruction, layered sanitization, sentinel tests. |
| Reader/writer separation is cosmetic. | Separate products/protocols/routers and negative cross-capability tests. |
| A retry duplicates a mutation or spend-affecting action. | No ambiguous generic mutation retry; typed reconciliation is required to opt in. |
| Generic writer reaches a billable activation endpoint unintentionally. | Risk classification, plan/digest confirmation, second high-impact acknowledgement, no live mutation in verification, and later typed guards. |
| Provider version, batch limit, host, or error behavior changes. | Explicit versions, dated constants, official links, implementation-date verification, fixture isolation. |
| Unbounded pagination, batch, response, or upload exhausts resources. | Independent item, byte, page, file, time, concurrency, and decompression budgets. |
| Sanitization removes useful debugging context. | Preserve safe status/codes/transient flag/validated trace ID and deterministic local request digest. |
