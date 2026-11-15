import SwiftUI

@main
struct LenteApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var server = StreamServer()
    @StateObject private var camera = CameraPermission()

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(server)
                .environmentObject(camera)
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active:
                UIApplication.shared.isIdleTimerDisabled = true
                camera.refresh()
                server.start()
            case .background:
                // iOS does not allow the camera in the background: release everything.
                server.stop()
                UIApplication.shared.isIdleTimerDisabled = false
            default:
                break
            }
        }
    }
}
