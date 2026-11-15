import SwiftUI

@main
struct LenteApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var probe = ProbeServer()
    @StateObject private var camera = CameraPermission()

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(probe)
                .environmentObject(camera)
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active:
                UIApplication.shared.isIdleTimerDisabled = true
                camera.refresh()
                probe.start()
            case .background:
                // iOS does not allow the camera in the background: release everything.
                probe.stop()
                UIApplication.shared.isIdleTimerDisabled = false
            default:
                break
            }
        }
    }
}
