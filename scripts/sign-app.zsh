#!/usr/bin/env zsh
set -euo pipefail

if [[ "$#" -ne 2 ]]; then
  print -u2 "usage: scripts/sign-app.zsh APP_PATH BUNDLE_ID"
  exit 64
fi

app_path="$1"
bundle_id="$2"
identity_name="${REMOTE_HANDY_CODESIGN_IDENTITY:-Remote Handy Local Code Signing}"
require_stable_signing="${REMOTE_HANDY_REQUIRE_STABLE_SIGNING:-0}"

if [[ ! -d "$app_path" ]]; then
  print -u2 "error: app bundle not found: $app_path"
  exit 1
fi

find_identity_hash() {
  local name="$1"
  /usr/bin/security find-identity -v -p codesigning 2>/dev/null \
    | /usr/bin/awk -v name="$name" 'index($0, "\"" name "\"") > 0 { print $2; exit }'
}

sign_identity=""
if [[ "$identity_name" != "-" ]]; then
  sign_identity="$(find_identity_hash "$identity_name")"
fi

if [[ -n "$sign_identity" ]]; then
  /usr/bin/codesign --force --deep --sign "$sign_identity" --identifier "$bundle_id" "$app_path"
  print "Signed $app_path with identity: $identity_name"
else
  if [[ "$require_stable_signing" == "1" && "$identity_name" != "-" ]]; then
    print -u2 "error: stable code signing identity not found: $identity_name"
    print -u2 "Run 'make setup-local-signing' once, then run 'make install-local' again."
    print -u2 "Refusing to install an ad-hoc-signed app because macOS Accessibility may reject it after rebuilds."
    exit 1
  fi

  /usr/bin/codesign --force --deep --sign - --identifier "$bundle_id" "$app_path"
  print -u2 "warning: stable code signing identity not found: $identity_name"
  print -u2 "warning: using ad-hoc signing; macOS Accessibility may need re-approval after rebuilds."
  print -u2 "warning: run 'make setup-local-signing' once, then reinstall."
fi

/usr/bin/codesign --verify --deep --strict "$app_path"
