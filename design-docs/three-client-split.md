# Reader, Writer, and Deleter Capability Split

**Workflow:** `codex-deepdesign-session-760`

**Status:** Proposed for deep, broad, and adversarial review

**Risk:** Critical

**Design authority:** This document supersedes the two-client ownership,
generic writer `DELETE`, deletion policy, activation prohibition, and USD 0
live-acceptance portions of
`design-docs/specs/design-production-safe-reader-writer-completion.md`. The
earlier document and
`design-docs/specs/design-mutation-authorization-journal-authentication.md`
remain authoritative where this document does not replace them, especially for
canonicalization, authenticated journals, trusted heads, crash recovery,
credential timing, and sanitized diagnostics.

**Implementation plan:** `impl-plans/active/three-client-split.md` (downstream
artifact; it is not created by this design-only handoff)

**Contract date:** 2026-08-16

## 1. Outcome

The gateway becomes three separately linked public libraries and three thin
executables:

- Reader can represent and transport only `GET`.
- Writer can represent and transport only non-delete `POST` mutations,
  including create, update, `PAUSED`, and tightly controlled `ACTIVE`
  transitions.
- Deleter alone can represent and transport physical Graph `DELETE` requests.

The split is structural, not a runtime mode switch. No shared public type has a
method field. A program linking only Reader or Writer has no `DELETE` request,
method, transport, catalog row, CLI route, or Deleter dependency to import.
Typed major Ads operations and conservative generic relative-path operations
both require an exact, operation-specific, enabled catalog entry before network
transport, except for the closed exact typed acceptance disposition in Section
5. Unknown operations remain useful as offline analyses but fail closed for
transport.

The existing reader URL/origin validation, writer authorization and journal
hardening, trusted-head protocol, secret handling, and deterministic release
checks are preserved and specialized rather than replaced.

## 2. Goals, non-goals, and acceptance criteria

### Goals

1. Prove method authority at compile time and package-link time, not by naming
   conventions or a late runtime check.
2. Keep deletion out of Writer while retaining its non-delete mutation safety
   work.
3. Give Deleter an independent catalog projection, CLI, policy, confirmation,
   replay/journal namespace, tests, documentation, and release archive.
4. Support typed campaign, ad-set, creative, and ad workflows plus conservative
   generic relative-path access without allowing a generic capability escape.
5. Specify a live acceptance sequence on account `act_2506275116537415` that
   starts all created objects `PAUSED`, validates Facebook, Instagram, and
   Threads only where Meta accepts them, never authorizes a complete serving
   hierarchy, detects external hierarchy changes, and keeps aggregate authorized
   spend strictly below USD 20.
6. Use Kinko as the only secret source and retain only bounded, sanitized,
   non-replayable verification evidence.
7. Define deterministic formatting, tests, release, separation, catalog,
   secret-scan, static-analysis, archive, and adversarial gates.

### Non-goals

- Source implementation, local production changes, live API execution, or
  credential access during this design handoff.
- Git staging, committing, pushing, publishing, or deployment.
- Deletion through Reader, Writer, a generic shell client, Ads Manager, or any
  executable other than `meta-marketing-gateway-deleter` during acceptance.
- Activation before validation and rollback readiness, or simultaneous
  activation of a complete campaign/ad-set/ad serving chain.
- Guaranteeing support for a placement or status transition that Meta rejects.
- Treating a successful HTTP response as proof of delivery, absence, or zero
  spend without a follow-up read.
- Claiming that Graph `DELETE` guarantees irreversible provider-side erasure;
  this design calls the HTTP `DELETE` cleanup operation “physical delete” to
  distinguish it from `POST` status/archive transitions.
- Running the downstream implementation or source-security workflows here.

### Acceptance criteria

The implementation is acceptable only when all intake criteria are traceable
to tests and sanitized evidence, including:

- Reader APIs, transport, CLI, and catalog contain only `GET`.
- Writer APIs, transport, CLI, and catalog contain only `POST`; Writer contains
  no `DELETE` spelling or equivalent deletion carrier and does not depend on
  Deleter.
- Deleter is the sole owner of `DELETE`, with independent protections and
  packaging.
- Reader-only and Writer-only negative compilation fixtures cannot construct or
  dispatch a delete.
- Generic and typed transport is denied without an exact operation catalog
  match.
- Live campaign, ad-set, creative, and ad create/read/update/status/delete
  coverage is recorded; inapplicable or provider-rejected behavior is recorded
  as a fail-closed evidence result rather than silently skipped.
- All creates begin `PAUSED`; any activation is validated, interlocked,
  immediately paused, and followed by spend verification.
- Cleanup is child-first and invokes only Deleter for physical Graph `DELETE`.
- Deep, broad, and adversarial reviews have no unresolved high- or
  medium-severity finding before implementation routing.

## 3. Current behavior and preservation baseline

The repository currently has Reader and Writer libraries and executables, a
trusted-head broker, a build-only catalog generator/plugin, and 91 XCTest
methods. Reader already owns a methodless `ReaderGraphRequest` and a GET-only
transport. Writer currently owns `GraphMethod.get`, `.post`, and `.delete`, a
method-bearing `GraphRequest`, generic delete policy and tests, and CLI help for
`graph post|delete`. The canonical catalog has reader and writer projections;
`meta.generic.delete` is a denied Writer row, so Writer can express delete even
though current production transport is blocked.

The following safety work is retained:

- fixed HTTPS `graph.facebook.com` origin and normalized relative paths;
- bounded query, body, file, response, error, and diagnostic handling;
- Kinko-only `META_ACCESS_TOKEN` injection after local authorization gates;
- exact operation authorization and deny-by-default catalog availability;
- immutable plan digests, explicit confirmation, durable authenticated journal
  chains, independently protected trusted heads, reconciliation, and
  outcome-unknown replay denial;
- separate Reader and Writer products, thin CLIs, build-only catalog
  projections, deterministic documentation, and release/secret checks; and
- all pre-existing reader/writer tests unless a test intentionally moves from
  Writer to Deleter or changes because live activation is now narrowly
  authorized.

Migration must move, not copy, delete-bearing behavior. A compatibility alias,
deprecated Writer delete wrapper, typealias, dynamic method string, raw request
escape hatch, or transitive Deleter re-export is forbidden.

## 4. Package and trust boundaries

### 4.1 SwiftPM products and targets

| Product | Sole target | Direct runtime dependencies |
|---|---|---|
| Library `MetaMarketingGatewayReader` | `MetaMarketingGatewayReaderKit` | `MetaGraphPrimitives` |
| Library `MetaMarketingGatewayWriter` | `MetaMarketingGatewayWriterKit` | `MetaGraphPrimitives`, `MetaMutationSafetyPrimitives`, `MetaTrustedHeadProtocol` |
| Library `MetaMarketingGatewayDeleter` | `MetaMarketingGatewayDeleterKit` | `MetaGraphPrimitives`, `MetaMutationSafetyPrimitives`, `MetaTrustedHeadProtocol` |
| Executable `meta-marketing-gateway-reader` | `MetaMarketingGatewayReaderCommand` | ReaderKit only |
| Executable `meta-marketing-gateway-writer` | `MetaMarketingGatewayWriterCommand` | WriterKit only |
| Executable `meta-marketing-gateway-deleter` | `MetaMarketingGatewayDeleterCommand` | DeleterKit only |
| Executable `meta-marketing-gateway-trusted-head-broker` | `MetaMarketingGatewayTrustedHeadBroker` | `MetaTrustedHeadProtocol` only |

`MetaMutationSafetyPrimitives` is an internal, method-neutral extraction of the
existing canonical digest, confirmation envelope, authenticated journal event,
record identity, and state-machine primitives. It owns no Graph method, path,
credential, transport, catalog, Ads operation, policy classification, CLI, or
production composition. Writer and Deleter each own their policy and use
distinct configuration, namespaces, event domains, and record keys.

This design narrowly extends the method-neutral trusted-head broker beyond the
predecessor's journal-head CAS: versioned typed messages also own the global
evidence replay registry, acceptance-run registry, activation lease, spend
ledger, and cleanup-inventory heads. These are closed schemas with monotonic
transitions, not arbitrary key/value writes. The broker
still has no Graph credential, request, object ID, method, body, catalog
dispatch, journal content, cleanup-inventory content, reset/delete, list-all, or
network listener. Cleanup inventory stays in authenticated encrypted
client-accessible storage; only its digest/head is broker-owned. Peer identity,
owner-only storage, bounded Unix-domain protocol, atomic replace/fsync, and
strict CAS rules from the predecessor remain mandatory.

The broker exposes separate owner-controlled Unix-domain sockets for each peer
role. Socket-directory permissions, OS peer credentials, code-signing identity,
executable digest, capability epoch, and catalog revision must all match the
installed role policy before a message is decoded. A process cannot select a
different role socket or claim a role in its payload. The authorization matrix
is exhaustive:

| Authenticated peer | Allowed broker messages/transitions | Always forbidden |
|---|---|---|
| Reader | Read an exact registered evidence challenge; atomically mark it `issued` with a valid Reader signature; append signed monitor or reconciliation probes for that challenge/session. | Register/consume evidence; mutation journal/head writes; acceptance quotas; activation/pause claims; spend; inventory writes. |
| Ordinary Writer | Register Writer-audience challenges; reserve/consume their globally unique evidence; advance Writer journal heads; reserve acceptance create slots; bind discovered creates; reserve spend; claim ACTIVE and normal PAUSE transitions; propose create/update inventory generations. | Deleter challenges/journals, DELETE state, Reader issuance, watchdog takeover, broker administration or reset. |
| Watchdog Writer | Read exact run/lease/capsule state; CAS takeover of an expired normal pause claim; advance only pause-recovery journal/head generations under the capsule. | Challenge registration, evidence issuance, create/update/ACTIVE, spend reservation, delete, inventory insertion, administration. |
| Deleter | Register Deleter-audience challenges; reserve/consume their globally unique evidence; advance Deleter journal heads and delete-reconciliation sessions; propose deletion-only inventory generations for existing handles. | Writer journals/operations, create slots, spend/activation, inventory insertion, Reader issuance, administration. |
| Acceptance driver | Read aggregate run, quota, activation, spend, inventory, and cleanup status; request cancellation. | Direct state mutation, Graph authority, credential/signing access, quota release, journal/head repair. |
| Spend authority | Register one signed FX-evidence digest for the exact workflow/epoch. | Spend reservation/accounting, Graph operations, evidence issuance, other state. |
| Release authority | During quiesced installation only, initialize one epoch/run authorization and role-policy digest. | Runtime mutation, rollback/reset of established state, Graph operations, secret values. |

Every state-changing message names its expected old generation and supplies the
required signed artifact: Reader evidence for evidence/session transitions,
acceptance authorization for run/quota transitions, FX evidence plus Reader
liability evidence for spend, and a recovery capsule for watchdog transitions.
The broker re-verifies signatures, immutable bindings, state predecessor, role,
and epoch; possession of a socket is insufficient. Cross-role calls, wrong
sockets, same UID under a different executable, missing signatures, and
transition skipping are authorization failures with no state change.

Build-only targets remain `MetaCapabilityCatalogGenerator` and
`MetaCapabilityCatalogPlugin`. The plugin produces three outputs and is not a
runtime dependency. There is no combined client or executable.

```text
ReaderCommand  -> ReaderKit  -> GraphPrimitives
WriterCommand  -> WriterKit  -> GraphPrimitives
                            \-> MutationSafetyPrimitives -> TrustedHeadProtocol
DeleterCommand -> DeleterKit -> GraphPrimitives
                              \-> MutationSafetyPrimitives -> TrustedHeadProtocol
TrustedHeadBroker -----------------------------------------> TrustedHeadProtocol

ReaderKit  ..build only..> CatalogPlugin -> CatalogGenerator <- canonical manifest
WriterKit  ..build only..> CatalogPlugin -> CatalogGenerator <- canonical manifest
DeleterKit ..build only..> CatalogPlugin -> CatalogGenerator <- canonical manifest
```

Forbidden dependency edges are Reader-to-Writer, Reader-to-Deleter,
Writer-to-Reader, Writer-to-Deleter, Deleter-to-Reader, and Deleter-to-Writer.
Tests that need multiple products use a separate acceptance-test target; unit
test targets mirror exactly one capability and do not weaken product linkage.

### 4.2 Method-specific public types

There is no shared `GraphMethod` or general `GraphRequest`.

- `ReaderGetRequest` contains version, normalized path, and bounded query.
  `ReaderTransport.send(_:)` always constructs `GET` internally and has no body
  or caller headers.
- `WriterPostRequest` contains version, path, query, canonical body/media type,
  and a generated `WriterOperationID`. `WriterTransport.send(_:)` always
  constructs `POST` internally. No initializer accepts a method string.
  Catalog validation and request canonicalization also reject delete-equivalent
  POST carriers such as `status=DELETED`, archive/delete actions, or a
  delete-named field/path; only the specifically cataloged `PAUSED` and `ACTIVE`
  status values exist.
- `DeleterDeleteRequest` contains version, path, query permitted by the exact
  delete schema, and a generated `DeleterOperationID`. It has no body.
  `DeleterTransport.send(_:)` always constructs `DELETE` internally.

Credentials are capability-owned nominal types with internal token material;
they are not convertible or public-initializable. Shared primitives may return
bounded sanitized response envelopes but cannot send a request.

Public typed builders return only their surface request or plan type. Generic
builders accept a relative path and parameters but no method. Reflection,
`RawRepresentable` method construction, arbitrary headers, caller URL sessions,
redirects, and alternate hosts are absent.

## 5. Canonical capability catalog

`Catalog/meta-capabilities.json` remains the sole authority and moves to a
schema with exactly three surfaces: `reader`, `writer`, and `deleter`. Every row
contains a stable operation ID, one surface, one method, reviewed Graph version,
exact path template, typed/generic implementation state, availability, official
source URLs and review date, parameter schema, target derivation, permissions,
evidence/reconciliation contract, and precise blockers.

Generator invariants are structural:

| Surface | Required method/kind | Rejected fields |
|---|---|---|
| Reader | `GET` / `publicRead` | body, mutation effect, confirmation, delete policy |
| Writer | `POST` / `mutation` | physical-delete effect, delete confirmation, delete reconciliation |
| Deleter | `DELETE` / `physicalDelete` | body, create/update/status effect, writer operation ID |

The generator rejects `both`, a missing surface, duplicate IDs, cross-surface
IDs, method/surface mismatches, unsafe relative paths, incomplete permission or
evidence metadata, unstable order, and enabled entries with unresolved
blockers. Generated ID enums have no arbitrary raw-value initializer. Each CLI
enumerates only its compiled projection; runtime filtering of the full manifest
is forbidden.

Availability precedence is:

`denied > blockedVersionReview > blockedProviderEvidence > blockedPlacement`

An otherwise complete row then has one of two dispatch dispositions:
`acceptanceOnly` or `enabled`. `acceptanceOnly` is not a weaker blocker or a
caller-selectable override. It is a closed bootstrap state for obtaining the
first live-response evidence without claiming production support. The
generator permits it only when official contract review, exact typed request
schema, permissions, implementation, offline tests, reconciliation contract,
placement recipe, confirmation, spend policy, and rollback path are complete,
and the only missing evidence is the live observation itself. It is forbidden
for generic rows and rows blocked for version, provider proof, placement,
identity, reconciliation, or safety behavior.

An `acceptanceOnly` row dispatches only when all of these compile-time and
runtime bindings match:

- an acceptance build whose manifest names the exact operation IDs, account
  digest, maximum JPY 500/day budget, USD 19.99 aggregate ceiling, expiration,
  workflow execution ID, package/catalog epoch, and immutable per-type/
  placement object quotas;
- an owner-approved acceptance authorization whose canonical digest is pinned
  into that build and registered in the trusted-head-protected global safety
  state before any object is created;
- the same ordinary plan, evidence, confirmation, journal, spend, watchdog,
  reconciliation, and cleanup-inventory gates required by an enabled row; and
- a CLI `--acceptance-run` value equal to the fixed manifest run ID. No other
  flag, environment value, runtime descriptor, or stronger confirmation can
  create or broaden this authority.

Acceptance builds are never production archives. Release checks reject
`acceptanceOnly`, its manifest, its account digest, and its dispatch symbol from
all production artifacts. Sanitized successful evidence supports a reviewed
catalog change from `acceptanceOnly` to `enabled` in a new revision; it does not
mutate the running catalog. Rejection moves only the exact row to a blocked
state. This closed state removes the live-evidence cycle without an uncataloged
transport path.

Implementation state and availability are independent. Only
`implemented + exact dispatch adapter + (enabled or fully bound
acceptanceOnly)` can transport. A stale review, unknown operation, unknown
field, generic path mismatch, unsupported placement, absent reconciler, or
incomplete acceptance binding stops before credential resolution.

### 5.1 Acceptance run lifecycle and object quotas

One broker-anchored `AcceptanceRunRegistry` makes the manifest's object bound
durable across concurrent processes, restarts, and catalog revisions. Its key is
the workflow execution ID and account digest, independent of package/catalog
revision. The immutable row binds exactly one acceptance authorization digest,
epoch, initial catalog revision, expiry, JPY/USD bounds, permitted placements,
per-object-type quotas, and cleanup-inventory namespace:

```text
absent -> authorized -> running -> cancelling|expired -> cleanupRequired
       -> reconciledDeleted -> closed
       \---------------------------------------------> quarantined
```

Only the release authority may make `absent -> authorized`, and only once. A
new catalog revision may be recorded as an allowed continuation after review
but cannot create a second run, reset quotas, change the account, or replace the
authorization digest. Restarted drivers resume the same row. Expiration or
cancellation denies new create/update/ACTIVE work but preserves Reader,
pause-recovery, reconciliation, and Deleter cleanup authority. `closed` and
`quarantined` are permanent; neither can be reopened under the same workflow
execution ID/account.

Each type has immutable `authorizedCount`, `reservedCount`, and slot records:

```text
available -> reservedForExactCreatePlan -> sendMayHaveOccurred
          -> inventoryBound -> deletedVerified
```

Writer must CAS-reserve one exact type/placement slot before its create journal
can enter `inFlight`. The slot binds plan/request/marker/configuration/catalog
digests and cannot be used by another process or plan. A reservation may return
to `available` only when local transport and journal evidence prove no socket
write and the create never entered `inFlight`; after `inFlight` or any possible
send it is non-refundable forever, including after provider absence or deletion.
A lost response binds later marker discovery to that same slot. Multiple
candidates quarantine the slot and run. `reservedCount` can never exceed
`authorizedCount`; combined CAS of slot, Writer journal head, and expected run
generation prevents concurrent or restarted drivers from over-creating.

Run completion requires every non-refundable slot to be either proven
never-sent or bound to exactly one inventory row that reaches
`deletedVerified`, every spend reservation settled or conservatively retained,
and all evidence/delete sessions terminal. A newer build or catalog sees and
honors the same counters before any credential access.

### 5.2 Initial operation families

| Surface | Major operation families |
|---|---|
| Reader | Existing typed account/campaign/ad-set/ad/creative list/get and insights; operation-specific generic GET entries; validation reads for status, effective status, configured placements, account currency, budget, delivery diagnostics, and spend. |
| Writer | Typed paused create/update for campaign, ad set, creative, and ad; typed safe update; separate `status-paused` and `status-active` POST IDs where the provider supports status; operation-specific generic POST entries. |
| Deleter | Separate physical-delete IDs for ad, creative, ad set, and campaign; operation-specific generic DELETE entries. |

Campaign, ad-set, and ad create builders fix `status=PAUSED`. Creative creation
is classified as non-serving and has no invented status field. A creative
status transition is cataloged only if sanitized provider evidence confirms an
official supported operation; otherwise the matrix records `notApplicable` or
`blockedProviderEvidence` and no request can be built.

Generic clients are conservative evolution surfaces, not universal proxies. An
unknown safe relative path can produce a credential-free offline analysis with
`catalogMatch=null` and `transportEligibility=false`; it cannot resolve a
credential or send. Exact method, version, path template, target, query/body
schema, values, effect, placement, and adapter must match one enabled row.

## 6. User-visible flows

### 6.1 Local discovery and offline planning

All clients provide local, credential-free `--help`, `--version`, and
`catalog list`. Writer and Deleter support immutable offline plan generation.
An offline plan is always non-executable and cannot be upgraded in place.

Representative commands are:

```text
meta-marketing-gateway-reader catalog list
meta-marketing-gateway-reader graph get --operation OP --api-version vNN.N --path RELATIVE

meta-marketing-gateway-writer graph post --operation OP --request-file request.json --plan-out offline-plan.json
meta-marketing-gateway-writer preview --plan offline-plan.json --evidence reader-evidence.json --out verified-plan.json
meta-marketing-gateway-writer apply --plan verified-plan.json --confirm FULL_PLAN_DIGEST

meta-marketing-gateway-deleter graph delete --operation OP --request-file request.json --plan-out offline-delete-plan.json
meta-marketing-gateway-deleter preview --plan offline-delete-plan.json --evidence reader-evidence.json --out verified-delete-plan.json
meta-marketing-gateway-deleter apply --plan verified-delete-plan.json --confirm FULL_PLAN_DIGEST --confirm-resource-digest EXACT_TARGET_DIGEST
```

Network forms run only through an explicit minimal Kinko invocation. Help,
catalog, and offline planning never inspect credentials. Persisted request and
plan files express target segments as inventory handles plus path templates;
they never contain resolved provider IDs. Resolution occurs only after apply
authorization under Section 8.1.

### 6.2 Cross-client evidence

Writer and Deleter do not gain GET transports for validation. Reader emits a
bounded `ReaderEvidenceChallenge`/`ReaderEvidenceEnvelope` exchange for a
cataloged validation recipe. Writer or Deleter first emits a challenge from an
already canonical offline plan. Reader signs an envelope that binds all of:

- schema, package/catalog/journal epoch and exact catalog revision;
- one audience (`writer` or `deleter`), one purpose (`preApply`,
  `activationPreSend`, `activationMonitor`, `pauseReconcile`, `preDelete`, or
  `deleteReconcile`), one consumer operation ID, and one plan digest;
- consumer configuration digest, request/target/account/run digests, Graph
  version, validation operation IDs, placement/budget/status/spend facts and
  response digests;
- challenge nonce, evidence ID, host/boot/broker-session clock domain,
  broker-recorded observation start/end/issue ticks, monotonic-age bound,
  audit wall time, expiry, and signer key ID.

Changing an audience, purpose, operation, plan, target, configuration, epoch,
or nonce invalidates the signature. Writer rejects Deleter evidence and vice
versa before credential or journal access. An envelope contains no token, raw
response, raw headers, resolved request URL, or reusable provider authorization.

Because caller-editable JSON is not provider evidence, a dedicated
Kinko-managed evidence-signing credential is available only to the Reader
runtime identity. Live mutation is disabled unless deployment verification
proves all of the following without reading the key value:

- Reader runs under a distinct non-login OS principal; Writer, Deleter,
  watchdog, acceptance driver, and ordinary operator principals cannot request
  the signing key from Kinko.
- Kinko policy binds key use to that principal and the approved, code-signed
  Reader executable digest/path. The launcher verifies ownership, immutable
  parent directories, signature, release provenance, and digest before asking
  Kinko to authorize the process.
- The key is a non-exportable signing handle when Kinko supports one. If the
  installed Kinko integration can only inject exportable bytes, those bytes are
  scoped to the verified Reader process, never inherited by child processes,
  scrubbed before crash handling, locked out of core dumps, and the deployment
  remains `blockedProviderEvidence` unless the OS/Kinko ACL tests prove no other
  principal can retrieve them.
- Writer and Deleter pin the public key, algorithm, key ID, validity interval,
  and revocation epoch in their generated catalogs. Unknown, revoked, expired,
  weak, or future key IDs fail closed.

Rotation is additive: a new Kinko key and catalog-pinned public key become
valid before the old key stops issuing. Existing envelopes retain their
original short expiry; revocation immediately invalidates unconsumed envelopes
and quarantines a reserved envelope until it is re-observed and reissued under
the new key. Emergency revocation disables Writer and Deleter apply, not Reader
GET. The signing credential is never the Meta access token.

Evidence replay state is global across both consumers even though their
mutation journals remain independent. A trusted-head-protected
`EvidenceReplayRegistry` has two mandatory global unique indices: one keyed only
by `evidenceID` and one keyed only by nonce digest. Audience is immutable row
data, never part of either uniqueness key. A single broker transaction rejects
an evidence ID or nonce found in any active row, expired row, consumed row, or
permanent tombstone before creating either index entry. The row stores audience,
purpose, consumer operation, plan/configuration/target digests, expiry, and
state:

```text
absent -> challengeRegistered -> issued -> reservedByExactPlan
                                             \-> consumedBeforeSend -> terminalTombstone
                         \-------------------> expiredTombstone
```

The consumer registers the exact challenge before Reader is invoked. Reader
refuses unregistered, already issued, wrong-audience, or unauthorized
challenges and atomically marks the matching entry `issued` when signing.
Preview changes `issued` to `reservedByExactPlan`. Only the identical plan may
resume that reservation. Apply atomically changes it to
`consumedBeforeSend` while holding the consumer journal lock and before
transport; a crash never makes it available to another plan. Expiry creates a
permanent tombstone. Audience is part of both the signed payload and the global
row, while the independent indices prevent a second Writer, Deleter, epoch, or
run row from reusing either identifier. Compaction may merge tombstones into an
authenticated sorted digest set but may never discard an ID/nonce or introduce
false negatives. Missing, rolled-back, forked, or unavailable registry or index
state blocks transport.

Freshness uses the broker's clock domain, not comparisons between process
clocks. The broker issues each challenge with `hostIdentityDigest`, OS boot ID,
broker session ID, and a broker-monotonic observation-start tick. After Reader's
provider call, the broker records the issue/end tick and returns an authenticated
clock receipt; Reader includes that receipt in its signed envelope, and the
broker verifies both. Writer/Deleter ask the same broker session to
evaluate age at reserve and consume time; wall time is audit-only. Producer and
consumer must be on the same verified host, boot, and broker session. Negative,
future, wrapped, incomparable, caller-supplied, cross-host, cross-boot, or
cross-session ticks are rejected.

Reader or consumer process restart is allowed only if the broker session and
registered challenge remain current. Broker restart creates a new session ID
and permanently expires every unconsumed envelope from the prior session;
provider observation must be repeated. OS reboot changes the boot ID and does
the same. Wall-clock adjustment cannot lengthen an envelope. A future reviewed
cross-host scheme must replace this contract with trusted synchronized time and
cannot be selected at runtime.

### 6.3 Create, update, validate, and status flow

1. Writer CAS-reserves the exact per-type acceptance-run slot, then creates
   campaign, ad set, creative, and ad as separate cataloged POST operations.
   Every object that accepts status is fixed to `PAUSED`; caller aliases or
   duplicate status carriers are rejected. A possible send permanently consumes
   its slot even if the response is lost or the object is later deleted.
2. Reader obtains fresh evidence for every created object, hierarchy binding,
   configured placement, account currency, daily budget, status/effective
   status, and spend baseline.
3. Writer applies only narrow, preplanned updates. Reader verifies each update
   before the next operation.
4. Before any `ACTIVE` transition, the run prepares and confirms a corresponding
   `PAUSED` recovery capsule, validates its catalog availability and evidence
   reservation, proves the separately supervised watchdog and Reader monitor
   are healthy, acquires the global account activation lease, and records a
   conservative spend reservation.
5. Reader issues `activationPreSend` evidence from observations completed no
   more than two seconds before Writer takes the send lock. Writer rechecks its
   broker-clock age under that lock. The evidence proves a complete,
   permission-verified enumeration of every relevant ancestor, descendant,
   delivery edge, creative/ad reference, and status for the target—not only
   run-owned objects. It binds edge counts, ordered collection digests,
   pagination exhaustion, identity/permission proof, and observation bounds.
   Any active, pending, in-review, unknown, filtered, inaccessible, newly
   inconsistent, or incompletely paginated object/state denies activation.
6. Status transitions are gateway-interlocked. The gateway authorizes campaign
   ACTIVE only when every enumerated descendant/reference is non-serving;
   ad-set ACTIVE only when every ancestor and descendant/reference is
   non-serving; and ad ACTIVE only when every ancestor is non-serving. It never
   authorizes a complete serving chain. This is not a claim that provider state
   is atomic: an external actor can create or activate an object after the
   enumeration and before POST.
7. A separately supervised Reader monitor starts before the ACTIVE POST and
   repeats the same complete, permission-verified, fully paginated closure at
   the catalog-reviewed interval, never slower than two seconds during the
   lease. It may not narrow to cached/run-owned IDs. If Meta rate limits or an
   operation's official contract cannot support complete enumeration at that
   interval, activation is denied. The monitor continues until the complete
   closure is non-serving and the spend ledger enters settlement.
8. “Immediate pause” is measured from the ACTIVE transport's first socket-write
   callback `T_active_write` in the broker clock domain. The normal Writer owns
   armed pause generation 1 before ACTIVE. It must begin the exact PAUSED socket
   write without waiting for an ACTIVE response or observation and record
   `T_pause_write <= T_active_write + 1 second`. If no pause-write event is
   broker-anchored by one second, the watchdog CAS-claims the next generation
   and must begin its PAUSED write by `T_active_write + 2 seconds`. Missing the
   two-second deadline is an incident and closes all activation authority. The
   60-second lease remains only the outer recovery/monitoring bound, not the
   definition of immediate.
9. Any unsupported provider response, stale evidence, process failure, status
   ambiguity, interlock breach, or spend uncertainty aborts later activation
   and enters pause-and-verify recovery.

Provider observation and mutation cannot be one atomic transaction. Therefore
“interlocked” means gateway-authorized state, not guaranteed account-wide
state. Live acceptance additionally requires an operator change freeze for the
account, but the gateway does not trust that convention: any newly enumerated
object, active/pending/unknown state, pagination/permission incompleteness,
external modification timestamp, unexpected actor/effective-status change,
monitor loss, or cancellation immediately closes activation authority and
invokes the recovery capsule. Recovery pauses the exact run-owned objects in
child-to-parent order (`ad`, `ad set`, `campaign`); external objects are never
mutated without a separately authorized inventory row, so their presence keeps
the run quarantined even after run-owned objects are paused.

`PAUSED` is a monotonic risk-reducing POST with a bounded, preauthorized recovery
exception. Before activation, the user confirmation covers one exact
`PauseRecoveryCapsule`: run, account, target hierarchy, configuration/catalog
epoch, expiry 24 hours after lease end or immediately after `pausedVerified`,
and at most three pause send generations per object. It cannot authorize an
update, activation, delete, new target, or later run. Normal and watchdog paths
use this broker-anchored state:

```text
prepared -> activeSendClaimed -> activeOutcomeUnknown -> monitoring
                                               \-----> pauseClaimed(owner,generation)
pauseClaimed -> pauseOutcomeUnknown -> pausedVerified -> closed
                                  \-> nextPauseGeneration | quarantined
```

Normal and watchdog processes contend on one CAS-owned `pauseClaimed` state;
only the owner may send that generation. Generation 1 is armed to normal before
ACTIVE; the watchdog may take generation 2 at the one-second immediate-pause
deadline and later generations under the bounded recovery rules. The loser
performs monitoring only.
Signals and operator cancellation set `cancelRequested`, prevent an unsent
ACTIVE request, and cause the current/next CAS owner to pause if ACTIVE may have
been sent. If an owner dies or a pause becomes outcome-unknown, lease expiry
permits one next generation—never replay of the same journal record—when fresh
Reader evidence proves ACTIVE. If Reader is unavailable after an ACTIVE send,
the capsule permits the watchdog to use the remaining finite generations with
cataloged backoff because repeated exact `status=PAUSED` is safer than leaving a
possibly active object. Exhaustion, expiry, journal/head disagreement, or an
uncertain target quarantines the run and triggers an alert; it never authorizes
activation or delete. If the object may still be ACTIVE after capsule
exhaustion, only a new explicit user confirmation may register another exact
pause-only recovery capsule; the prior journal records remain immutable.

The live acceptance driver and watchdog are test/runbook tooling, not a fourth
client or public product. They have no Graph request or credential API and can
only invoke the three built executables with prevalidated artifact paths. The
watchdog has its own non-login OS identity and Kinko ACL that can launch only
the verified Writer executable for cataloged `status-paused` with a valid
recovery capsule; it cannot retrieve the evidence-signing credential or invoke
create/update/ACTIVE. Because executable ACLs alone may not constrain CLI
arguments, Writer also recognizes the pinned watchdog OS identity, ignores
caller-selected configuration, loads the fixed owner-only pause-recovery
configuration, and exposes only capsule-bound `status-paused`; every other
route denies before token resolution. To meet the two-second deadline, Kinko
injects the token into the already verified normal and watchdog processes only
after all local gates and immediately before activation readiness; it exists in
locked process memory, is not inherited, and is never persisted. Activation
requires both credential resolutions, transport readiness, watchdog heartbeat,
broker CAS probe, and Reader monitor probe immediately beforehand. The watchdog
is separately supervised from the activation process so one process failure or
signal cannot remove the pause attempt.

### 6.4 Physical cleanup

After all objects are verified paused and spend is stable, cleanup proceeds
child-first: ad, creative after references are absent, ad set, then campaign.
For each object:

1. Reader emits fresh pre-delete evidence for exact identity, account,
   hierarchy, paused/non-serving state, and reference constraints.
2. Deleter creates a one-target plan, verifies the evidence, requires full plan
   digest plus exact target-digest confirmation, resolves the bound inventory
   handle inside the process, validates its own journal and trusted head,
   persists `inFlight`, and sends at most one DELETE.
3. Deleter records `outcomeUnknown` regardless of the apparent response.
4. Reader performs the cataloged absence/tombstone check. Deleter consumes the
   signed result to record `succeeded`, `failedSafeToRetry`, or retains
   `outcomeUnknown`. It never automatically replays.

#### 6.4.1 Durable cleanup inventory

Every live run has an authenticated, owner-only durable cleanup inventory. It
is method-neutral shared safety state, not a Reader, Writer, or Deleter API. The
inventory stores exact provider IDs because digest-only or ephemeral state is
insufficient for recovery. Each row binds run and account, object type and exact
ID, parent/reference IDs, creating Writer operation/plan/record digests,
creation reconciliation state, last verified status, Deleter plan/record
digest, deletion state, and timestamps.

Writer must append and fsync the inventory row and advance its separately
protected trusted head immediately after a create response identifies an
object, before creating any dependent object or returning success. A unique
run-scoped marker is part of every cataloged create. If the create response is
lost, Writer remains `outcomeUnknown`; a cataloged Reader reconciliation query
uses that marker and exact account/hierarchy to discover zero or one candidate.
One candidate is anchored into inventory before progress; zero remains pending;
multiple candidates quarantine the run. Create is never replayed merely because
the inventory lacks an ID.

The primary inventory and encrypted authenticated backup use immutable
generation files on distinct configured owner-controlled volumes plus a
broker-owned two-phase head. For committed generation `g`, candidate `C_(g+1)`
binds the complete canonical inventory, generation, prior head/digest,
operation, and a Kinko-key authentication tag. Under one cross-process lock the
role-authorized Writer or Deleter updater performs:

1. write-new and fsync `C_(g+1)` on primary, then its directory;
2. write-new and fsync the identical bytes on backup, then its directory;
3. broker CAS `committed(g) -> prepared(g+1, candidateDigest, priorHead)`;
4. re-read and authenticate both immutable candidates; and
5. broker CAS `prepared(g+1) -> committed(g+1)`.

No live “current” file is replaced; readers select only the generation named by
the broker's committed head. Exact IDs are encrypted at rest with a per-run data
key available only through Kinko; the key itself is never persisted. Candidate
files are never overwritten or deleted during recovery. The recovery table is
mechanical:

| Durable files and broker state | Only permitted recovery |
|---|---|
| Neither candidate exists; head is `committed(g)`. | Stay at `g`. If a create may have succeeded, use marker reconciliation to produce a new authenticated candidate; never replay create. |
| Only primary or only backup has one authenticated exact-next candidate; head is `committed(g)`. | Preserve it, copy its identical bytes write-new to the missing volume, fsync, then perform prepare/commit. Never copy old `g` over it. |
| Both have byte-identical authenticated exact-next candidates; head is `committed(g)`. | Perform prepare/commit for that digest. |
| Both have different authenticated next candidates, or either has multiple candidates; head is old. | Preserve every candidate under its immutable name, quarantine, and reconcile journal/provider/inventory identity. No automatic winner or overwrite. |
| Head is `prepared(g+1)` and one/both matching candidates exist with no conflicting candidate. | Copy only the broker-named identical candidate to an absent side, verify both, then commit. |
| Head is `prepared(g+1)` and any conflicting candidate exists. | Preserve every candidate and quarantine; do not commit or overwrite. |
| Head is `prepared(g+1)` but no matching candidate exists. | Quarantine; marker/provider reconciliation may add a separately named candidate but cannot rewrite the broker-named generation. |
| Head is `committed(g+1)` and both matching candidates exist. | Normal operation. |
| Head is `committed(g+1)` and exactly one matching candidate exists while the other side is absent. | Restore the absent immutable copy from the matching side, fsync, then resume. |
| Head is `committed(g+1)` but neither side matches, or any conflicting candidate exists. | Preserve all bytes and quarantine; never fall back to `g`, discard a unique ID, or advance. |

Recovery validates authentication, prior head, generation, full inventory
invariants, Writer/Deleter journal binding, acceptance slot, and provider marker
before copying or advancing. A uniquely discovered exact ID is always preserved
as a new immutable candidate even when it conflicts; only authenticated
provider reconciliation can resolve it. Missing, divergent, rolled-back,
unreadable, or unanchored state blocks new mutation and delete. Neither a CLI
flag nor a new run can reset it.

Writer may add/create-reconcile rows; Reader may emit evidence but cannot edit
inventory; Deleter may advance only deletion fields for an existing exact row.
The acceptance driver refuses completion while any created-object row is not
`deletedVerified`; a provider-retained or quarantined object remains an explicit
incomplete cleanup result. Exact IDs remain recoverable through host failure
and are retained through the longest cataloged provider consistency window plus
audit retention. After every row is
terminal and retention expires, compaction writes digest-only tombstones to
both copies, verifies by strict parse and secret/privacy scan that exact IDs are
absent, advances the trusted head, and retires the per-run Kinko data key.
Filesystem snapshots/backups must expire under the same retention policy;
otherwise verified erasure cannot be claimed and the run remains retained.

#### 6.4.2 Deterministic delete reconciliation

Every object-specific Deleter catalog row specifies the official response
classes, identity/permission probe, parent-edge/reference probe, tombstone
meaning, consistency window, probe schedule, and maximum observation horizon.
Missing any field is `blockedVersionReview`. A DELETE HTTP response is never a
terminal success by itself.

Deleter creates a broker-anchored authenticated
`DeleteReconciliationSession` for one delete record and inventory handle. Its
immutable header binds epoch/catalog, Deleter record/plan/request/target/account
digests, Reader principal and permission requirements, object and parent-edge
recipes, consistency-window duration, required probe count, exact due offsets,
allowed lateness, maximum gap, observation horizon, clock domain, and session
generation. Each scheduled probe is a separate short-lived signed Reader
envelope bound to session ID, generation, ordinal, due tick, purpose, complete
pagination counts/digests, identity/permission proof, and object/reference
result. The session persists only evidence IDs/digests and classifications; the
exact ID remains behind its inventory handle.

The broker permits one append per ordinal and consumes its globally unique
evidence atomically. Deleter may aggregate terminal success only when every
required ordinal in one uninterrupted broker clock domain is present, each
arrived within its allowed lateness, adjacent observation-start ticks do not
exceed `maximumGap`, first-to-last coverage meets the full consistency window,
all identity/permission checks match, every required pagination stream is
exhausted, and every object/edge classification satisfies the same terminal
rule. A missed/late/incomplete probe invalidates that candidate window; the
session retains it and starts a new generation from the next complete probe.
It may not interpolate or combine gaps, sessions, identities, or key epochs.

Reader/Deleter process restart may resume the same generation only when the
broker session survives and no scheduled bound was missed. Broker restart or OS
reboot closes the generation as incomplete because its monotonic times are no
longer comparable; a new chained generation must observe the entire window
again. Prior probes remain immutable audit evidence but cannot count toward the
new window. Reaching the observation horizon without one complete generation
quarantines indefinitely. Session/head rollback, duplicate ordinals,
permission drift, or conflicting classifications quarantine immediately.

| Observation after a send may have occurred | Required classification and action |
|---|---|
| Reader sees the exact object with unchanged identity and ordinary fields during the consistency window. | `outcomeUnknown`; presence does not prove no effect or safe retry. Continue scheduled probes. |
| Reader sees an official deletion tombstone whose documented meaning is physical Graph deletion, and the object is absent from every catalog-required parent/reference edge for the full consistency window. | `succeeded`; anchor terminal evidence. An archive/disabled tombstone that is not the reviewed DELETE result is not sufficient. |
| Reader receives object-not-found while the same signed envelope proves the expected app/actor/account identity and permissions, and independent parent/reference probes also show absence throughout the consistency window. | `succeeded`; anchor terminal evidence. A lone 404 is insufficient. |
| Reader gets 401/403, permission loss, identity mismatch, a visibility-filtered result, unexpected redirect/version, or cannot perform a required edge probe. | `outcomeUnknown` then `quarantined` at the observation horizon; never retry. |
| Reader gets timeout, 429, 5xx, inconsistent presence/absence, a still-referenced creative, or observations have not covered the full consistency window. | Retain `outcomeUnknown`; continue only the bounded read schedule. At the horizon, quarantine indefinitely. |
| Local transport proves before socket write that zero DELETE bytes could have left the process. | `failedSafeToRetry`; a new plan, evidence envelope, confirmation, journal record, and record identity are required. |
| A reviewed provider error contract explicitly and unambiguously proves no effect for this exact operation, version, and error code, and authenticated probes confirm continued presence after its required window. | `failedSafeToRetry`; otherwise quarantine. |
| Evidence names a different object/account, more than one candidate, an unreviewed tombstone, or a state impossible under the catalog. | Quarantine immediately; no retry or parent deletion. |

For any send whose bytes may have left the process, continued presence alone
never yields `failedSafeToRetry`; eventual deletion could still occur. If the
official contract provides no finite consistency bound, the row cannot become
production `enabled`; an acceptance-only delete may remain quarantined until
manual evidence review but still cannot replay. Child-first reference checks
must be terminal before a parent DELETE is planned.

Batch delete and wildcard cleanup are absent. A creative that remains
referenced stays undeleted with a sanitized blocked result; parent cleanup does
not skip over it. No Writer POST archive/status transition is described as
physical cleanup.

## 7. State model and invariants

### 7.1 Object lifecycle

```text
absent
  -> createPlanned
  -> createInFlight
  -> createdPaused
  -> validatedPaused
  -> updateInFlight
  -> validatedPaused
  -> activationReady
  -> activeGatewayInterlocked
  -> pauseClaimed
  -> pauseOutcomeUnknown
  -> pausedVerified
  -> deletePlanned
  -> deleteInFlight
  -> deleteOutcomeUnknown
  -> deletedVerified | deleteFailedSafeToRetry | quarantined
```

Creative omits activation states unless an operation-specific provider contract
later establishes them. No state transition is inferred from process exit or a
single HTTP response. Reader evidence authorizes only the specifically bound
next transition and expires after the shorter of the catalog TTL or 60 seconds
for activation/delete gates; activation pre-send evidence additionally has the
two-second maximum observation age defined above.

Supporting durable states are:

- acceptance run: `authorized -> running -> cancelling|expired ->
  cleanupRequired -> reconciledDeleted -> closed|quarantined`;
- create slot: `available -> reservedForExactCreatePlan -> sendMayHaveOccurred
  -> inventoryBound -> deletedVerified`;
- inventory head: `committed(g) -> prepared(g+1) -> committed(g+1)` over
  immutable dual-volume generations; and
- delete observation: `scheduled -> collecting -> completeWindow -> terminal`
  or `newGeneration|quarantined` after gaps, restart, or horizon expiry.

### 7.2 Mutation journal states

Writer and Deleter use separate domain tags and namespaces:

```text
planned -> confirmed -> inFlight -> outcomeUnknown -> succeeded
                                           \-------> failedSafeToRetry
                                           \-------> quarantined
```

Every send is preceded by a durable authenticated `inFlight` event and trusted
head. Every observed transport result first becomes durably
`outcomeUnknown`. Only fresh, operation-specific Reader reconciliation evidence
can create a terminal event. Existing exact one-step trusted-head recovery,
immutable unanchored-successor handling, monotonic compare-and-set, namespace
quarantine, and new-record retry rules remain mandatory.

Journal invariants include:

- Writer and Deleter directories, configuration digests, record domains,
  idempotency keys, and operation IDs are disjoint. Evidence nonces are instead
  protected by audience-independent global nonce/evidence-ID uniqueness; the
  audience is immutable data in that registry.
- Neither client can open the other's namespace or reinterpret its artifact.
- A target with an unresolved delete outcome cannot receive another delete.
- A target with an unresolved activation outcome can receive only the exact
  risk-reducing pause exception after fresh active evidence.
- Compaction is terminal-only and retains permanent replay and consumed-evidence
  tombstones; rotation cannot re-enable an operation.
- Trusted-head broker state is separately protected, never reset by an ordinary
  CLI, and contains no secret or raw provider data.

### 7.3 Spend and activation invariants

- All live-created campaign, ad-set, and ad objects start `PAUSED`; no input
  carrier can override the fixed value.
- The account currency must be provider-verified. For the authorized account,
  a JPY ad-set daily budget is exactly JPY 500 when Meta accepts that value. If
  Meta rejects it or requires an increase, the live run stops; it does not
  choose a larger budget.
- Aggregate gateway-authorized exposure is strictly less than USD 20 across the
  entire workflow, not per process or per run. A broker-anchored
  `GlobalSpendLedger` is owned by a distinct non-login safety principal in an
  owner-only directory. Writer accesses it through a length-bounded local CAS
  protocol; no CLI can replace, reset, decrement, or select another backend.
  The key is workflow execution ID plus account digest and package/catalog
  epoch. A single cross-process lock covers reservation, activation-lease, and
  settlement transitions.
- The ledger stores a fixed `authorizationCeilingCents=1999`, monotonically
  nondecreasing `cumulativeReservedCents` and
  `cumulativeObservedSpendCents`, outstanding reservation records, an immutable
  liability-component/coverage index, source-rate digests,
  provider-liability multipliers, per-run provider baseline/high-water
  observations, activation leases, settlement state, final sequence/hash, and
  retained boundary. Every replacement is
  authenticated, fsynced, and advanced through the separately protected trusted
  head. Rollback, missing state, fork, lock loss, or broker disagreement denies
  activation globally.
- A reservation follows
  `proposed -> reserved -> activeExposure -> settling -> settled|quarantined`.
  `reserved` is durable before ACTIVE transport. Crash recovery may advance
  only the identical reservation/lease transition; it never refunds capacity.
  Closing or settling a reservation releases the activation lock but does not
  reduce `cumulativeReservedCents`. Thus repeated zero-spend runs cannot reuse
  the same USD authorization indefinitely.
- Liability accounting is additive. Every independently observable exposure is
  an immutable component with a stable digest, class, account/run/object/time
  bounds, currency amount, converted cents, and evidence ID: new delivery
  exposure, other operation-specific exposure, each pending/unbilled amount,
  each provider high-water delta, and each externally attributable or ambiguous
  amount. The full JPY 500 daily budget multiplied by the cataloged official
  maximum delivery/overspend factor is always one new-delivery component. A
  separate operation liability is another component unless the catalog proves
  it is the identical component and binds the same component ID.
- Coverage is an immutable allocation from one existing reservation component
  to one observed liability component, bounded by remaining cents in both.
  Reservation cents cannot cover two components. Coverage may be recorded only
  when signed evidence proves the same account, run, object/hierarchy, currency,
  liability class, and overlapping provider interval. Similar values or
  timestamps are not proof. For each observed component `i`,
  `uncovered_i = max(0, amount_i - validAllocatedCoverage_i)`. Unknown overlap
  means independent components and both are added.
- Under the global lock, a new activation computes
  `newDelta = newDeliveryExposure + newIndependentOperationExposure +
  sum(uncoveredPendingUnbilled) + sum(uncoveredHighWater) +
  sum(uncoveredExternalOrAmbiguous)`, then
  `prospectiveExposure = cumulativeReservedCents + newDelta`. Existing open
  reservations are already included in `cumulativeReservedCents` and are never
  subtracted. Pending/provider/external observations are recorded even when the
  activation is denied. Only an exact immutable coverage allocation can reduce
  their uncovered term. The broker atomically appends components, allocations,
  and one new reservation allocating every cent of `newDelta`, then increments
  `cumulativeReservedCents` by exactly `newDelta`; future checks therefore do
  not add those same components again. On denial it still records authenticated
  observations as uncovered but creates no reservation or activation lease. It
  denies when `prospectiveExposure >= 2000`.
- Provider baseline and high-water values are monotonic per exact metric and
  currency. `delta = greatestHighWater - authenticatedWorkflowBaseline`; a
  lower/reset/missing counter or currency change becomes an independent
  ambiguous component rather than a subtraction. Realized spend never reduces
  `cumulativeReservedCents`. Tests must add overlapping new, pending, unbilled,
  external, and high-water components and may subtract only proven one-to-one
  coverage.
- Every currency component is converted using one policy-pinned central-bank or
  governmental public FX source, quote direction, TLS host, document field, and
  parser; aggregators and caller-entered rates are forbidden. The rate evidence
  must be no older than 24 hours, bind retrieval time/source digest, use a 25%
  adverse movement margin, and round liability upward to cents. If the official
  provider contract supplies no finite delivery multiplier, the FX source is
  unavailable/ambiguous, or a component cannot be bounded, activation is
  denied.
- Writer has no FX GET escape hatch. A distinct non-login spend-authority
  process fetches the pinned public source, applies the deterministic parser,
  and signs `FxRateEvidence` with a Kinko-managed credential under the same
  executable/identity/rotation controls as Section 6.2. The evidence binds
  source URL/digest, quote direction, parsed rate, retrieval/expiry times,
  acceptance/workflow ID, and package/catalog epoch. Writer pins only its
  public key and consumes the evidence once through the global spend ledger.
  The acceptance build additionally pins the exact evidence digest. The fetcher
  is build/runbook tooling with no Graph request or release product.
- Only one global acceptance run and one activation lease may exist. The
  gateway never authorizes a complete active campaign/ad-set/ad chain, so
  expected delivery is zero; the reservation remains required because external
  state, pacing, and pause controls can fail.
- An activation cannot consume a generic POST entry. It requires a typed exact
  status-active row, fresh Reader evidence, a preconfirmed pause plan, watchdog
  readiness, journal/head health, and spend reservation.
- After pause, Reader records immediate spend and follows the per-operation
  cataloged reporting-latency contract. Settlement requires all objects paused,
  the official maximum reporting-latency interval plus a cataloged safety
  margin to elapse, and two successive authenticated spend observations to be
  stable. There is no fixed 15-minute release assumption. If no dated official
  latency bound exists, the reservation remains `settling` indefinitely and no
  further activation is authorized. Observed spend is monotonically added or
  raised from the authenticated pre-activation baseline to the greatest
  provider-supported high-water value; it can never be edited downward. A
  counter reset, currency change, lower observation, or attribution ambiguity
  quarantines settlement and retains the full reservation. Positive, unknown,
  delayed, or externally attributable spend is still counted against the global
  ceiling and blocks later activation when attribution is uncertain.
- The ledger horizon is the immutable workflow execution ID from first
  reservation through final cleanup and settlement. Closing the workflow writes
  a permanent terminal head; that execution ID can never reopen or receive a
  new reservation.

## 8. Data, validation, permissions, and errors

### 8.1 Artifact model

All plan, evidence, journal, receipt, and live-report schemas are versioned,
strictly decoded, size/depth bounded, canonicalized, and reject unknown fields.
Plans bind operation ID, method-specific request digest, catalog revision,
target, account, effect, placement contract, evidence key ID/nonces, expiry,
configuration digest, confirmation class, and reconciliation strategy.

Exact provider IDs may exist persistently only inside the encrypted
authenticated cleanup-inventory generation files and their governed encrypted
backup/snapshots. Every other artifact—request input, offline/verified plan,
challenge, evidence, confirmation, journal, trusted head, receipt, metric,
diagnostic, live report, catalog, provenance, or archive—stores only an opaque
inventory handle and keyed run-scoped target digest. Deleter and Writer resolve
the handle after authorization inside locked, core-dump-disabled process memory
and verify the resolved ID against the bound digest before building the
method-specific request; it is never written to a temporary request file or CLI
argument. Generic live acceptance paths obey the same rule.

An authenticated `ArtifactRegistry` in the cleanup inventory records every
artifact path/handle, schema, generation, encryption policy, backup/snapshot
class, creation/expiry time, and exact-ID policy. Strict decoding and release/
privacy scans reject provider-ID-shaped cleartext outside permitted encrypted
inventory blobs. Owner-only plans use handles, so loss of a plan never loses
the ID. At terminal retention, compaction removes exact IDs from primary and
backup inventory generations, retires the Kinko data key, verifies all
registered artifacts and expired snapshots contain handles/digests only, and
then advances the erasure head. Any unregistered file, retained snapshot,
crash/core dump, swap exposure, or scan ambiguity prevents verified-erasure
status. Files otherwise require owner-only regular-file semantics, no symlink,
write-new/atomic replace as their schema requires, fsync, and revalidation after
open.

### 8.2 Input and placement validation

Relative paths reject scheme, authority, port, user info, fragment, dot/empty
segments, traversal, encoded separators, control characters, token query keys,
redirects, arbitrary headers, cookies, proxies, and alternate origins. Query and
body keys are canonical and schema-closed. Duplicate/case-confusable status,
budget, target, or placement carriers fail.

Placement is an operation-specific catalog value, not a free string. Facebook,
Instagram, and Threads each have reviewed publisher-platform/position rules,
required identity/creative fields, Graph version, and evidence status. A
placement combination transports only when every element is enabled for the
exact ad-set/ad/creative recipe. Meta rejection becomes sanitized evidence and
`blockedPlacement`; the run does not remove the failed placement and silently
continue under the same plan.

### 8.3 Permissions and credentials

Kinko is the sole credential provider. The existing `META_ACCESS_TOKEN` is
injected only into a capability command that needs a provider call. The token
is never accepted via arguments, stdin, files, URLs, query strings, logs,
environment dumps, plans, receipts, journals, tests, or evidence. A dedicated
Kinko-managed Reader evidence-signing key is required for cross-client facts;
its public key and key ID are non-secret configuration. Kinko policies are
separate per runtime identity: Reader network GET plus signing, ordinary Writer
POST, watchdog Writer pause-only, and Deleter DELETE. Deployment validation
queries only Kinko policy metadata and key IDs, never values, and fails closed
if principals, executable constraints, inheritance, rotation, or revocation do
not match Section 6.2.

Each operation catalog row lists required Meta permissions. Missing,
unexpected, or excessive capability is reported as a sanitized policy/provider
error; the gateway does not request new permissions. Reader, Writer, and
Deleter credential types are nominal and not shared. Credential resolution
occurs after syntax, catalog, configuration, plan, confirmation, evidence,
spend, and initial durable-state gates, as applicable.

### 8.4 Error semantics

Errors use bounded JSON envelopes with stable categories: `invalidInput`,
`unknownOperation`, `catalogBlocked`, `unsupportedPlacement`,
`evidenceInvalid`, `confirmationRequired`, `spendDenied`, `credentialMissing`,
`providerDenied`, `transportOutcomeUnknown`, `reconciliationPending`,
`journalUntrusted`, `acceptanceQuotaDenied`, `clockDomainInvalid`,
`hierarchyIncomplete`, `pauseDeadlineMissed`, `liabilityUnbounded`,
`inventoryConflict`, `brokerRoleDenied`, `reconciliationGap`, and
`internalSanitized`. They include operation ID, surface, catalog revision, safe
state, and a correlation ID, but no raw request/response, URL, header, token,
body, exact account/object ID, or provider message by default. Provider
codes/subcodes may be retained only after allowlist-based sanitization.

## 9. Live acceptance and official-behavior evidence

Live execution is downstream, separately supervised work; this design neither
reads Kinko nor calls Meta. Before execution, official Meta reference pages for
the selected Graph version, object edges, status updates, deletion, placements,
permissions, and insights/spend fields must be rechecked and recorded with URL
and date. A documentation fetch failure or version mismatch blocks the
operation.

No sanitized live-response artifact was supplied to Node 1, so this draft makes
no new claim that a placement, status transition, budget, or delete result is
currently accepted. The rows below are the mandatory evidence contract; their
results remain pending until the authorized downstream live run.

The sanitized live matrix is:

| Domain | Required flow | Status expectation | Cleanup |
|---|---|---|---|
| Campaign | create, read, narrow update, PAUSED/ACTIVE/PAUSED where accepted | Starts PAUSED; gateway activation requires descendants paused and continuously monitored | Deleter DELETE then Reader absence/tombstone evidence |
| Ad set | create with JPY 500/day and placement recipe, read, update, PAUSED/ACTIVE/PAUSED where accepted | Starts PAUSED; gateway activation requires campaign and ad paused and continuously monitored | Child-first Deleter DELETE |
| Creative | create, read, narrow update; status only if officially supported | Non-serving; no invented ACTIVE field | Delete only after ad reference is absent |
| Ad | create, read, narrow update, PAUSED/ACTIVE/PAUSED where accepted | Starts PAUSED; gateway activation requires campaign and ad set paused and continuously monitored | First Deleter DELETE |
| Placement | Facebook, Instagram, Threads attempted as separate exact recipes when catalog-reviewed | Provider acceptance recorded independently; unsupported is fail-closed | Objects from accepted recipes follow normal cleanup |

Each sanitized evidence row records run ID, timestamp, official-source review
date, Graph version, capability surface, operation ID, path template (not the
resolved URL), placement label, HTTP status class, allowlisted provider
code/subcode, request/response schema digests, redacted object-ID digest,
observed status/effective status, currency, budget/spend minor units, latency,
result, cleanup state, and reviewer. It never stores a token, header, raw body,
raw URL, request dump, secret-bearing error, exact access credential, or enough
material to replay a request.

Observed behavior is not generalized. Documentation states “observed on
DATE/version/account/run” and distinguishes it from the cited official
contract. Initial live transport uses only the closed `acceptanceOnly` path in
Section 5; blocked rows and generic operations have no live-test bypass. A
successful live response enables no running catalog row by itself. It becomes
review input for a new catalog revision only after source review, tests,
reconciliation, permission mapping, and design disposition. Provider rejection
updates the exact future row to blocked and records the sanitized evidence.
Evidence must be committed only after secret scanning and manual review.

## 10. Observability and operational recovery

Local structured events record surface, operation ID, plan/record digest,
catalog revision, state transition, evidence age/key ID, interlock state,
reservation cents, spend delta, retry disposition, and sanitized error class.
Metrics count catalog denials, evidence failures, activation lease expiry,
pause CAS ownership/generations, nonzero spend, global reserved/observed cents,
uncovered liability components, acceptance slot counts, ACTIVE-to-PAUSE write
latency, outcome-unknown records, delete-session probe gaps/restarts,
reconciliation age, inventory generation/replica state, inventory rows without
terminal cleanup, evidence ID/nonce collisions, broker role denials,
mixed-epoch starts, delete blocks, and quarantined namespaces. Values remain
bounded and non-secret.

Alerts are mandatory when normal PAUSE has not started by one second, watchdog
PAUSE has not started by two seconds, an activation lease remains open at 60
seconds, any complete-hierarchy evidence is active/incomplete/unknown,
positive/unknown spend delta, failed pause,
outcome-unknown older than its reconciliation SLA, journal/head disagreement,
inventory/backup divergence, spend-ledger rollback, evidence-signer ACL drift,
acceptance quota mismatch, incomplete hierarchy enumeration, immediate-pause
deadline miss, delete-session gap, mixed epoch, or attempted delete outside
Deleter. The immediate response is
stop later work, let the CAS owner invoke only Writer's bounded recovery capsule
as needed, verify with Reader, preserve cleanup inventory, and quarantine
uncertain state. Deleter is cleanup, not an emergency serving control.

## 11. Migration, compatibility, and rollback

The three-client release introduces `capabilityEpoch=2`. Package metadata,
catalog schema/revision, generated projections, CLI artifacts, evidence,
configuration, mutation journals, replay registry, global spend ledger, cleanup
inventory/artifact registry, acceptance-run quotas, delete sessions,
trusted-head protocol, and broker role state all carry the epoch. Writer
and Deleter startup performs a broker handshake and requires exact epoch,
catalog revision, journal schema/domain, and configuration agreement before
credential access. A mixed, missing, future, or legacy epoch is a sanitized
hard failure. Reader may perform ordinary GET at its matching catalog epoch but
cannot issue evidence for a consumer at another epoch.

Migration is fail-closed and installation-atomic:

1. Build and verify a complete epoch-2 bundle containing the three clients,
   broker, catalogs, docs, checksums, provenance, migration verifier, and a
   capability-reduced rollback bundle. All network mutation rows are initially
   blocked.
2. In staging, move delete request, policy, journal specialization, CLI, tests,
   and catalog rows from Writer to Deleter; replace method-bearing Writer types;
   prove negative compilation and archive separation.
3. Quiesce epoch-1 Writer processes, prevent new launches, wait for held locks,
   and inventory every epoch-1 journal. Any in-flight/outcome-unknown delete or
   mutation blocks installation and is quarantined for explicit recovery.
4. Verify hashes/signatures, owner and directory permissions, Kinko executable
   ACLs, broker protocol, backups, and free space in a versioned staging
   directory. No live binary is overwritten in place.
5. Revoke the epoch-1 Writer executable from the launch-policy allowlist and
   Kinko command ACL; remove its directory from executable search paths. An
   explicit hash denylist prevents the broker and launch wrapper from serving a
   known epoch-1 Writer even if a stale copy remains.
6. Stop the old broker, atomically switch one owner-controlled `current`
   directory link to the verified epoch-2 bundle, start the epoch-2 broker, and
   require all three CLI self-checks and broker epoch handshakes. A partial
   switch or any mixed handshake leaves mutation disabled.
7. Run offline gates, register the exact acceptance authorization, and enable
   only reviewed `acceptanceOnly` operations. After live evidence and review,
   install a new production revision containing only reviewed `enabled` rows.

There is no source-compatible Writer delete migration. Consumers must link the
Deleter product and explicitly adopt its stronger workflow. Old offline plans
whose surface or method was Writer DELETE are permanently rejected, not
translated. Existing Writer POST journal records retain their identities;
delete-domain records are migrated only by a one-time offline verifier that
authenticates old terminal history and emits non-executable replay tombstones in
the Deleter namespace. In-flight or outcome-unknown old delete records block the
target and require review; they are never replayed or automatically migrated.

Rollback never restores the prior binary set. The prebuilt epoch-2
capability-reduced rollback bundle has Reader GET, Writer `status-paused` only
for authenticated inventory recovery, and Deleter cleanup only for already
inventoried objects; create, update, ACTIVE, generic POST/DELETE, and delete
plans for non-inventoried targets are blocked. It retains the same
epoch/protocol and contains no Writer DELETE symbols. Rollback atomically
switches `current` to that verified bundle,
revokes the failed bundle hash, and keeps the last trusted heads, replay/spend
state, acceptance quotas, delete sessions, and cleanup inventory/artifact
registry. A later forward release must use a new catalog
revision and pass migration checks again. Live-created objects remain PAUSED
and are physically cleaned only with the verified Deleter executable.

## 12. Verification strategy

### Deterministic gates

The implementation plan must run and retain sanitized output for:

```text
swift-format lint --recursive Package.swift Sources Tests Plugins
swift build
swift test
swift build -c release
swift package dump-package
swift package describe --type json
swift run meta-marketing-gateway-reader --help
swift run meta-marketing-gateway-writer --help
swift run meta-marketing-gateway-deleter --help
swift run meta-marketing-gateway-reader catalog list
swift run meta-marketing-gateway-writer catalog list
swift run meta-marketing-gateway-deleter catalog list
scripts/verify-target-separation.sh
scripts/verify-catalog-projections.sh
scripts/verify-focused-safety-tests.sh
scripts/verify-reproducible-archives.sh
scripts/verify-no-secret-artifacts.sh
gitleaks detect --source . --no-git
semgrep scan --config auto .
```

Archive checks require three reproducible archives and checksums, SBOM, source
inventory, and provenance. Reader contains only Reader; Writer contains Writer
and the generic trusted-head broker; Deleter contains Deleter and the same
method-neutral broker. Reader and Writer archives contain no Deleter module,
symbol, operation ID, CLI text, `DELETE` method token, or physical-delete policy.
The Deleter archive contains no Writer POST operations. Absolute paths,
credentials, secret-shaped strings, raw live artifacts, build tools, and the
canonical full manifest are absent.

### Compile-time and adversarial coverage

- A Reader-only fixture cannot import Writer/Deleter, create a body-bearing
  request, name POST/DELETE, or inject a transport method.
- A Writer-only fixture cannot import Deleter, name or construct DELETE, use a
  deletion operation ID, or recover a generic method transport.
- Package graph, emitted module interfaces, symbols, strings, CLI help,
  generated catalogs, and archives prove the same separation.
- Catalog mutation tests reject every surface/method/effect mismatch and
  require deterministic three-way generation.
- Typed/generic parity tests exercise alternate origins, encoded traversal,
  case/duplicate carriers, version drift, operation-ID substitution, schema
  smuggling, placement fallback, and unknown endpoints.
- Writer tests cover all paused creates, updates, status transitions, interlock,
  lease/watchdog, rollback pause exception, budget/FX reservation, evidence
  replay, credential ordering, crash boundaries, and spend uncertainty.
- Evidence tests prove Kinko ACL metadata, distinct OS identities, executable
  signature/digest/path verification, no child inheritance/core dump, key
  rotation/revocation, signature failure, exact audience/purpose/operation/plan/
  configuration/target binding, independent evidence-ID and nonce global
  collision rejection across Writer/Deleter/active/tombstone states,
  reserve-to-consume CAS, expiry tombstones, and cross-surface replay denial.
- Clock tests cover same-session process restart, broker restart, OS reboot,
  cross-host envelopes, wall-clock jumps, negative/future/wrapped ticks, missed
  freshness bounds, and mandatory re-observation after domain change.
- Broker authorization tests exercise every allowed and forbidden cell of the
  role matrix, wrong socket/UID/executable/digest/epoch, missing or wrong signed
  artifact, transition skip, same UID with another binary, and state
  non-mutation on denial.
- Activation tests inject incomplete pagination, filtered permissions,
  pre-existing and concurrently created external ancestors/descendants/
  references, active/pending/unknown states, modification races, monitor loss/
  rate limiting, process signals, cancellation, normal/watchdog contention,
  owner death at each CAS boundary, Kinko outage, outcome-unknown ACTIVE/PAUSE,
  normal one-second and watchdog two-second deadline misses, bounded recovery
  generations, and capsule expiry/exhaustion.
- Acceptance-run tests start concurrent and restarted drivers across catalog
  revisions; prove one authorization, atomic per-type slot reservation before
  create `inFlight`, no refund after possible send, marker reconciliation,
  quota exhaustion, cancellation/expiry cleanup-only behavior, permanent close,
  and no revision-based counter reset.
- Spend tests use multiple processes and crash injection to prove one global
  lock, authenticated monotonic reservation, no refund/reuse, additive
  uncovered-liability arithmetic, one-to-one coverage allocation, overlapping
  pending/unbilled/external/high-water/new components, counter reset, FX source/
  direction/freshness/signature/replay/rounding, provider multiplier, delayed/
  unknown reporting, indefinite settlement, and strict denial at 2000 cents.
- Deleter tests cover exact target confirmation, child-first references,
  separate namespace, at-most-one send, response-to-outcomeUnknown behavior,
  signed absence reconciliation, terminal-only retry, and inability to accept a
  POST body or Writer plan.
- Delete reconciliation fixtures cover presence, documented tombstones,
  independent edge absence, 404 with and without proven permissions, 401/403,
  429/5xx/timeouts, inconsistent reads, eventual consistency, creative
  references, per-probe signed envelopes, incomplete pagination, ordinal
  duplication, allowed-lateness/max-gap boundaries, missed-probe window restart,
  Reader/Deleter/broker restart, clock-domain change, terminal aggregation,
  no-bytes-sent, provider-proven no-effect, horizon expiry, and indefinite
  quarantine. Continued presence after a possible send never alone permits
  retry.
- Cleanup-inventory tests inject response loss, host restart, one/multiple
  marker discoveries, every primary-only/backup-only/both/head-old/prepared/
  committed/conflicting generation permutation, rollback, missing Kinko data
  key, concurrent Writer/Deleter updates, preservation of every unique ID,
  handle-only plan/request/receipt enforcement, unregistered artifacts, core/
  swap/snapshot retention, digest-only compaction, and verified exact-ID
  erasure.
- Catalog tests prove only exact typed complete rows can be `acceptanceOnly`,
  blocked/generic rows cannot enter acceptance dispatch, account/run/budget/
  epoch bounds cannot broaden, and production artifacts contain no acceptance
  symbol or manifest.
- Epoch tests reject every package/catalog/journal/broker version-skew
  permutation, stale epoch-1 Writer hashes and plans, partial installation, and
  rollback attempts that reintroduce Writer DELETE; the capability-reduced
  epoch-2 rollback retains recovery state.
- Focused cross-feature tests prove old Writer delete plans fail, no operation
  can cross-consume another surface's evidence or journal, and no generic path
  bypasses an exact gate.

### Review and live gates

Node 1 design self-review, independent deep review, broad integration review,
and adversarial review record findings by severity, remediation, and
disposition. Any unresolved high or medium finding keeps routing closed. Live
acceptance begins only after offline gates pass and ends only after every object
is paused, spend is verified, child-first Deleter cleanup is reconciled, and
evidence is sanitized and scanned. The complete implemented source tree and
artifacts then route to the source-security workflow.

## 13. Cross-feature impacts

- `Package.swift`: third library/product/executable/test targets; optional
  method-neutral safety extraction; strict dependency graph.
- `Sources`: Writer request/transport/CLI/policy lose DELETE; Deleter gains
  delete-only equivalents; Reader gains signed evidence recipes without
  mutation capability.
- Runtime identity and Kinko policy: Reader-only evidence signer and
  spend-authority ACLs with executable attestation; watchdog pause-only Writer
  ACL; rotation/revocation checks.
- `Catalog` and plugin/generator: schema becomes three-surface and emits three
  exhaustive projections plus deterministic documentation; exact typed
  `acceptanceOnly` bootstrap rows are excluded from production archives.
- Durable safety state: global evidence replay registry, activation/spend ledger,
  acceptance-run/quota registry, broker role sockets/matrix, delete observation
  sessions, encrypted two-phase cleanup inventory/backup, artifact registry,
  cross-process locking, trusted heads, retention, and alerts.
- `Tests`: deletion tests move to Deleter; negative compilation, cross-surface,
  activation interlock, placement, spend, and live acceptance coverage grows
  beyond the 91-test preservation baseline.
- `docs`, README, and SECURITY: three-client commands, Kinko boundary, live
  evidence ledger, cleanup rules, migration incompatibility, and support matrix.
- `scripts` and release: three archives, separation/symbol checks, reproducible
  checksums/SBOM/provenance, epoch-atomic install and capability-reduced
  rollback bundles, legacy-binary revocation, static analysis, and secret
  scanning.
- Existing consumers: Reader is source-compatible; Writer POST APIs may require
  methodless type migration; Writer delete callers intentionally break and must
  explicitly adopt Deleter.

## 14. Provisional decisions

These choices are conservative defaults made without pausing the workflow.

### PD-001: No shared HTTP-method enum

**Decision:** Use surface-specific request and transport types with implicit
methods. **Why confirmation would normally be needed:** It intentionally breaks
generic Writer API source compatibility. **Why preferable:** It makes DELETE
unrepresentable to Reader/Writer consumers and is stronger than runtime policy.
**If later rejected:** A replacement must preserve equivalent negative compile,
link, symbol, and archive proof; a public all-method type is not acceptable.

### PD-002: Signed Reader evidence instead of hidden GET in mutation clients

**Decision:** Writer and Deleter consume short-lived, Kinko-key-signed Reader
evidence and have no GET transport. The signer requires a distinct Reader OS
identity, executable-bound Kinko ACL, deployment attestation, and preferably a
non-exportable key. Evidence IDs and nonce digests have audience-independent
global uniqueness, and freshness uses one broker host/boot/session monotonic
clock domain. **Why confirmation would normally be needed:** It adds key
provisioning, runtime identities, and multi-command orchestration. **Why
preferable:** Each client has one network method and other operator processes
cannot forge cross-client facts. **If later rejected:** A reviewed alternative
must keep GET outside the Writer/Deleter public and transport surfaces and
provide equal executable isolation, authenticity, freshness, revocation, and
global replay protection.

### PD-003: Gateway-interlocked activation with continuous monitoring

**Decision:** Exercise ACTIVE on one hierarchy level at a time while the other
fully enumerated serving closure remains non-serving, with two-second pre-send
evidence and continuous complete monitoring, a 60-second outer lease,
CAS-owned bounded recovery, normal PAUSE write within one second of ACTIVE
write, and watchdog PAUSE write within two seconds. **Why confirmation would
normally be needed:** It may not exercise real delivery and adds operational
identities/timing. **Why preferable:** It validates status transitions while
minimizing exposure and detecting external objects/races. **If later rejected:**
A new high-risk review must specify smaller provable exposure, independent pause
supervision, complete external hierarchy handling, and explicit authorization
before any full-chain activation.

### PD-004: Exact JPY 500 daily budget and conservative full-budget reservation

**Decision:** Use exactly JPY 500/day if Meta accepts it; never auto-increase.
Reserve the provider-bounded maximum using an approved public FX source and 25%
adverse margin in a global authenticated monotonic ledger; add every independent
uncovered liability and allow only exact one-to-one coverage allocations.
Reservations are not refunded within the workflow. **Why confirmation would
normally be needed:** Budget, FX source, additive attribution, and one-way
reservation are business choices. **Why preferable:** It follows the user
preference, prevents maximum-based undercounting, proves the strict aggregate
cap, and does not rely on immediate pause or prompt reporting. **If later
rejected:** Update the cataloged model through review; no run may use an
unreviewed amount, reuse authority, net ambiguous liabilities, or reach USD
20.00.

### PD-005: Shared method-neutral broker, separate journals

**Decision:** Writer and Deleter may package the same trusted-head broker binary
but use disjoint configs, role sockets, executable/OS-principal policies,
namespaces, domain tags, and journals under an exhaustive message matrix. **Why
confirmation would normally be needed:** A dedicated Deleter broker would offer
stronger operational isolation at higher complexity. **Why preferable:** The
broker has no Graph/method authority, while role, journal, and policy
independence are still enforceable. **If later rejected:** Add separately named
role brokers without adding a Writer/Deleter dependency edge or weakening
migration.

### PD-006: No backward-compatible Writer delete shim

**Decision:** Writer delete source and old plans fail explicitly after the
split. **Why confirmation would normally be needed:** Existing consumers may
need migration work. **Why preferable:** Any shim preserves the capability the
feature is intended to remove. **If later rejected:** Provide documentation or
tooling that generates a new Deleter plan, never a forwarding Writer API.

### PD-007: Closed acceptance-only catalog bootstrap

**Decision:** Allow only complete exact typed rows to use a build-time
`acceptanceOnly` disposition bound to one broker-anchored, non-reopenable run
with immutable per-type non-refundable create quotas; production archives
reject it. **Why confirmation would normally be needed:** It introduces a
distinct pre-production artifact, durable quota state, and approval step. **Why
preferable:** It breaks the live-evidence cycle without allowing blocked/generic
operations or concurrent drivers to bypass catalog/object bounds. **If later
rejected:** Initial enablement must rely entirely on reviewed non-live evidence
and treat live execution as post-enable validation; no undocumented live-test
switch is acceptable.

### PD-008: Durable encrypted exact-ID cleanup inventory

**Decision:** Persist exact created IDs only in immutable authenticated encrypted
inventory generations and their governed backup, using a broker two-phase head;
all other artifacts contain handles/digests. **Why confirmation would normally
be needed:** Exact IDs, cross-volume generations, privacy erasure, and retention
have operational costs. **Why preferable:** Every partial-write permutation
preserves unique IDs while recovery and cleanup survive response or host loss,
and erasure has a closed artifact scope. **If later rejected:** Supply an
equally durable, authenticated, independently recoverable object-discovery and
all-artifact retention mechanism; ephemeral plans, cleartext copies, or
digest-only recovery records are insufficient.

### PD-009: Epoch-2 migration with capability-reduced rollback

**Decision:** Reject mixed epochs, revoke the legacy Writer binary, install via
one atomic bundle switch, and roll back only to an epoch-2 bundle without Writer
DELETE. **Why confirmation would normally be needed:** It intentionally forbids
ordinary binary downgrade and adds deployment controls. **Why preferable:** A
rollback cannot recreate the deleted capability or reinterpret journals.
**If later rejected:** Any replacement must prove legacy Writer DELETE cannot
launch and preserve exact state/epoch compatibility; restoring epoch 1 is not
an option.

## 15. Assumptions, open questions, and residual risks

### Assumptions

- Meta API versions, permissions, placement names, field constraints, deletion
  results, and validation behavior can change and require dated official review
  plus sanitized live verification.
- Operation-specific catalog gates remain authoritative for typed and generic
  APIs.
- SwiftPM dependency, negative-compilation, symbol/string, CLI, and archive
  evidence—not naming conventions—prove isolation.
- The authorized account is accessible using the named Kinko key and reports
  its currency through an allowlisted Reader operation; no secret value is
  assumed or recorded.
- The trusted-head broker's separate OS-identity deployment contract remains
  available to Writer and Deleter.
- The reviewed document and its two named predecessor designs are jointly
  authoritative where this document does not explicitly supersede them.
- Blocked catalog operations cannot use an undocumented live-test bypass.
- External account actors and provider reporting delays remain possible even
  under the operator change freeze.
- Concurrent and restarted acceptance, Reader, Writer, watchdog, and Deleter
  processes are possible and must share broker-anchored state.
- External actors may create or activate hierarchy objects during the
  irreducible observation-to-send interval.
- Pending/unbilled, high-water, external, and new-operation liabilities are
  independent unless an immutable one-to-one coverage allocation proves
  otherwise.
- Crashes may occur after either inventory replica write or either broker
  prepare/commit transition.
- No undocumented tuple-key behavior supplies replay uniqueness; the explicit
  audience-independent evidence-ID and nonce indices are required.

### Open questions resolved only by evidence

- Which reviewed Graph version and exact fields Meta accepts on the execution
  date.
- Whether JPY 500/day meets the account and objective minimum without a larger
  budget.
- Which Facebook, Instagram, and Threads placement recipes the account,
  objective, identity, and creative accept.
- Whether each object accepts ACTIVE while its hierarchy peers are paused and
  how status/effective-status is reported.
- The exact sanitized success/absence/tombstone semantics for each DELETE.
- Whether the deployed Kinko/OS combination supports the required
  executable-bound signing-key ACL and non-exportable handle; otherwise live
  mutation remains blocked.
- Which policy-approved central-bank or governmental FX publication and dated
  Meta delivery/reporting bounds satisfy the spend ledger contracts.

Every unknown maps to a per-operation blocked state; none invites an unsafe
default or requires user confirmation before design review.

### Residual risks

- Meta behavior, permissions, versions, and placements may drift after review.
- Spend could accrue through provider pacing, external actors, or a failed
  gateway interlock despite continuous monitoring and conservative reservation;
  provider reads and writes cannot be atomic.
- Cross-process evidence signing adds key-rotation and availability risk.
- Broker/socket role-policy or clock-domain failure disables all mutation and
  can force re-observation or prolonged recovery.
- A compromised executable with direct token access is outside compile-time API
  isolation; least-privilege Meta tokens and process controls remain important.
- Graph DELETE may yield eventual consistency or a tombstone rather than
  immediate erasure, leaving outcome-unknown records that require later
  reconciliation.
- Missing finite provider deletion or spend-reporting bounds can retain cleanup
  inventory and spend reservations indefinitely.
- Cleanup data-key, replica, or snapshot-policy unavailability can prevent
  cleanup completion or verified exact-ID erasure.
- Shared broker availability can affect both mutation surfaces, though separate
  namespaces prevent authority crossover.
- Generic relative-path APIs remain potential escape hatches if any exact
  catalog, canonicalization, or generated-dispatch invariant regresses.
- Acceptance-only dispatch and legacy-binary revocation are critical release
  boundaries; a packaging or launch-policy regression could bypass intended
  rollout state.

## 16. Design review record and routing

### Addressed deep-review feedback

| Prior severity | Finding | Revision disposition |
|---|---|---|
| High | Evidence signer could be retrieved by another process. | Addressed in 6.2, 8.3, 12, and PD-002 with distinct Reader identity, executable-bound Kinko ACL, non-exportability/fallback denial, attestation, rotation, and revocation. |
| High | Evidence lacked single audience/plan binding and global replay state. | Addressed in 6.2 and 7.2 with exact audience/purpose/operation/plan/configuration/target binding and a global trusted-head replay registry. |
| High | Stale evidence and external actors defeat absolute interlock. | Addressed in 6.3 and 7.3 by qualifying gateway authority, two-second pre-send evidence, continuous monitoring, change freeze, and emergency child-to-parent pause. |
| High | Normal/watchdog pause races and outcome-unknown recovery were undefined. | Addressed in 6.3 with one CAS owner, credential/identity bounds, cancellation/crash transitions, a finite recovery capsule, and distinct pause generations. |
| High | Spend ceiling lacked global authenticated crash-safe accounting. | Addressed in 7.3 with the monotonic broker-anchored ledger, cross-process lock, official FX/provider bounds, no refund, crash recovery, and indefinite settlement on uncertainty. |
| High | Ephemeral exact IDs could make cleanup impossible. | Addressed in 6.4.1 and 8.1 with authenticated encrypted primary/backup inventory, discovery recovery, retention, and verified compaction. |
| High | Live evidence and catalog enablement were circular. | Addressed in 5 and 9 with a generated, exact, non-generic `acceptanceOnly` state excluded from production artifacts. |
| Middle | Delete reconciliation and safe retry were not deterministic. | Addressed in 6.4.2 with per-object contracts and an exhaustive observation/action table; presence after possible send never alone permits retry. |
| Middle | Mixed-version installation and rollback could restore Writer DELETE. | Addressed in 11, 12, and PD-009 with capability epoch 2, startup handshake, atomic switch, legacy revocation, and a reduced rollback bundle. |

### Addressed repeat deep-review feedback

| Prior severity | Finding | Revision disposition |
|---|---|---|
| High | Audience-bearing registry keys allowed cross-surface evidence-ID/nonce reuse. | Addressed in 6.2 and 12 with two audience-independent global unique indices covering all active states and permanent tombstones. |
| High | Activation ignored incomplete or active external hierarchy state. | Addressed in 6.3 with complete permission-verified ancestor/descendant/reference enumeration, pagination proof, deny states, and identical continuous monitoring. |
| High | Acceptance object counts lacked durable global lifecycle/quota enforcement. | Addressed in 5.1 and 6.3 with a broker-anchored non-reopenable run and atomic non-refundable per-type create slots. |
| High | Maximum-based spend arithmetic undercounted independent liabilities. | Addressed in 7.3 with explicit additive components, one-to-one coverage allocations, baseline/high-water rules, and the prospective-exposure equation. |
| High | Two-copy inventory partial-write recovery could discard the only ID. | Addressed in 6.4.1 with immutable generations, broker prepare/commit, an exhaustive recovery table, and preserve-all conflict handling. |
| Middle | Broker peer roles and transition authority were unspecified. | Addressed in 4.1 and 12 with role sockets, OS/executable authentication, an exhaustive message matrix, required signed artifacts, and negative tests. |
| Middle | Cross-process monotonic freshness lacked a clock domain. | Addressed in 6.2 with broker host/boot/session ticks, same-domain checks, restart/reboot invalidation, and clock adversarial tests. |
| Middle | Immediate pause lacked a testable write deadline. | Addressed in 6.3 with normal PAUSE write by one second and watchdog PAUSE write by two seconds from ACTIVE first-byte write, without waiting for response. |
| Middle | Delete consistency-window observations lacked durable session semantics. | Addressed in 6.4.2 with broker-anchored sessions, scheduled signed probes, gap/lateness/completeness rules, restart handling, and terminal aggregation. |
| Middle | Exact IDs could persist outside inventory retention controls. | Addressed in 6.4, 8.1, 12, and PD-008 by allowing persistent exact IDs only in encrypted inventory generations/backups and using handles/digests everywhere else. |

| Review | Status | Acceptance |
|---|---|---|
| Node 1 remediation 1 | complete | Addressed seven high and two middle findings from deep review attempt 1. |
| Deep review attempt 1 | revision required | Seven high and two middle findings returned to Node 1. |
| Deep review attempt 2 | revision required | Five high and five middle findings returned to Node 1; two prior findings validated and others refined/reopened. |
| Node 1 remediation 2 | complete | All five high and five middle findings from attempt 2 are explicitly addressed; independent repeat review required. |
| Deep review attempt 3 | pending | Must report no unresolved high or medium finding. |
| Broad review | pending | Must report no unresolved high or medium finding. |
| Adversarial review | pending | Must report no unresolved high or medium finding. |

Routing is fail-closed while any high or medium finding remains. On accepted
design, route this document and the active implementation plan to the
implementation-completion workflow. Do not route to source security before
implementation. After implementation, route the complete explicit source tree,
tests, catalog, docs, scripts, and release evidence to the source-security
workflow.
