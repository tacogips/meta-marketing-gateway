#!/bin/sh
set -eu

test -f Catalog/meta-capabilities.json
test -f docs/capabilities.md
command -v jq >/dev/null
work_root="$(mktemp -d)"
scratch_root="$(mktemp -d)"
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
trap 'rm -rf "$work_root" "$scratch_root"' EXIT
jq -e '
  .reviewDate as $reviewDate |
  .schema == 1 and
  (.reviewDate | type == "string") and
  (.operations | type == "array" and length > 0) and
  ((.operations | map(.id) | length) == (.operations | map(.id) | unique | length)) and
  ([.operations[] | (.reviewDate | type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$"))] | all) and
  (.reviewDate == "2026-08-15") and
  ([.operations[] | .reviewDate == $reviewDate] | all) and
  ([.operations[] | (.source | type == "string" and startswith("https://developers.facebook.com/"))] | all) and
  ([.operations[] | .surface] | all(. == "reader" or . == "writer" or . == "deleter")) and
  ([.operations[] | select(.surface == "reader") | .method] | all(. == "GET")) and
  ([.operations[] | select(.surface == "writer") | .method] | all(. == "POST")) and
  ([.operations[] | select(.surface == "deleter") | .method] | all(. == "DELETE"))
' Catalog/meta-capabilities.json >/dev/null
! rg -n 'MetaGraphWriter|MutationJournal|TrustedHead' Sources/MetaMarketingGatewayReaderKit
rg -q 'v25.0' Sources/MetaMarketingGatewayReaderKit/MetaAdsReader.swift
swift run --scratch-path "$scratch_root" MetaCapabilityCatalogGenerator --input Catalog/meta-capabilities.json --surface reader \
  --swift-output "$work_root/reader.swift"
swift run --scratch-path "$scratch_root" MetaCapabilityCatalogGenerator --input Catalog/meta-capabilities.json --surface reader \
  --swift-output "$work_root/reader-repeat.swift"
swift run --scratch-path "$scratch_root" MetaCapabilityCatalogGenerator --input Catalog/meta-capabilities.json --surface writer \
  --swift-output "$work_root/writer.swift"
swift run --scratch-path "$scratch_root" MetaCapabilityCatalogGenerator --input Catalog/meta-capabilities.json --surface writer \
  --swift-output "$work_root/writer-repeat.swift"
swift run --scratch-path "$scratch_root" MetaCapabilityCatalogGenerator --input Catalog/meta-capabilities.json --surface deleter \
  --swift-output "$work_root/deleter.swift"
swift run --scratch-path "$scratch_root" MetaCapabilityCatalogGenerator --input Catalog/meta-capabilities.json --surface deleter \
  --swift-output "$work_root/deleter-repeat.swift"
swift run --scratch-path "$scratch_root" MetaCapabilityCatalogGenerator --input Catalog/meta-capabilities.json \
  --documentation-output "$work_root/capabilities.md"
swift run --scratch-path "$scratch_root" MetaCapabilityCatalogGenerator --input Catalog/meta-capabilities.json \
  --documentation-output "$work_root/capabilities-repeat.md"
cmp "$work_root/reader.swift" "$work_root/reader-repeat.swift"
cmp "$work_root/writer.swift" "$work_root/writer-repeat.swift"
cmp "$work_root/deleter.swift" "$work_root/deleter-repeat.swift"
cmp "$work_root/capabilities.md" "$work_root/capabilities-repeat.md"
cmp "$work_root/capabilities.md" docs/capabilities.md
! rg -F -q 'meta.generic.write' "$work_root/reader.swift"
! rg -F -q 'meta.graph.get' "$work_root/writer.swift"
! rg -F -q 'meta.generic.delete' "$work_root/writer.swift"
! rg -F -q 'meta.generic.write' "$work_root/deleter.swift"
jq -r '.operations[] | select(.surface == "reader") | .id' Catalog/meta-capabilities.json | \
  while IFS= read -r operation; do
    if [ "$operation" = "meta.graph.get" ]; then
      rg -F -q 'func get(' Sources/MetaMarketingGatewayReaderKit
    else
      rg -F -q "$operation" Sources/MetaMarketingGatewayReaderKit
    fi
    rg -F -q "$operation" "$work_root/reader.swift"
  done
sh "$script_dir/run-swiftpm-external.sh" run meta-marketing-gateway-reader catalog list > "$work_root/reader-cli.json"
sh "$script_dir/run-swiftpm-external.sh" run meta-marketing-gateway-writer catalog list > "$work_root/writer-cli.json"
sh "$script_dir/run-swiftpm-external.sh" run meta-marketing-gateway-deleter catalog list > "$work_root/deleter-cli.json"
jq -S '[.operations[] | select(.surface == "reader") | .id] | sort' Catalog/meta-capabilities.json > "$work_root/reader-expected-operations.json"
jq -S '[.operations[] | select(.surface == "writer") | .id] | sort' Catalog/meta-capabilities.json > "$work_root/writer-expected-operations.json"
jq -S '[.operations[] | select(.surface == "deleter") | .id] | sort' Catalog/meta-capabilities.json > "$work_root/deleter-expected-operations.json"
jq -S '[.operations[] | select(.surface == "reader") | {(.id): .availability}] | add' Catalog/meta-capabilities.json > "$work_root/reader-expected-availability.json"
jq -S '[.operations[] | select(.surface == "writer") | {(.id): .availability}] | add' Catalog/meta-capabilities.json > "$work_root/writer-expected-availability.json"
jq -S '[.operations[] | select(.surface == "deleter") | {(.id): .availability}] | add' Catalog/meta-capabilities.json > "$work_root/deleter-expected-availability.json"
jq -S '.operations | sort' "$work_root/reader-cli.json" > "$work_root/reader-cli-operations.json"
jq -S '.operations | sort' "$work_root/writer-cli.json" > "$work_root/writer-cli-operations.json"
jq -S '.operations | sort' "$work_root/deleter-cli.json" > "$work_root/deleter-cli-operations.json"
jq -S '.availabilityByOperation' "$work_root/reader-cli.json" > "$work_root/reader-cli-availability.json"
jq -S '.availabilityByOperation' "$work_root/writer-cli.json" > "$work_root/writer-cli-availability.json"
jq -S '.availabilityByOperation' "$work_root/deleter-cli.json" > "$work_root/deleter-cli-availability.json"
cmp "$work_root/reader-expected-operations.json" "$work_root/reader-cli-operations.json"
cmp "$work_root/writer-expected-operations.json" "$work_root/writer-cli-operations.json"
cmp "$work_root/deleter-expected-operations.json" "$work_root/deleter-cli-operations.json"
cmp "$work_root/reader-expected-availability.json" "$work_root/reader-cli-availability.json"
cmp "$work_root/writer-expected-availability.json" "$work_root/writer-cli-availability.json"
cmp "$work_root/deleter-expected-availability.json" "$work_root/deleter-cli-availability.json"
jq -r '.operations[] | .id' Catalog/meta-capabilities.json | \
  while IFS= read -r operation; do
    rg -F -q "$operation" docs/capabilities.md
  done
