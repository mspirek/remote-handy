# Architecture

Remote Handy consists of a small AppKit menu-bar app, a temporary copy-donor app, and a pure Swift core with SQLite fixtures.

The hotkey handler captures the maximum Handy history ID at key-down, only with Apple Screen Sharing frontmost. It arms a session event tap scoped to Handy's PID. On release, the watcher reads the oldest nonblank later row, preferring completed post-processed text to raw transcription. It stabilizes the candidate for one second, retrying temporary SQLite locks within the deadline.

The paste guard must observe the entire synthetic Command-V/modifier sequence. It then removes the tap before the asynchronous donor handoff and bounded System Events operation. The helper verifies focus, copies through the donor, checks the clipboard, returns focus, and optionally pastes. Cancellation invalidates the donor request; the donor rechecks request validity and focus before copying. Failure to observe suppression sends no replacement copy/paste. The workflow is single-operation; overlapping hotkeys are rejected as Busy.

SMAppService registers the bundled agent. launchd owns the main app process and restarts it after unsuccessful exits, with a ten-second throttle. Successful Quit is intentional. Manual reopening starts the registered service; a kernel advisory lock excludes simultaneous owners and is released after crashes. Session suspension cancels pending work and stops observers; session resumption rearms the hotkey observers without replaying an old transcript.

Settings preserve user choices and normalize timing ranges. Invalid JSON leaves automation disabled until repaired. Logs rotate at roughly 1 MiB; transcripts are absent from logs. Donor request files are transient and deleted after the operation. Both successful and failed operations release state for the next trigger.

The mechanism depends on Handy's private history schema and synthetic event source attribution. An incompatible version fails visibly. It does not change Handy configuration, install audio input on the remote Mac, or guarantee arbitrary remote clients.

Primary platform references: [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice), [agent registration](https://developer.apple.com/documentation/servicemanagement/smappservice/agent(plistname:)), and the installed `launchd.plist(5)` manual for BundleProgram and SuccessfulExit. Handy source reference: [v0.9.8 actions](https://github.com/cjpais/Handy/blob/v0.9.8/src-tauri/src/actions.rs).
