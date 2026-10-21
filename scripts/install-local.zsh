#!/usr/bin/env zsh
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
install_dir="${REMOTE_HANDY_INSTALL_DIR:-$HOME/Applications}"
export REMOTE_HANDY_REQUIRE_STABLE_SIGNING="${REMOTE_HANDY_REQUIRE_STABLE_SIGNING:-1}"
identity="${REMOTE_HANDY_CODESIGN_IDENTITY:-Remote Handy Local Code Signing}"
menu_app="$install_dir/Remote Handy.app"
if [[ "$REMOTE_HANDY_REQUIRE_STABLE_SIGNING" == "1" && "$identity" != "-" ]]; then
  if ! security find-identity -v -p codesigning | awk -v name="$identity" 'index($0, "\"" name "\"") { found=1 } END { exit !found }'; then
    print -u2 "Run make setup-local-signing first, or set REMOTE_HANDY_CODESIGN_IDENTITY to an existing signing identity."
    exit 1
  fi
fi
"$repo_root/scripts/build-copy-donor-app.zsh"
"$repo_root/scripts/build-menubar-app.zsh"

# Unregister the old service before replacing a signed bundle that launchd owns.
service="gui/$(id -u)/com.remote-handy.agent"
was_managed=0
if launchctl print "$service" >/dev/null 2>&1; then
  was_managed=1
  open -n -g "$menu_app" --args --startup-disable
  for attempt in {1..100}; do
    if ! launchctl print "$service" >/dev/null 2>&1; then break; fi
    sleep 0.1
  done
  if launchctl print "$service" >/dev/null 2>&1; then
    print -u2 'Startup service did not unregister; installation stopped.'
    exit 1
  fi
fi
if pgrep -x 'Remote Handy' >/dev/null; then
  osascript -e 'tell application id "com.remote-handy.MenuBar" to quit'
  for attempt in {1..80}; do
    if ! pgrep -x 'Remote Handy' >/dev/null; then break; fi
    sleep 0.1
  done
  if pgrep -x 'Remote Handy' >/dev/null; then
    print -u2 'Remote Handy is still running; installation stopped.'
    exit 1
  fi
fi
if pgrep -x 'Remote Handy Copy Donor' >/dev/null; then
  print -u2 'A copy is active. Wait for it to finish before installing.'
  exit 1
fi
mkdir -p "$install_dir"
for name in 'Remote Handy' 'Remote Handy Copy Donor'; do
  target="$install_dir/$name.app"
  staging="$install_dir/.$name.installing.app"
  if [[ -e "$staging" ]]; then
    print -u2 "Staging path already exists: $staging"
    exit 1
  fi
  ditto "$repo_root/.build/apps/$name.app" "$staging"
  codesign --verify --deep --strict "$staging"
  if [[ -e "$target" ]]; then
    if [[ ! -d "$target/Contents" ]]; then print -u2 "Target is not an app directory: $target"; exit 1; fi
    backup="$install_dir/.$name.previous-$$"
    if [[ -e "$backup" ]]; then print -u2 "Backup already exists: $backup"; exit 1; fi
    # Preserve the root bundle inode: SMAppService bookmarks the registered app.
    mv "$target/Contents" "$backup"
    if mv "$staging/Contents" "$target/Contents"; then
      rmdir "$staging"
      rm -rf "$backup"
      touch "$target"
    else
      mv "$backup" "$target/Contents"
      exit 1
    fi
  else
    mv "$staging" "$target"
  fi
done
# Refresh Launch Services metadata before asking SMAppService to register the app.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$menu_app"
print "Installed: $menu_app"
# Preserve an existing startup registration. New installations opt in explicitly.
if [[ "${REMOTE_HANDY_ENABLE_STARTUP:-$was_managed}" == "1" ]]; then
  status_file="$HOME/Library/Application Support/RemoteHandy/startup-status.txt"
  rm -f "$status_file"
  open -n -g "$menu_app" --args --startup-enable
  for attempt in {1..100}; do
    if [[ -f "$status_file" ]]; then break; fi
    sleep 0.1
  done
  if [[ ! -f "$status_file" ]]; then
    print -u2 'Startup registration did not report a result. Open the app to inspect startup status.'
    exit 1
  fi
  cat "$status_file"
  print ''
  if [[ "$(<"$status_file")" == Error:* ]]; then exit 1; fi
  if [[ "$(<"$status_file")" == Enabled:* ]]; then
    for attempt in {1..100}; do
      if launchctl print "$service" 2>/dev/null | /usr/bin/grep -q 'state = running'; then break; fi
      sleep 0.1
    done
    if ! launchctl print "$service" 2>/dev/null | /usr/bin/grep -q 'state = running'; then
      # A locally signed rebuild can leave a stale launch constraint in macOS's
      # registration cache. Refresh only our service through SMAppService once.
      print 'Refreshing startup registration for the updated signed bundle.'
      rm -f "$status_file"
      open -n -g "$menu_app" --args --startup-disable
      for attempt in {1..100}; do
        if [[ -f "$status_file" ]] && ! launchctl print "$service" >/dev/null 2>&1; then break; fi
        sleep 0.1
      done
      if [[ ! -f "$status_file" ]] || [[ "$(<"$status_file")" != Disabled ]] || launchctl print "$service" >/dev/null 2>&1; then
        print -u2 'Startup refresh could not unregister the service. Open the app to inspect startup status.'
        exit 1
      fi
      rm -f "$status_file"
      open -n -g "$menu_app" --args --startup-enable
      for attempt in {1..100}; do
        if [[ -f "$status_file" ]] && launchctl print "$service" 2>/dev/null | /usr/bin/grep -q 'state = running'; then break; fi
        sleep 0.1
      done
      if [[ ! -f "$status_file" ]] || ! launchctl print "$service" 2>/dev/null | /usr/bin/grep -q 'state = running'; then
        print -u2 'Startup is registered but the managed process did not start after one refresh. Inspect launchctl and startup status.'
        exit 1
      fi
    fi
  fi
else
  open -g "$menu_app" --args --settings
fi
