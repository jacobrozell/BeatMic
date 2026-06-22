import Foundation

enum LaunchConfiguration {
    static var resetsOnLaunch: Bool {
        ProcessInfo.processInfo.arguments.contains("-ui_test_reset")
    }

    static var mockBPM: Int? {
        guard let index = ProcessInfo.processInfo.arguments.firstIndex(of: "-ui_test_mock_bpm"),
              ProcessInfo.processInfo.arguments.indices.contains(index + 1) else { return nil }
        return Int(ProcessInfo.processInfo.arguments[index + 1])
    }

    static var skipsMicPermission: Bool {
        ProcessInfo.processInfo.arguments.contains("-ui_test_skip_mic_onboarding")
    }
}
