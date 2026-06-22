# BeatMic

A minimal iOS app that listens through the microphone, estimates the tempo of nearby music, and shows how trustworthy the analysis is via a confidence meter.

## Build & run

Requires **Xcode 16+** and **iOS 18+**. The Xcode project is generated from `project.yml` via [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen   # once
xcodegen generate
open BeatMic.xcodeproj
```

Select an iPhone simulator (or device) and press **⌘R**. Signing uses team `7JT2JB89AV` with bundle id `com.jacobrozell.beatmic`.

## Tests

Sync metronome fixtures once (or let CI/`verify-local.sh` do it), then run tests:

```bash
bash Scripts/sync-metronome-fixtures.sh
xcodegen generate
bash Scripts/ci/verify-local.sh
```

Unit tests analyze bundled metronome WAVs; UI smoke tests use `-ui_test_mock_bpm 120` because the simulator mic is unreliable. In-app: **Settings → Run metronome verification**.

## Docs

| Topic | Location |
|-------|----------|
| Agent build phases | [`docs/agent-build-checklist.md`](docs/agent-build-checklist.md) |
| What ships today | [`docs/feature-inventory.md`](docs/feature-inventory.md) |
| Product specs | [`specs/README.md`](specs/README.md) |

## Defaults (v1)

- **Name:** BeatMic · **Bundle:** `com.jacobrozell.beatmic`
- **Min iOS:** 18.0 · **Locale:** English · **Orientation:** portrait
- **Telemetry:** off · **Tip jar:** none
