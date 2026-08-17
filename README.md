# Meta Marketing Gateway

A Swift 6 gateway for the Meta Graph and Marketing APIs. Capabilities are split
into separately linked clients: Reader is GET-only, Writer is POST-only, and
Deleter is DELETE-only. Typed campaign, ad set, creative, ad, and insights
routes cover the major Ads domains; conservative generic relative-path routes
preserve coverage as Meta adds APIs.

## Local verification

```bash
mise run lint
mise run test
mise run build
swift run meta-marketing-gateway-reader --help
swift run meta-marketing-gateway-writer --help
swift run meta-marketing-gateway-deleter --help
mise run secret-audit
mise run supply-chain-audit
```

## Credentials

Kinko is the only supported credential store. Do not create credential files,
use `.env`, pass a secret flag, or print credential values. For a read that is
separately authorized, inject the smallest explicit allowlist:

```bash
kinko exec --env META_ACCESS_TOKEN -- \
  swift run meta-marketing-gateway-reader graph get \
  --api-version v25.0 --path me --query fields=id
```

Live Writer calls require a request file that binds the ad account plus an exact
`--confirm-account act_N`; Writer has no DELETE symbol or route. Physical
deletion requires the separate Deleter executable and an exact repeated
`--confirm-path`. Both accept credentials only from Kinko. Neither client
automatically retries mutations. Endpoint expressibility does not grant Meta
permissions, App Review, business verification, or resource access.

```bash
kinko exec --env META_ACCESS_TOKEN -- \
  swift run meta-marketing-gateway-deleter graph delete \
  --api-version v25.0 --path OBJECT_ID --confirm-path OBJECT_ID
```

The initial typed Ads compatibility matrix was reviewed against Meta's
[Marketing API overview](https://developers.facebook.com/docs/marketing-api/overview/)
and [Graph API versioning](https://developers.facebook.com/docs/graph-api/guides/versioning/)
on 2026-08-15. Revalidate those sources before changing versions or enabling
provider-specific limits, retry codes, or upload hosts.

## Typed reader and local file inputs

Typed reader routes validate closed field selections, account IDs, pagination,
and optional JSON filter files before resolving Kinko credentials. Filter files
must be owner-controlled regular files and use only the documented filter
shape; raw JSON fragments and token-shaped query fields are rejected.

```bash
kinko exec --env META_ACCESS_TOKEN -- \
  swift run meta-marketing-gateway-reader ads list adaccounts \
  --api-version v25.0 --fields id,name \
  --filter-file filters.json
```

Multipart inputs are bounded, revalidate file identity for every chunk, and
stream through an owner-only temporary file to the fixed
`https://graph.facebook.com/vNN.N/act_<id>/adimages` upload edge; request and
response bodies are bounded in memory and no resumable-session identifier is
persisted. Video and resumable uploads remain disabled until their provider
contracts are independently revalidated. Offline planning serializes a distinct
`OfflineMutationPlan` schema that cannot be decoded as an executable
`MutationPlan`.

Durable journals use an atomic schema rollout: records, events, and separately
protected trusted heads bind the namespace, complete journal key, plan digest,
record filename, and retained-chain boundary. Legacy or missing-schema journal
material is quarantined and fails closed; there is no automatic migration.
Trusted-head recovery is an administrative operation requiring independently
protected expected-head evidence.
