# Contributing

See [`README.md`](README.md) for setup. Run `xcodegen generate` after editing `project.yml`.

## Layout

- `Sources/Domain/` — pure tempo analysis (`BPMAnalyzer`)
- `Sources/Data/` — microphone capture
- `Sources/Features/` — SwiftUI flows (detector, onboarding, settings)
- `Sources/DesignSystem/` — shared UI components
- `Sources/Support/` — launch configuration, links, accessibility IDs
- `Tests/` — Swift Testing unit tests
- `BeatMicUITests/` — UI smoke tests (mock BPM launch args)

## Style

- 4-space indent, `private` by default
- Domain code must not import SwiftUI
- SwiftLint via `.swiftlint.yml` (CI enforces)
- **Never** commit or bundle personal audio (`*.mp3`, etc.); use `local-test-media/` or gitignored album folders for QA

## UI test launch args

- `-ui_test_skip_mic_onboarding` — opens detector without permission sheet
- `-ui_test_mock_bpm 120` — simulates a stable 120 BPM reading
