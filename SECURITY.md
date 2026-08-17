# Security policy

Credentials may only enter a gateway process through an explicit minimal Kinko
environment allowlist, such as `kinko exec --env META_ACCESS_TOKEN -- command`.

Mutation policy denials are fail-closed and sanitized. Authorization is derived
from the exact request, including declared JSON media type, rather than caller
risk metadata. Durable journal records and trusted heads are schema-versioned
and authenticate record identity, plan digest, and retained-chain boundaries.
Legacy or missing-schema records are not automatically migrated and cannot be
used. Keep the trusted-head store independently protected; administrative
recovery requires independently verified expected-head evidence.
The project does not support local credential files, `.env`, keychain fallback,
stdin secrets, secret CLI flags, alternate origins, arbitrary headers, or
redirect-following authorization.

Report a potential issue without attaching credential material. Do not include
tokens, request bodies containing customer data, authorization headers, or
provider error bodies in an issue.

The trusted-head broker is a separate writer-only executable. It must run under
a different OS identity, own its socket and head storage, and never share that
storage with the writer. Credentialed writer preview, apply, and reconciliation
remain blocked until that supervised deployment, authenticated principal
verification, operation-specific asset proof, and reconciliation contracts are
implemented and re-reviewed.
