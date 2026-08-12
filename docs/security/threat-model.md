# TouchPoint threat model

Protected assets are screen contents, recordings, Accessibility and Screen Recording
permissions, global input state, cursor visibility, signing credentials, and local files.
Window metadata, display geometry, Simulator state, hotkeys, and capture permissions are
untrusted or change asynchronously.

Required controls:

- Capture only the explicitly selected Simulator and overlay surfaces; require deliberate
  user action before recording, saving, or sharing output.
- Restore cursor visibility and global input state on stop, error, permission denial, app
  termination, and overlay recreation.
- Re-resolve ScreenCaptureKit windows after identity changes and validate screen/scale/crop
  transforms before recording.
- Keep signing/notarization credentials, recording paths, and private screen content out of
  logs, fixtures, errors, and source control.
- Isolate private CGS declarations and use them only for hide/show, never cursor replacement.

Update this model when capture scope, permissions, cursor APIs, storage, sharing, hotkeys,
or release signing changes.
