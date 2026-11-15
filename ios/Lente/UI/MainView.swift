import AVFoundation
import SwiftUI

/// Camera permission state. Phase 0 only asks for it; capture starts in Phase 1.
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
    @EnvironmentObject private var probe: ProbeServer
    @EnvironmentObject private var camera: CameraPermission

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
                Text("Prueba de la Fase 0 · puerto 27183")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.white)
            .padding(32)
        }
        .onAppear {
            probe.start()
            if camera.status == .notDetermined { camera.request() }
        }
    }

    private var statusText: String {
        switch probe.state {
        case .stopped: return "Detenido"
        case .waiting: return "Esperando la computadora"
        case .connected: return "Conectado · \(probe.bytesSent) bytes enviados"
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
