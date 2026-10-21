#!/usr/bin/env zsh
set -euo pipefail
if [[ $# != 1 || -e "$1" ]]; then
  print -u2 'usage: scripts/export-public-source.zsh NEW_EXPORT_DIRECTORY'
  exit 2
fi
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$1"
# Only a reviewed commit is exportable; untracked runtime files never enter the export.
git -C "$repo_root" archive HEAD | tar -x -C "$1"
