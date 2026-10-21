# Remote Handy ledger

As of October 21, 2026. Native local utility for Handy dictation into Apple Screen Sharing. Maintainer: Mark Spirek. Implementation/integration: Codex. Contributions are bounded; one writer per target.

- RH-001: Handy-only source, independent identity, MIT attribution, clean public history. Published at [mspirek/remote-handy](https://github.com/mspirek/remote-handy); GitHub visibility, MIT detection and initial remote commit verified. Clean export fixtures, privacy scan and both app builds pass locally.
- RH-002: launch-at-login and unsuccessful-exit recovery using SMAppService; successful Quit stays stopped. Installed registration, signed update recovery, crash restart, duplicate exclusion and Quit/manual reopening verified. Actual reboot/login and sleep/wake remain untested.
- RH-003: preserve the tested process-scoped paste guard and add duplicate/session/timing safeguards. Fixtures and public CI pass. Operator confirmed five sequential final-build Fn dictations and ordinary local dictation; matching operation logs inspected. Optional post-processing was not configured and remains unverified. See [verification](../docs/VERIFICATION.md).
- Decision: macOS 26+ and Swift 6.2+, with local validation on macOS 27. Compatibility below 26 is outside current scope. No hosted services or recurring infrastructure cost.
- Decision: no public binary until signing/notarization and clean-machine installation are separately verified. Source builds use a local certificate or contributor-provided identity.

Canonical technical records: [architecture](../docs/ARCHITECTURE.md), [verification](../docs/VERIFICATION.md). Keep these records current with changes; do not treat a source push as native acceptance.
