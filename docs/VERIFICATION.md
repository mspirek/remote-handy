# Verification

October 21, 2026. Source-build alpha 0.1.0. Native testing: macOS 27.0.1, Handy 0.9.8, Apple Screen Sharing 7.0. macOS 26 is the minimum deployment target; CI fixtures and builds pass there, while native UI/remote-paste behavior on 26 remains unverified.

## Automated checks

Fixture coverage includes read-only Handy database access, processed/raw fallback, Unicode, blank/pruned rows, missing/incompatible databases, temporary writer locks, stabilization, cancellation, settings roundtrip and invalid timing normalization, single-instance ownership, clipboard formatting, and process-scoped paired paste suppression. Fixtures, privacy scan and both native app builds also pass from a clean export of the published source. Installer shell syntax and launch-agent plist validation pass.

Public [GitHub Actions run 39619646651](https://github.com/mspirek/remote-handy/actions/runs/39619646651) passed fixtures, the source scan and both app builds on macOS 26 at commit `6c6851782ecd1bb530430f3c1f715fb4d390fa1d`. Later acceptance-record edits do not change that tested runtime source.

## Native evidence

The prior Handy-adapter build successfully inserted individual dictated sentences into remote TextEdit. An unguarded trial repeated stale clipboard text; the process-scoped guard eliminated that repetition, with actual suppression and remote content checked together. This proves the mechanism on the test setup, not every configuration.

The renamed app's Settings layout was inspected. Its SMAppService registration returned enabled and launchd reported the bundled main app running with managed arguments. A controlled SIGKILL produced a new managed process. A duplicate launch left exactly one instance. Deliberate Quit exited with status zero and remained stopped beyond the recovery throttle; reopening restored a single managed process. The installed app's own permission check confirmed Accessibility and System Events access after the final signed update. Strict signature verification passed for both installed bundles.

An in-place signed update initially hit a stale macOS launch constraint. The installer now preserves the bundle root and performs one bounded refresh through SMAppService if the first launch fails. Reinstallation exercised that recovery successfully. Read-only source review accepted the donor cancellation/focus guards and installer with no remaining blocking findings.

The operator confirmed five sequential Fn dictations through Screen Sharing and an ordinary local dictation worked on the final installed build. Operational logs independently show five handoffs, each with one suppressed Handy paste, a matching clipboard, and one replacement paste. Local dictations were skipped by the remote-only guard. Optional post-processing was not configured in Handy, so it was not accepted as a test; the unused helper shortcut was disabled locally and the managed app reopened with Fn enabled.

## Limits

A real post-processing dictation, full-screen remote sessions, reboot/login persistence, sleep/wake on real hardware, long dictations and other remote clients are unverified. Overlapping dictations are unsupported; wait for each paste before starting the next. Local clipboard matches and sent-key logs alone do not prove remote insertion.

CI and synthetic checks do not exercise microphone input, permission prompts, login approval, shared clipboard timing or the remote application. Record those as separate acceptance evidence.
