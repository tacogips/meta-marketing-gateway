#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
first="$(mktemp -d)"
second="$(mktemp -d)"
first_scratch_root="$(mktemp -d)"
second_scratch_root="$(mktemp -d)"
trap 'rm -rf "$first" "$second" "$first_scratch_root" "$second_scratch_root"' EXIT
META_MARKETING_GATEWAY_SWIFTPM_SCRATCH_PATH="$first_scratch_root" \
  sh scripts/build-local-archives.sh "$first" >/dev/null
META_MARKETING_GATEWAY_SWIFTPM_SCRATCH_PATH="$second_scratch_root" \
  sh scripts/build-local-archives.sh "$second" >/dev/null
cmp "$first/meta-marketing-gateway-reader.tar.gz" "$second/meta-marketing-gateway-reader.tar.gz"
cmp "$first/meta-marketing-gateway-writer.tar.gz" "$second/meta-marketing-gateway-writer.tar.gz"
cmp "$first/meta-marketing-gateway-deleter.tar.gz" "$second/meta-marketing-gateway-deleter.tar.gz"
tar -tzf "$first/meta-marketing-gateway-writer.tar.gz" | rg -x 'meta-marketing-gateway-trusted-head-broker'
! tar -tzf "$first/meta-marketing-gateway-reader.tar.gz" | rg 'writer|trusted-head-broker'
mkdir "$first/extracted-reader" "$first/extracted-writer"
mkdir "$first/extracted-deleter"
tar -xzf "$first/meta-marketing-gateway-reader.tar.gz" -C "$first/extracted-reader"
tar -xzf "$first/meta-marketing-gateway-writer.tar.gz" -C "$first/extracted-writer"
tar -xzf "$first/meta-marketing-gateway-deleter.tar.gz" -C "$first/extracted-deleter"
"$first/extracted-reader/meta-marketing-gateway-reader" --help >/dev/null
"$first/extracted-writer/meta-marketing-gateway-writer" --help >/dev/null
"$first/extracted-deleter/meta-marketing-gateway-deleter" --help >/dev/null
cmp "$first/SHA256SUMS" "$second/SHA256SUMS"
cmp "$first/SBOM.spdx" "$second/SBOM.spdx"
cmp "$first/provenance-input.json" "$second/provenance-input.json"
command -v gitleaks >/dev/null
gitleaks detect --source "$first" --no-git
gitleaks detect --source "$second" --no-git
sh "$script_dir/validate-spdx.sh" "$first/SBOM.spdx" \
  "$(shasum -a 256 "$first/meta-marketing-gateway-reader.tar.gz" | awk '{print $1}')" \
  "$(shasum -a 256 "$first/meta-marketing-gateway-writer.tar.gz" | awk '{print $1}')" \
  "$(shasum -a 256 "$first/meta-marketing-gateway-deleter.tar.gz" | awk '{print $1}')"
