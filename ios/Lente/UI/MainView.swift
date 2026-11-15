import AVFoundation
import SwiftUI
import UIKit

/// Camera permission state.
final class CameraPermission: ObservableObject {
    @Published private(set) var status = AVCaptureDevice.authorizationStatus(for: .video)

    func refresh() {
        status = AVCaptureDevice.authorizationStatus(for: .video)
    }

    func request() {
        AVCaptureDevice.requestAccess(for: .video) { _ in
            DispatchQueue.main.async { self.refresh() }
        }
    }
}

struct MainView: View {
    @EnvironmentObject private var server: StreamServer
    @EnvironmentObject private var camera: CameraPermission
    @State private var savedBrightness: CGFloat = 0.5

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 24) {
                Text("Hola, soy Lente")
                    .font(.largeTitle.bold())
                Text(statusText)
                    .font(.title3)
                    .multilineTextAlignment(.center)
                Text(cameraText)
                    .font(.body)
                    .foregroundStyle(.secondary)
                if camera.status == .notDetermined {
                    Button("Permitir la cámara") { camera.request() }
                        .buttonStyle(.borderedProminent)
                }
                if case .streaming = server.state {
                    Button("Pantalla negra") { server.blackout = true }
                        .buttonStyle(.bordered)
                }
                Text("Conectá el cable y abrí Lente en la computadora")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.white)
            .padding(32)

            if server.blackout {
                // Black screen with the minimum brightness: less heat and battery.
                // Double tap (or MOD+Shift+o on the PC) brings the screen back.
                Color.black
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { server.blackout = false }
            }
        }
        .statusBarHidden(true)
        .onChange(of: server.blackout) { on in
            if on {
                savedBrightness = UIScreen.main.brightness
                UIScreen.main.brightness = 0
            } else {
                UIScreen.main.brightness = savedBrightness
            }
        }
        .onAppear {
            server.start()
            if camera.status == .notDetermined { camera.request() }
        }
    }

    private var statusText: String {
        switch server.state {
        case .stopped: return "Detenido"
        case .waiting: return "Esperando la computadora"
        case .configuring: return "Preparando la cámara"
        case .streaming(let detail): return "Transmitiendo\n\(detail)\n\(server.framesSent) cuadros"
        case .interrupted: return "Cámara interrumpida\nVuelve sola al terminar la llamada o al cerrar el Centro de control"
        case .failed(let detail): return "Error: \(detail)"
        }
    }

    private var cameraText: String {
        switch camera.status {
        case .authorized: return "Permiso de cámara: concedido"
        case .denied, .restricted: return "Permiso de cámara: denegado (Ajustes › Lente)"
        case .notDetermined: return "Permiso de cámara: sin pedir"
        @unknown default: return "Permiso de cámara: desconocido"
        }
    }
}
