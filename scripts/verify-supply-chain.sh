#!/bin/sh
set -eu

test -f Package.swift
test -f .github/workflows/ci.yml
rg -q 'actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683' .github/workflows/ci.yml
rg -q 'jdx/mise-action@c37c93293d6b742fc901e1406b8f764f6fb19dac' .github/workflows/ci.yml
rg -q 'gitleaks/gitleaks-action@ff98106e4c7b2bc287b24eaf42907196329070c7' .github/workflows/ci.yml
rg -q 'semgrep/semgrep-action@713efdd345f3035192eaa63f56867b88e63e4e5d' .github/workflows/ci.yml
# This package intentionally has no third-party runtime dependencies.
! rg -q '\.package\(' Package.swift
