# Security

Do not post transcripts, tokens, local configuration or unsanitized diagnostic exports in public issues. Use the repository's private vulnerability reporting if enabled; otherwise contact the maintainer privately through GitHub.

The app reads Handy's history with SQLite read-only access. It uses existing Accessibility permission to suppress only Handy-generated paste events during an operation begun in Apple Screen Sharing, then requires verified suppression before copying. Physical keys and events from unrelated processes pass through. Focus is checked before donor copy and paste.

The app uses no network APIs, bundled third-party dependencies, privileged daemon, administrator access or automatic permission grants. Its optional per-user SMAppService agent starts at login and after unsuccessful exits. Deliberate Quit is respected. Local builds require a stable signing identity for reliable macOS permission retention; they are not notarized releases.

Please report changes to Handy's history schema or paste-event attribution, unexpected suppression, clipboard contents, focus, or startup behavior with sanitized reproduction steps and version information.
