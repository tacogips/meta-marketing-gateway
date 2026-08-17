# Typed Ads Writer and Spend Safety

**Feature ID:** `meta-ads-writer-safety`
**Feature title:** Typed Ads writer and spend safety
**Issue reference:** `workflow:codex-design-and-implement-review-loop-session-732/communication:comm-002452`
**Workflow mode:** `issue-resolution`
**Status:** Accepted for implementation planning
**Reviewed:** 2026-08-15
**Implementation plan:** `impl-plans/meta-ads-writer-safety.md`
**Codex agent reference:** `../google-marketing-gateway`

## 1. Purpose and scope

This design defines the mutation boundary for the Swift Meta Marketing gateway.
It covers typed Ads mutations, generic Graph mutations, deterministic previews,
explicit confirmations, idempotency and replay defense, destructive-operation
controls, dev/test asset policy, and a strict live-spend authorization ceiling.

The design is deliberately fail-closed. A request being valid Graph API syntax
does not make it safe to apply. Reader and writer clients are separate Swift
types and executable products, and only the writer can reach mutation transport.
Typed major-domain APIs are the normal path. The generic Graph surface remains
endpoint-complete by accepting future relative Graph nodes/edges and parameters,
but a generic mutation must supply a validated safety policy and passes the same
preview/apply state machine as typed mutations.

This feature does not implement authentication setup, every typed Ads domain,
or the whole repository. It defines the contracts those slices must use.

## 2. Inputs, constraints, and repository findings

The target repository has no source tree or Swift package yet. The referenced
Google gateway supplies useful structural precedents but not reusable Meta
writer semantics.

| Input | Finding and consequence |
|---|---|
| Target root | The repository root is an empty, uncommitted repository at design time. All plan paths are prospective. |
| Reference root | `../google-marketing-gateway` separates reader, writer, admin, compatibility, and core products. Preserve the reader/writer separation, but do not copy Google credential persistence. |
| Credential rule | Kinko is the only credential store. Processes receive only explicitly allowlisted environment names through `kinko exec`; no `.env`, config-file secret, keychain fallback, CLI secret argument, or secret-valued log is permitted. |
| Mutation safety | Preview must be mutation-transport-free; it may make labeled, authenticated read-only observations. Apply must bind confirmation, current state, mutation intent, target account, and idempotency key. |
| Spend | Prefer sandbox/dev/test assets. Live-spend authorization must remain strictly below USD 20. The first release must not activate delivery, create billable campaigns, or raise live budgets. |
| External verification | Mocks and Meta test assets are preferred. No live mutation is required by this feature. |

## 3. Security and safety invariants

The following are release-blocking invariants:

1. `MetaMarketingReader` has no mutation method and accepts only logical reads.
2. `MetaMarketingWriter` is a distinct type and dependency boundary. A reader
   executable does not link its CLI routing to writer commands.
3. Transport accepts only `https://graph.facebook.com` and an explicitly
   configured, validated Graph API version. Callers cannot supply an absolute
   URL, authorization header, access token parameter, alternate host, redirect
   authorization, or arbitrary HTTP headers.
4. Every write follows `prepare -> preview -> confirm -> apply -> receipt`.
   There is no direct typed or generic `execute` escape hatch.
5. Preview is mutation-transport-free and performs no network mutation.
   Authenticated read-only preflight transport is allowed only when declared by
   policy, labeled in output, and routed through the reader boundary.
6. Apply recomputes the canonical intent digest and refuses a stale, changed,
   expired, wrong-profile, or wrong-account plan.
7. Within a journal namespace, an idempotency key binding is permanent: reuse
   with different canonical intent is always an error. An uncertain prior result
   is never replayed automatically.
8. Deletes, archive-like state changes, permission changes, ownership changes,
   audience deletion, and serving activation are destructive/high-risk even
   when the provider represents them as ordinary `POST` updates.
9. New Ads objects default to `PAUSED`. `ACTIVE` create or transition is not
   implemented in the first release.
10. The gateway does not authorize USD 20.00 or more in cumulative live-spend
    liability. The implementable first release authorizes USD 0 because live
    activation and live budget increases are denied.
11. No credential is loaded before local syntax, policy, and file-permission
    checks pass. Read-only preview observations may then resolve a reader
    credential; the mutation credential is not resolved until apply has also
    passed confirmation, current-state, and journal checks, and its non-secret
    actor/app identity is verified before the journal enters `inFlight`.
12. Logs, previews, receipts, errors, tests, and crash diagnostics never contain
    access tokens, app secrets, authorization headers, `appsecret_proof`, raw
    uploaded customer data, or full provider error bodies.

## 4. Architecture and trust boundaries

| Component | Responsibility | Forbidden behavior |
|---|---|---|
| `MetaGraphCore` | Versioned relative Graph request model, canonical JSON, official-origin URL construction, sanitized responses/errors. | Credential loading, arbitrary hosts, redirecting authorization, or mutation dispatch. |
| `MetaMarketingReader` | Generic Graph reads and typed reads/preflight observations. | `POST`/`DELETE` mutation routing based only on HTTP verb; access to writer transport. |
| `MetaMarketingWriter` | Typed mutations, policy-classified generic mutations, preview/apply engine, idempotency journal, receipts. | Direct execute, implicit confirmation, unknown-risk apply, or live activation in v1. |
| `MetaMarketingGatewayCLI` | Reader/writer subcommands, machine-readable previews, explicit flags, safe exit codes. | Token arguments, interactive secret prompts, hidden approval, or echoing request bodies. |
| `CredentialEnvironment` | Read named environment variables after safety gates. | Reading `.env`, credential JSON, shell history, or unallowlisted names. |
| `MutationJournal` | Non-secret idempotency state and sanitized receipts in a secure local directory. | Persisting credentials, raw request/response bodies, or silently clearing uncertain states. |

Executable products should be `meta-marketing-gateway-reader` and
`meta-marketing-gateway-writer`. A future compatibility executable may route to
either mode, but it must construct exactly one capability and cannot upgrade a
reader profile to writer behavior.

## 5. Typed and generic mutation contracts

### 5.1 Common protocol

Every mutation conforms conceptually to:

```swift
public protocol MetaMutation: Sendable, Encodable {
    associatedtype Output: Decodable & Sendable
    static var operation: MutationOperationDescriptor { get }
    var target: MutationTarget { get }
    var preconditions: MutationPreconditions { get }
    func validatedIntent() throws -> CanonicalMutationIntent
}
```

`MutationOperationDescriptor` is immutable library policy, not user input. It
declares stable operation ID, Graph method and path shape, capability, risk
class, spend effect, reversibility, test-asset support, required observation
fields, confirmation class, allowed parameters, response projection, and
redaction rules.

`CanonicalMutationIntent` includes the operation ID, Graph version, credential
profile name (never its values), stable non-secret Meta app and actor IDs,
journal namespace, business/ad-account/resource IDs, normalized parameters,
content hashes for approved uploads, expected state fingerprint, risk
classification, spend classification, and idempotency key. Dictionary keys are
sorted, number and Unicode encodings are normalized, and omitted values are
distinguished from explicit nulls. SHA-256 of those canonical bytes is the
`intentDigest`.

### 5.2 Initial typed Ads operations

The first typed slice should cover common object lifecycle operations while
remaining non-serving:

| Domain | Typed operations | V1 apply policy |
|---|---|---|
| Campaign | Create paused, update name/objective-compatible fields, pause, archive/delete where supported. | Create/update/pause allowed on test assets after confirmation; destructive transitions require elevated confirmation. Live create remains paused. |
| Ad set | Create paused, update targeting/schedule/bid/budget, pause. | Test assets only initially. Any budget-bearing live update denied. |
| Ad | Create paused, update creative association/name/tracking fields, pause. | Test assets only initially; no activation. |
| Creative | Create/update supported typed fields and approved local upload references. | Test assets first; secure-file checks and content hashes required. |
| Audience | Create/update; delete only as explicitly destructive. | Custom-audience membership upload is a separate sensitive-data design and is not enabled by this feature. |
| Ads rules | Create/update/enable/disable/delete. | Preview is required; enabling rules is treated as spend-affecting and denied on live assets in v1. |

Generated or hand-maintained enums must preserve an `unknown(String)` decode
case for forward-compatible responses. Request enums remain closed: an unknown
request value requires an explicit raw/generic request policy rather than a
string cast into a typed call.

### 5.3 Endpoint-complete generic Graph surface

`GenericGraphMutation` accepts an allowlisted Graph API version, relative
node/edge template, descriptor-authorized mutation method (initially `POST` or
`DELETE`), typed scalar/list/object parameters, optional secure file handles,
and a `MutationOperationDescriptor`. It never accepts a full URL,
access token field, auth header, arbitrary header, or redirect policy.

This keeps the transport capable of current and future Marketing API endpoints
without claiming they are safe by default. Built-in descriptors are compiled
and tested. The registry also accepts a versioned declarative descriptor bundle
after schema, official-origin, path, method, parameter, redaction, version, and
digest validation. A runtime descriptor cannot lower safety: it is forcibly
classified `unclassified/maxRisk`, destructive, spend-possible, and test-only,
regardless of fields in the bundle. It may apply only to a Meta-verified
non-billable sandbox/test asset with destructive-strength confirmation. A
future endpoint can therefore be previewed and exercised on test assets without
a transport or SDK API change. Live apply or a narrower classification still
requires a built-in reviewed descriptor and fixtures. The descriptor bundle and
its full SHA-256 digest are bound into the preview, journal, confirmation, and
receipt; prefix digests are rejected.

Runtime descriptors also pass immutable gateway rules that their bundle cannot
override. They cannot apply permission, ownership, business/ad-account access,
billing, payment, funding-source, account-spend-cap, account-status, audience-
membership/customer-data upload, token, or credential operations. They cannot
upload files or raw bytes. All directly and indirectly affected resource IDs
must be enumerated by a read-only closure resolver and independently verified as
non-billable test assets; an unknown, unresolvable, external, cross-business, or
live secondary resource makes the operation preview-only. Parameter names,
types, byte counts, and SHA-256 digests may appear, but all runtime parameter and
file values are opaque-redacted by default. Generic provider error messages and
bodies are discarded; only gateway-allowlisted structured codes and trace IDs
survive. These rules intentionally leave unfamiliar sensitive or cross-resource
operations previewable but not applyable until typed/built-in review.

Graph batch execution is not an idempotency mechanism. A batch is previewed as
an ordered set, gets one aggregate digest plus per-entry digests, and is applied
only if every entry passes. Partial provider results are journaled individually;
failed or uncertain entries are not automatically retried.

## 6. Preview, confirmation, and apply

### 6.1 Preview document

`prepare` validates the mutation and performs declared read-only observations.
It emits a versioned `MutationPreview` containing:

- preview schema version, operation ID, risk, reversibility, asset classification;
- credential profile name, stable non-secret Meta app/actor IDs, and target
  business/ad-account/resource IDs;
- redacted before/after field diff with defaults and provider-derived changes;
- spend impact in account currency and, when applicable, USD liability policy;
- precondition fingerprint and observation timestamp;
- idempotency key, `intentDigest`, expiry, required confirmation class;
- exact warnings, denied reasons, and whether apply is currently eligible.

The preview is safe to print or save and contains no credentials or raw private
payloads. Uploads appear as filename-safe labels, byte counts, media type, and
SHA-256 content hashes. Preview JSON is deterministic so tests can use fixtures.

### 6.2 Confirmation classes

| Class | Examples | Apply requirements |
|---|---|---|
| `standard` | Rename, paused create on a test asset, non-serving metadata update. | `--confirm <intentDigest>` and unexpired exact preview. |
| `highRisk` | Targeting, bid/budget fields, rule definition, live-asset paused create. | Standard requirements plus `--allow-high-risk` and a second confirmation token derived from operation ID and target ID. |
| `destructive` | Delete/archive, detach ownership/access, irreversible audience action. | High-risk requirements plus `--allow-destructive`; exact resource ID must be repeated; batch destructive apply is denied by default. |
| `spendAffecting` | Activation, budget increase, enabling an automated rule. | Destructive-strength confirmation plus spend ledger reservation and ceiling proof. Denied on live assets in v1. |

Interactive TTY prompts may collect the same explicit values, but never weaken
non-interactive requirements. `--yes`, environment-based approval, confirmation
embedded in a request file, and prefix/partial digest matching are forbidden.

### 6.3 Apply algorithm

1. Parse request and secure files; validate all local inputs.
2. Load the preview and verify schema, expiry, exact identifiers, flags, and
   confirmation values.
3. Reconstruct and canonicalize intent; require the same digest.
4. Lock the mutation journal; bind the idempotency key to the digest and target.
5. Repeat required read-only observations using the preview-bound app/actor
   identity and require the same state fingerprint or stronger preconditions.
6. Enforce asset classification, affected-resource closure, immutable deny
   rules, destructive policy, and spend policy.
7. Resolve the Kinko-injected mutation credential without sending a mutation;
   obtain its provider-authenticated, non-secret app and actor IDs and require
   an exact match with the preview identity. Token rotation is allowed only when
   the stable app/actor identity is unchanged.
8. Mark the record `inFlight` atomically.
9. Send exactly one provider mutation; do not follow cross-origin redirects.
10. Atomically store `succeeded`, `failedSafeToRetry`, or `outcomeUnknown` plus a
   sanitized receipt. Never infer failure from a transport timeout after send.
11. Return the receipt. Automatic retries are allowed only before any request
    bytes are sent or for a provider-documented operation-specific idempotency
    facility encoded by its descriptor.

## 7. Idempotency, replay defense, and reconciliation

An idempotency key is caller-supplied for automation or generated at `prepare`.
Its journal scope is `(journalNamespace, credentialProfile, metaAppID,
metaActorID, businessID, adAccountID, operationID, idempotencyKey)`. The value is
the canonical intent digest.

| Journal state | Repeat behavior |
|---|---|
| `prepared` | Same digest may continue with exact confirmation before expiry. |
| `inFlight` | Deny repeat; require reconciliation. |
| `succeeded` | Return the existing sanitized receipt without network mutation. |
| `failedSafeToRetry` | Same digest may retry only when the descriptor marks the failure safe and a fresh preview reconfirms current state. |
| `outcomeUnknown` | Deny retry. A typed reconciliation read must prove effect or non-effect; otherwise require a new, explicitly reviewed recovery operation, never a force replay. |

Terminal receipt payloads may be compacted, but the namespace, scoped key,
intent digest, target, terminal state, and receipt digest remain as permanent
tombstones and are never evicted or rebound. Namespace creation is an explicit
local administrative action; it is not available from mutation apply, is denied
while any prior journal exists with unresolved states, and invalidates every
older preview. A missing journal or namespace causes apply to fail closed rather
than silently creating fresh state.

The journal uses atomic replace, a process lock, directory mode `0700`, and file
mode `0600`; it stores no credential material. Truncation, unreadable ownership,
symlinks, structural corruption, broken hash links, or duplicate sequence
numbers fail closed. Retention is policy-controlled but cannot evict `inFlight`
or `outcomeUnknown` records or permanent key tombstones. A monotonic sequence and
hash chain detect internal corruption but cannot detect restoration of a
complete older journal snapshot without a trusted external anchor. Restoring a
snapshot is therefore an explicit residual risk; backups and namespace recovery
procedures must preserve the newest head. This is operational metadata, so
Kinko-only credential storage is not violated.

Optimistic concurrency uses typed observed fields where available. If Meta does
not expose a stable revision for an object, the gateway hashes the exact fields
declared by the descriptor and refuses apply when they differ. This reduces but
cannot eliminate races after the final read; receipts disclose that limitation.

## 8. Destructive-operation controls

- Classification follows business effect, not HTTP method or endpoint name.
- Generic `DELETE` is always destructive. Generic `POST` is max-risk until a
  built-in descriptor proves a narrower class.
- Prefer reversible state transitions such as `PAUSED` over delete/archive.
- Preview must name affected resource IDs and known dependent objects/counts.
- Destructive bulk operations are not implemented in v1. Later support requires
  per-resource previews and confirmations plus a bounded maximum batch size.
- Destructive mutations require a fresh preview with a short, configurable
  expiry and cannot use a preview created before the last observed update.
- Permission, ownership, billing, payment, account-spend-cap, and business asset
  assignment mutations are excluded until separate typed designs are accepted.
- A successful response is not proof of final provider state. When material,
  the writer performs a typed read-back and records `verified`, `pending`, or
  `verificationUnavailable` without replaying the mutation.

## 9. Test assets and live-spend ceiling

### 9.1 Asset classification

Every plan classifies its target as `verifiedNonBillableTest` or `live`.
`verifiedNonBillableTest` requires current provider evidence that the asset is a
Meta sandbox/test asset incapable of billing or delivery. Every other target is
`live`, including development-owned real ad accounts, paused production assets,
and anything unverified. Profile metadata can identify an expected test asset
but cannot establish the safety class without the provider observation.

Tests use, in order: pure mocks, URL-protocol/transport fakes, recorded sanitized
fixtures, Meta Marketing API sandbox/test accounts, development-owned paused
assets, and finally live assets only when necessary and explicitly approved.
The setup identity, if interactive Meta setup is unavoidable, is
`taco-dev-sandbox@mutvar.com`.

### 9.2 Spend policy

The issue ceiling is interpreted strictly as gateway-authorized cumulative live
liability `< USD 20.00`; USD 20.00 fails. The ceiling is not a claim that this
process controls concurrent Ads Manager users, existing delivery, Meta pacing,
currency conversion, taxes, or provider behavior outside the gateway.

For v1:

- all creates are `PAUSED`;
- live activation, live budget increases, rule enablement, and any other action
  capable of delivery are denied;
- non-USD live spend-affecting operations are denied because no reviewed FX
  policy exists;
- the live-spend ledger therefore authorizes exactly USD 0.00.

A later live-spend implementation must be separately reviewed and must reserve
integer USD cents in the locked journal, prove cumulative outstanding and
completed authorization is at most 1,999 cents for the workflow, require a
fresh account-currency and account-state observation, define conservative
provider pacing liability, and reconcile reservations. Failure to calculate a
hard upper bound denies apply. The CLI must display that this is an authorization
ceiling rather than a guarantee of final invoiced spend.

## 10. Credentials, privacy, and logging

Supported secret names are centrally allowlisted, for example
`META_ACCESS_TOKEN`, `META_APP_SECRET`, and an optional descriptor-approved
system-user token name. The gateway rejects tokens in flags, query parameters,
request JSON, config files, and stdin. It never enumerates or prints the process
environment.

Example invocations use an explicit Kinko environment allowlist:

```bash
kinko exec --env META_ACCESS_TOKEN,META_APP_SECRET -- \
  swift run meta-marketing-gateway-writer ads campaign preview --request request.json

kinko exec --env META_ACCESS_TOKEN,META_APP_SECRET -- \
  swift run meta-marketing-gateway-writer ads campaign apply \
  --preview preview.json --confirm <full-intent-digest>
```

The `kinko exec --env KEY[,KEY...] -- command` syntax was verified against the
installed CLI on 2026-08-15 with `kinko exec --help`. Tests use sentinel secrets
and assert their absence from stdout, stderr, errors, previews, receipts, journal
files, and HTTP diagnostics. Provider `fbtrace_id`, safe error code/subcode,
operation ID, and field path may be retained; provider messages and bodies
require allowlisted field extraction and redaction.

## 11. CLI and library failure semantics

Machine-readable CLI output uses a stable envelope and nonzero categorized exit
codes: validation, preview-denied, confirmation, stale-plan, idempotency-conflict,
outcome-unknown, credential, provider-rejected, and verification-failed. The
receipt exposes no request replay command containing secrets.

Cancellation before send records no mutation. Cancellation after send records
`outcomeUnknown` unless an authoritative response was received. `SIGINT`,
timeout, decoding failure, 5xx, and connection loss are tested on both sides of
the send boundary.

Library APIs use injected clocks, UUID/key generators, journal, credential
provider, reader preflight, and HTTP transport so all state transitions can be
tested without network or secret access.

## 12. Official-source policy

Marketing API versions, endpoint fields, permissions, sandbox behavior,
validation parameters, and spending behavior are time-sensitive. Implementers
must recheck official Meta sources on the implementation date and record the
checked version in descriptor fixtures. Useful primary sources include:

- [Meta Marketing API documentation](https://developers.facebook.com/docs/marketing-api/)
- [Meta official Marketing API Postman workspace](https://www.postman.com/meta/facebook-marketing-api/overview)
- [Meta official Python Business SDK](https://github.com/facebook/facebook-python-business-sdk)
- [Campaign reference](https://developers.facebook.com/docs/marketing-api/reference/ad-campaign-group)
- [Ad Account reference](https://developers.facebook.com/docs/marketing-api/reference/ad-account)
- [Graph API batch requests](https://developers.facebook.com/docs/graph-api/making-multiple-requests)

Meta's official SDK demonstrates CRUD and batch capabilities but does not make
batch execution a replay-safety guarantee. Provider-specific validation-only or
idempotency behavior may be used only after its current official contract is
verified and encoded per operation; it is never assumed globally.

## 13. Decisions and rejected alternatives

| Decision | Rationale |
|---|---|
| Separate reader and writer products and types. | Compile-time/API separation prevents accidental mutation through a reader client. |
| Require the same safety state machine for typed and generic mutations. | Endpoint completeness must not become a raw unsafe proxy. |
| Permit runtime generic descriptors only at forced maximum risk on verified non-billable test assets. | Future endpoint coverage does not require a transport change, while caller assertions cannot lower risk or enable live apply. |
| Use canonical intent digests plus fresh state observations. | Confirmation must bind exact action, target, inputs, and observed state. |
| Treat transport uncertainty as `outcomeUnknown`. | Blind retries can duplicate non-idempotent mutations. |
| Keep the journal local and secret-free. | Durable replay defense is required; Kinko remains the only credential store. |
| Deny live delivery in v1. | It provides an enforceable USD 0 authorization while the later `< USD 20` liability model receives separate review. |
| Do not trust CLI policy manifests in v1. | A caller-controlled risk label would bypass safety classification. |

Rejected alternatives include a universal `--force`, confirmation by `--yes`,
automatic retries after timeouts, using Graph batch as idempotency, storing
tokens in profiles or `.env`, trusting resource names or ownership as test
classification, allowing runtime descriptors to lower risk, and converting
non-USD budgets using an unpinned live exchange rate.

## 14. Acceptance criteria

- Reader code cannot construct or send a mutation.
- Typed campaign, ad set, ad, creative, audience, and ads-rule models have
  explicit operation descriptors and forward-compatible response decoding.
- Generic relative Graph mutation construction supports future endpoints;
  runtime descriptors are apply-capable only at forced maximum risk on verified
  non-billable test assets after immutable exclusions and complete affected-
  resource closure checks, while live apply requires a built-in descriptor.
- The preview artifact is deterministic and credential-free; preview execution
  is mutation-free and binds exact intent, target, preconditions, idempotency
  key, risk, and spend disposition.
- Standard, high-risk, destructive, and spend-affecting confirmations are
  independently tested.
- Duplicate, conflicting, in-flight, succeeded, safe-retry, and unknown-outcome
  journal states have deterministic behavior across process restarts.
- All destructive and live-spend bypass attempts fail closed.
- V1 cannot activate live delivery or increase live budget, so authorized live
  spend is USD 0 and necessarily below USD 20.
- Kinko-only credential injection and explicit environment allowlists are shown
  in docs and enforced by code/tests.
- Unit and integration tests use mocks or Meta test assets; no billable campaign
  is created by verification.

## 15. Risks and residual limitations

| Risk | Mitigation / residual limitation |
|---|---|
| Local journal deletion or host compromise | Secure permissions, locks, hash chain, and fail-closed corruption checks reduce risk; a local client cannot defend against a fully compromised host. |
| Provider state changes after final observation | Exact field fingerprints reduce the race; read-back receipts disclose remaining race and final state. |
| Meta fields and behaviors change by Graph version | Pin versions, record verification dates, preserve unknown response values, and recheck official docs per implementation. |
| Generic surface is mistaken for unrestricted apply | API naming, preview denial, descriptor requirement, and tests make the policy boundary explicit. |
| Existing or concurrent live delivery exceeds USD 20 | V1 does not activate or raise budgets; later authorization ceiling cannot guarantee spend caused outside this gateway. |
| Sanitization removes useful diagnostics | Retain safe structured codes, operation ID, field path, and `fbtrace_id`; keep raw bodies out of normal artifacts. |

## 16. Design verification

```bash
test -f design-docs/meta-ads-writer-safety.md
rg -n "Kinko|kinko exec|USD 20|idempot|outcomeUnknown|allow-destructive|GenericGraphMutation" \
  design-docs/meta-ads-writer-safety.md
git diff --check -- design-docs/meta-ads-writer-safety.md
```
