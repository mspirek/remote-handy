# Remote Handy contributor instructions

Start with [_AGENTS/LEDGER.md](_AGENTS/LEDGER.md), [architecture](docs/ARCHITECTURE.md) and [verification](docs/VERIFICATION.md). One writer per mutable target; reviewers remain read-only unless assigned implementation. Record decisions and evidence before handoff.

- Handy history and settings are read-only. Never repair, migrate, vacuum, checkpoint or snapshot-copy its database or sidecars.
- Keep the implementation native Swift/AppKit. Use the existing build/install scripts.
- Match Handy's process for paste suppression. Never suppress physical input or unrelated apps.
- Keep remote focus guards and fail closed when suppression or clipboard delivery is unproven. Never add blind undo or cleanup.
- Preserve user configuration and stable signing identity during installation. Do not kill unrelated processes or change permissions.
- The local operator must authorize any app installation/startup change. Permission prompts require the operator's approval. Quit is intentional, not a crash.
- Verify original remote text, not merely a local clipboard match or a sent keystroke. Label synthetic, native and unrun tests separately.
- Public releases must exclude runtime settings, databases, transcripts, screenshots, private paths and private development history. Keep license and provenance notices intact.
- Run fixture tests, privacy scan, build and relevant native checks. Record untested targets honestly. Avoid committing build output or local signing identities.
