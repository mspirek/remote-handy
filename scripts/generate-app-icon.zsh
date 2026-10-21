#!/usr/bin/env zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
output_path="${1:?usage: generate-app-icon.zsh OUTPUT_ICNS}"
output_dir="$(dirname "$output_path")"
iconset_dir="$(mktemp -d "${TMPDIR:-/tmp}/remote-handy-icon.XXXXXX")/RemoteHandy.iconset"

mkdir -p "$output_dir" "$iconset_dir"

CLANG_MODULE_CACHE_PATH="$repo_root/.module-cache" swift "$repo_root/scripts/render-app-icon.swift" "$iconset_dir"
iconutil -c icns "$iconset_dir" -o "$output_path"

print "$output_path"
