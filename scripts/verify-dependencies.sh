#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
dependencies="$(sh "$script_dir/run-swiftpm-external.sh" package show-dependencies --format json)"
printf '%s\n' "$dependencies" | rg -U -q '"dependencies"[[:space:]]*:[[:space:]]*\[[[:space:]]*\]'
sh "$script_dir/run-swiftpm-external.sh" package describe >/dev/null
