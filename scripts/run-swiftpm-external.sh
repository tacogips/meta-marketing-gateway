#!/bin/sh
set -eu

# SwiftPM build products and caches must never be created in this repository's
# .build directory during offline verification. The caller provides an ordinary
# Swift subcommand, for example: `test --parallel` or `package describe`.
test "$#" -gt 0
scratch_root="$(mktemp -d)"
trap 'rm -rf "$scratch_root"' EXIT

command="$1"
shift
if [ "$command" = "package" ]; then
  swift package --scratch-path "$scratch_root" "$@"
else
  swift "$command" --scratch-path "$scratch_root" "$@"
fi
