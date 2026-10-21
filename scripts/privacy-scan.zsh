#!/usr/bin/env zsh
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"
# Scan tracked public source, or source folders before the initial commit.
if rg -n --hidden -e '/Users/[^/[:space:]]+/' -e 'BEGIN .*PRIVATE KEY' -e 'gh[pousr]_[A-Za-z0-9]{20}' -e 'github_pat_[A-Za-z0-9_]{20}' -e 'sk-[A-Za-z0-9]{24}' . \
  --glob '!.git/**' --glob '!.build/**' --glob '!.module-cache/**' --glob '!.swiftpm/**' \
  --glob '!scripts/privacy-scan.zsh' --glob '!*.png' --glob '!*.icns'; then
  print -u2 'Potential private content found. Review before publishing.'
  exit 1
fi
if rg -ni 'wispr|whisperflow' Sources scripts Package.swift README.md .github --glob '!privacy-scan.zsh'; then
  print -u2 'Unexpected old integration reference outside attribution.'
  exit 1
fi
print 'Public source scan passed (manual review still required).'
