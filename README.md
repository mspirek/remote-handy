# Remote Handy

Use [Handy](https://github.com/cjpais/Handy) on your local Mac to dictate into another Mac through Apple Screen Sharing.

Remote Handy reads Handy's local history, prevents Handy's competing paste from inserting stale clipboard text, and hands the fresh transcript to Screen Sharing using a small local copy-donor app. It can paste automatically or leave the transcript ready for a manual Command-V.

**Source-build alpha.** Requires macOS 26 or later and Swift 6.2 or later. Tested locally on macOS 27 with Handy 0.9.8 and Apple Screen Sharing. No prebuilt or notarized download is provided. Remote Handy is independent of the Handy project.

## Install

Install this helper on the **local Mac running Handy**. Keep Handy history enabled and use hold-to-talk mode. The default shortcut is Fn; the optional Option+Shift+Space shortcut must match Handy's own post-processing binding.

With Xcode or compatible Command Line Tools installed:

```sh
git clone https://github.com/mspirek/remote-handy.git
cd remote-handy
make test-fixtures
make setup-local-signing
make install-local
```

`setup-local-signing` creates a local signing certificate in your login keychain. This keeps the app's identity stable across your own builds; it does not make the app Developer ID signed or notarized. You can instead set `REMOTE_HANDY_CODESIGN_IDENTITY` to an existing code-signing identity. The installer requires stable signing, closes an existing copy gracefully, and preserves settings.

Open `~/Applications/Remote Handy.app`, or choose **RH → Settings**. Enable the shortcut trigger and Auto paste when ready. New installations start with automatic actions off.

Grant the installed Remote Handy app Accessibility access in System Settings → Privacy & Security → Accessibility. Use **RH → Check Input Permissions** to request Automation access to System Events. The app needs both to control paste in Screen Sharing. It never grants or resets permissions itself.

## Launch automatically and recover

Choose **RH → Launch at Login & Recover After Failure**. Approve the background item in System Settings → General → Login Items if macOS requests it. For an explicitly unattended install after local signing:

```sh
REMOTE_HANDY_ENABLE_STARTUP=1 make install-local
```

The bundled `SMAppService` agent starts at login and relaunches after an unsuccessful exit. A deliberate **Quit** exits successfully and stays stopped until you reopen the app or log in again. Reopening transfers ownership back to the managed service. A single-instance lock prevents two copies from handling the same dictation. Sleep and session changes cancel pending work; wake rearms the shortcut listeners.

This does not launch Handy itself. Enable Handy's own launch-at-login option if desired. Startup recovery cannot repair revoked permissions, disabled history, a disconnected remote session, or an incompatible Handy update.

## Use

1. Connect Apple Screen Sharing and focus a disposable text field on the remote Mac for the first test.
2. Hold Fn, dictate, and release.
3. Wait for the sentence to appear before starting the next dictation.

Only dictations begun with Apple Screen Sharing frontmost are handled. Local dictation is left alone. If focus changes before the donor handoff, the helper skips the paste. The guard matches Handy-generated paste events, not physical keyboard input or other applications. If suppression cannot be verified, it stops without changing the helper clipboard or sending another paste.

**One dictation at a time.** Overlapping hotkeys while a handoff is running are skipped and show Busy. Other remote clients, fullscreen sessions, long dictations, and all hardware combinations are not yet verified. See [verification](docs/VERIFICATION.md).

## Troubleshooting

- Open the app again to reach Settings even if the menu-bar item is hidden.
- **Run Baseline Health Check** checks the history schema, settings, donor, signing and permissions.
- **Diagnostics** shows startup and recent operation metadata. It does not display transcript content.
- **Reset Running State** cancels an in-flight operation. It does not delete history or change permissions.
- Disable the helper using **RH → Disable Remote Handy**, or Option-click RH.
- If startup needs approval, open System Settings → General → Login Items. To stop starting at login, uncheck the startup menu item before quitting.

Settings: `~/Library/Application Support/RemoteHandy/settings.json`. Logs: `~/Library/Logs/RemoteHandy/menu-bar.log`, rotated at about 1 MiB with one previous file. Never post private settings, transcripts, or raw logs in an issue.

To uninstall, disable startup from the menu, quit, and move both Remote Handy applications from `~/Applications` to Trash. Your settings remain unless you remove the RemoteHandy support folder yourself.

## Development and license

Native Swift/AppKit, SQLite read-only access, no third-party Swift packages, no telemetry or hosted service. Run `make test-fixtures`, `make privacy-scan`, and `make build-menubar-app`. The GitHub workflow checks fixtures and an ad-hoc-signed build; actual Accessibility, microphone and remote paste acceptance require a Mac session.

See [architecture](docs/ARCHITECTURE.md), [contributing](CONTRIBUTING.md), [privacy](PRIVACY.md), [security](SECURITY.md), and [provenance](NOTICE.md). Distributed under the [MIT license](LICENSE).
