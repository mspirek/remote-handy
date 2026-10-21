#!/usr/bin/env zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
output_dir="${1:-$repo_root/.build/apps}"
app_name="Remote Handy"
bundle_id="com.remote-handy.MenuBar"
app_path="$output_dir/$app_name.app"
contents="$app_path/Contents"
macos="$contents/MacOS"
resources="$contents/Resources"
version="${REMOTE_HANDY_VERSION:-$(tr -d '[:space:]' < "$repo_root/VERSION")}"
build_number="${REMOTE_HANDY_BUILD_NUMBER:-$(date +%s)}"

mkdir -p "$macos" "$resources" "$contents/Library/LaunchAgents"
cp "$repo_root/app/com.remote-handy.agent.plist" "$contents/Library/LaunchAgents/"

cd "$repo_root"
CLANG_MODULE_CACHE_PATH="$repo_root/.module-cache" swift build --product remote-handy-menubar

cp "$repo_root/.build/debug/remote-handy-menubar" "$macos/$app_name"
chmod +x "$macos/$app_name"
cp "$repo_root/assets/RemoteHandy.icns" "$resources/RemoteHandy.icns"

plist="$contents/Info.plist"
{
  print '<?xml version="1.0" encoding="UTF-8"?>'
  print '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
  print '<plist version="1.0">'
  print '<dict>'
  print '  <key>CFBundleDevelopmentRegion</key>'
  print '  <string>en</string>'
  print '  <key>CFBundleExecutable</key>'
  print "  <string>$app_name</string>"
  print '  <key>CFBundleIdentifier</key>'
  print "  <string>$bundle_id</string>"
  print '  <key>CFBundleName</key>'
  print "  <string>$app_name</string>"
  print '  <key>CFBundleDisplayName</key>'
  print "  <string>$app_name</string>"
  print '  <key>CFBundleIconFile</key>'
  print '  <string>RemoteHandy</string>'
  print '  <key>CFBundleIconName</key>'
  print '  <string>RemoteHandy</string>'
  print '  <key>CFBundlePackageType</key>'
  print '  <string>APPL</string>'
  print '  <key>CFBundleShortVersionString</key>'
  print "  <string>$version</string>"
  print '  <key>CFBundleVersion</key>'
  print "  <string>$build_number</string>"
  print '  <key>LSMinimumSystemVersion</key>'
  print '  <string>26.0</string>'
  print '  <key>LSUIElement</key>'
  print '  <true/>'
  print '  <key>NSAppleEventsUsageDescription</key>'
  print '  <string>Remote Handy needs permission to ask System Events to send Command-V to Apple Screen Sharing for auto-paste.</string>'
  print '</dict>'
  print '</plist>'
} >"$plist"

"$repo_root/scripts/sign-app.zsh" "$app_path" "$bundle_id" >/dev/null

echo "$app_path"
