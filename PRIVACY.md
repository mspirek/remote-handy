# Privacy

Remote Handy runs locally and makes no network requests. It has no analytics, account, updater, telemetry or crash-upload service.

It reads Handy's configured SQLite history with SQLITE_OPEN_READONLY. It does not modify Handy's history, settings or sidecars. It reads only the rows needed for the triggered operation.

During a remote operation it observes keyboard event metadata to identify Handy's synthetic paste. It does not record typed text. It writes the selected transcript to the local clipboard and sends it through Apple Screen Sharing to the connected remote Mac. Screen Sharing's clipboard behavior and remote access are controlled by macOS and your session configuration.

The donor briefly uses a private temporary directory containing the selected transcript. The request directory is removed on success and error when the helper remains alive; an abrupt process crash can leave a temporary directory until macOS cleans it. Settings and operational metadata stay in the user's RemoteHandy support/log folders. Logs omit transcript content and are bounded to the current file plus one previous file. Diagnostic exports may still reveal local paths and application names; review before sharing.

Accessibility enables the narrow paste guard and keyboard automation. Automation permits System Events to send the replacement paste. The background item provides login launch and failure recovery; it can be disabled from the app menu or macOS Login Items settings. Permissions are never granted automatically.
