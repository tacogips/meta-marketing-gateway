#!/bin/sh
set -eu

spdx_file="$1"
reader_hash="$2"
writer_hash="$3"
deleter_hash="$4"

test "$(rg -c '^SPDXVersion: SPDX-2\.3$' "$spdx_file")" -eq 1
test "$(rg -c '^DataLicense: CC0-1\.0$' "$spdx_file")" -eq 1
test "$(rg -c '^SPDXID: SPDXRef-DOCUMENT$' "$spdx_file")" -eq 1
test "$(rg -c '^SPDXID: SPDXRef-ReaderArchive$' "$spdx_file")" -eq 1
test "$(rg -c '^SPDXID: SPDXRef-WriterArchive$' "$spdx_file")" -eq 1
test "$(rg -c '^SPDXID: SPDXRef-DeleterArchive$' "$spdx_file")" -eq 1
test "$(rg -F 'PackageChecksum: SHA256:' "$spdx_file" | wc -l | tr -d ' ')" -eq 3
rg -q "^PackageChecksum: SHA256: $reader_hash$" "$spdx_file"
rg -q "^PackageChecksum: SHA256: $writer_hash$" "$spdx_file"
rg -q "^PackageChecksum: SHA256: $deleter_hash$" "$spdx_file"
rg -q '^Relationship: SPDXRef-DOCUMENT DESCRIBES SPDXRef-ReaderArchive$' "$spdx_file"
rg -q '^Relationship: SPDXRef-DOCUMENT DESCRIBES SPDXRef-WriterArchive$' "$spdx_file"
rg -q '^Relationship: SPDXRef-DOCUMENT DESCRIBES SPDXRef-DeleterArchive$' "$spdx_file"
