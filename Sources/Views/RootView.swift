import SwiftUI

struct RootView: View {
    @State private var model = DetectorViewModel()

    var body: some View {
        Group {
            if shouldShowOnboarding {
                MicPermissionView(model: model)
            } else {
                DetectorView(model: model)
            }
        }
        .onAppear {
            model.refreshPermission()
            if LaunchConfiguration.skipsMicPermission {
                model.refreshPermission()
            }
        }
    }

    private var shouldShowOnboarding: Bool {
        if LaunchConfiguration.skipsMicPermission || LaunchConfiguration.mockBPM != nil {
            return false
        }
        return model.permission != .granted
    }
}
