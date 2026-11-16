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
                // The screen stays on only while streaming (MainView): waiting for the computer,
                // the iPhone locks with its own settings, like any other app.
                UIApplication.shared.isIdleTimerDisabled = false
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
