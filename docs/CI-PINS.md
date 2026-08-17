# CI provenance

- `actions/checkout` is pinned to `11bd71901bbe5b1630ceea73d27597364c9af683`,
  the upstream `v4.2.2` tag, checked on 2026-08-15 with `git ls-remote`.
- `jdx/mise-action` is pinned to `c37c93293d6b742fc901e1406b8f764f6fb19dac`,
  the upstream `v2.4.4` tag; `gitleaks/gitleaks-action` is pinned to
  `ff98106e4c7b2bc287b24eaf42907196329070c7`, the upstream `v2.3.9` tag; and
  `semgrep/semgrep-action` is pinned to `713efdd345f3035192eaa63f56867b88e63e4e5d`,
  the upstream `v1` tag. All were checked on 2026-08-15 with `git ls-remote`.
- CI uses the `macos-14` hosted image and records `swift --version` in its log.
  The local release gate requires the same toolchain version for both builds.
