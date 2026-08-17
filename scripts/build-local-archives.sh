#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
archive_root="${1:-$(mktemp -d)}"
test -d "$archive_root"
test -z "$(find "$archive_root" -mindepth 1 -maxdepth 1 -print -quit)"
work_root="$(mktemp -d)"
scratch_root="${META_MARKETING_GATEWAY_SWIFTPM_SCRATCH_PATH:-$(mktemp -d)}"
test -d "$scratch_root"
if [ -n "${META_MARKETING_GATEWAY_SWIFTPM_SCRATCH_PATH:-}" ]; then
  trap 'rm -rf "$work_root"' EXIT
else
  trap 'rm -rf "$work_root" "$scratch_root"' EXIT
fi

mkdir -p "$work_root/reader" "$work_root/writer" "$work_root/deleter"
swift build -c release --scratch-path "$scratch_root"
binary_root="$(swift build -c release --scratch-path "$scratch_root" --show-bin-path)"
cp "$binary_root/meta-marketing-gateway-reader" "$work_root/reader/"
cp "$binary_root/meta-marketing-gateway-writer" "$work_root/writer/"
cp "$binary_root/meta-marketing-gateway-deleter" "$work_root/deleter/"
cp "$binary_root/meta-marketing-gateway-trusted-head-broker" "$work_root/writer/"
strip -S -x "$work_root/reader/meta-marketing-gateway-reader"
strip -S -x "$work_root/writer/meta-marketing-gateway-writer"
strip -S -x "$work_root/deleter/meta-marketing-gateway-deleter"
strip -S -x "$work_root/writer/meta-marketing-gateway-trusted-head-broker"
python3 "$script_dir/normalize-macho-uuid.py" \
  "$work_root/reader/meta-marketing-gateway-reader" \
  "$work_root/writer/meta-marketing-gateway-writer" \
  "$work_root/deleter/meta-marketing-gateway-deleter" \
  "$work_root/writer/meta-marketing-gateway-trusted-head-broker"
codesign --force --sign - "$work_root/reader/meta-marketing-gateway-reader"
codesign --force --sign - "$work_root/writer/meta-marketing-gateway-writer"
codesign --force --sign - "$work_root/deleter/meta-marketing-gateway-deleter"
codesign --force --sign - "$work_root/writer/meta-marketing-gateway-trusted-head-broker"
touch -t 200001010000 "$work_root/reader/meta-marketing-gateway-reader" "$work_root/writer/meta-marketing-gateway-writer" "$work_root/deleter/meta-marketing-gateway-deleter" "$work_root/writer/meta-marketing-gateway-trusted-head-broker"
tar -cf "$work_root/reader.tar" -C "$work_root/reader" meta-marketing-gateway-reader
tar -cf "$work_root/writer.tar" -C "$work_root/writer" meta-marketing-gateway-writer meta-marketing-gateway-trusted-head-broker
gzip -n -c "$work_root/reader.tar" > "$archive_root/meta-marketing-gateway-reader.tar.gz"
gzip -n -c "$work_root/writer.tar" > "$archive_root/meta-marketing-gateway-writer.tar.gz"
tar -cf "$work_root/deleter.tar" -C "$work_root/deleter" meta-marketing-gateway-deleter
gzip -n -c "$work_root/deleter.tar" > "$archive_root/meta-marketing-gateway-deleter.tar.gz"
tar -tzf "$archive_root/meta-marketing-gateway-reader.tar.gz" | rg -x 'meta-marketing-gateway-reader'
tar -tzf "$archive_root/meta-marketing-gateway-writer.tar.gz" | rg -x 'meta-marketing-gateway-writer'
tar -tzf "$archive_root/meta-marketing-gateway-writer.tar.gz" | rg -x 'meta-marketing-gateway-trusted-head-broker'
tar -tzf "$archive_root/meta-marketing-gateway-deleter.tar.gz" | rg -x 'meta-marketing-gateway-deleter'
! tar -tzf "$archive_root/meta-marketing-gateway-reader.tar.gz" | rg 'writer|trusted-head-broker'
! tar -tzf "$archive_root/meta-marketing-gateway-writer.tar.gz" | rg 'deleter'
! tar -tzf "$archive_root/meta-marketing-gateway-deleter.tar.gz" | rg 'reader|writer|trusted-head-broker'
swift --version > "$archive_root/TOOLCHAIN.txt"
{
  find Package.swift Sources Plugins Catalog docs scripts -type f -print
  printf '%s\n' mise.toml README.md SECURITY.md CONTRIBUTING.md
} | LC_ALL=C sort | while IFS= read -r source_file; do
  shasum -a 256 "$source_file"
done > "$archive_root/SOURCE-SHA256SUMS"
source_manifest_hash="$(shasum -a 256 "$archive_root/SOURCE-SHA256SUMS" | awk '{print $1}')"
reader_hash="$(shasum -a 256 "$archive_root/meta-marketing-gateway-reader.tar.gz" | awk '{print $1}')"
writer_hash="$(shasum -a 256 "$archive_root/meta-marketing-gateway-writer.tar.gz" | awk '{print $1}')"
deleter_hash="$(shasum -a 256 "$archive_root/meta-marketing-gateway-deleter.tar.gz" | awk '{print $1}')"
package_hash="$(shasum -a 256 Package.swift | awk '{print $1}')"
printf 'SPDXVersion: SPDX-2.3\nDataLicense: CC0-1.0\nSPDXID: SPDXRef-DOCUMENT\nDocumentName: MetaMarketingGateway-local\nDocumentNamespace: https://example.invalid/meta-marketing-gateway/%s\nCreator: Tool: SwiftPM-local-archive\nCreated: 2000-01-01T00:00:00Z\n\n##### Package\nPackageName: meta-marketing-gateway-reader\nSPDXID: SPDXRef-ReaderArchive\nPackageVersion: 0.2.0\nPackageDownloadLocation: NOASSERTION\nFilesAnalyzed: false\nPackageFileName: meta-marketing-gateway-reader.tar.gz\nPackageChecksum: SHA256: %s\nPackageLicenseConcluded: NOASSERTION\nPackageLicenseDeclared: NOASSERTION\n\n##### Package\nPackageName: meta-marketing-gateway-writer\nSPDXID: SPDXRef-WriterArchive\nPackageVersion: 0.2.0\nPackageDownloadLocation: NOASSERTION\nFilesAnalyzed: false\nPackageFileName: meta-marketing-gateway-writer.tar.gz\nPackageChecksum: SHA256: %s\nPackageLicenseConcluded: NOASSERTION\nPackageLicenseDeclared: NOASSERTION\n\n##### Package\nPackageName: meta-marketing-gateway-deleter\nSPDXID: SPDXRef-DeleterArchive\nPackageVersion: 0.2.0\nPackageDownloadLocation: NOASSERTION\nFilesAnalyzed: false\nPackageFileName: meta-marketing-gateway-deleter.tar.gz\nPackageChecksum: SHA256: %s\nPackageLicenseConcluded: NOASSERTION\nPackageLicenseDeclared: NOASSERTION\n\nRelationship: SPDXRef-DOCUMENT DESCRIBES SPDXRef-ReaderArchive\nRelationship: SPDXRef-DOCUMENT DESCRIBES SPDXRef-WriterArchive\nRelationship: SPDXRef-DOCUMENT DESCRIBES SPDXRef-DeleterArchive\n' "$package_hash" "$reader_hash" "$writer_hash" "$deleter_hash" > "$archive_root/SBOM.spdx"
printf '{"buildType":"local-swiftpm","publication":"none","packageSwiftSHA256":"%s","sourceInventorySHA256":"%s","artifacts":{"meta-marketing-gateway-reader.tar.gz":"%s","meta-marketing-gateway-writer.tar.gz":"%s","meta-marketing-gateway-deleter.tar.gz":"%s"},"toolchainFile":"TOOLCHAIN.txt"}\n' "$package_hash" "$source_manifest_hash" "$reader_hash" "$writer_hash" "$deleter_hash" > "$archive_root/provenance-input.json"
(cd "$archive_root" && shasum -a 256 *.tar.gz SBOM.spdx provenance-input.json SOURCE-SHA256SUMS TOOLCHAIN.txt > SHA256SUMS)
(
  cd "$archive_root"
  shasum -a 256 -c SHA256SUMS
  rg -q "PackageChecksum: SHA256: $reader_hash" SBOM.spdx
  rg -q "PackageChecksum: SHA256: $writer_hash" SBOM.spdx
  rg -q "\"sourceInventorySHA256\":\"$source_manifest_hash\"" provenance-input.json
  sh "$script_dir/validate-spdx.sh" SBOM.spdx "$reader_hash" "$writer_hash" "$deleter_hash"
)
printf '%s\n' "$archive_root"
