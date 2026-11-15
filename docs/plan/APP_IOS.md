# Lente · App del iPhone (servidor iOS)

## 1 · Principios

* **Mínima:** sin dependencias de terceros, sin recursos gráficos salvo el ícono. Meta: IPA de menos de 2 MB.
* **Un solo trabajo:** cámara → codificador → socket. Nada más corre mientras transmite.
* **Latencia antes que todo:** cada decisión de configuración se toma pensando en el delay; si algo mejora la imagen pero suma delay, va como opción, nunca por defecto.
* **La PC manda:** los parámetros llegan en la apertura de sesión. La app casi no tiene ajustes propios.
* **Falla en voz alta:** cualquier parámetro o estado imposible se responde con un estado de error claro, nunca con un comportamiento silencioso.

## 2 · Datos del proyecto

| Campo | Valor |
|---|---|
| Plataforma | iPhone, iOS 16.0 o superior (ajustar con D4) |
| Lenguaje | Swift 5.9 o superior, SwiftUI para la interfaz |
| Proyecto | Generado con XcodeGen desde `ios/project.yml` (no se versiona el `.xcodeproj`) |
| Bundle ID | `digital.velinex.lente` (provisional, cambia con el nombre definitivo, D3) |
| Permisos | Solo cámara. `NSCameraUsageDescription`: «Lente usa la cámara para mandar el video a tu computadora por el cable.» |
| Orientación de la interfaz | Vertical fija. La orientación del video la decide la PC y es independiente |
| Otras claves de Info.plist | `UIRequiresFullScreen` = YES, `UIStatusBarHidden` = YES, `UIApplicationSceneManifest` mínimo |
| Modos en segundo plano | Ninguno (iOS no permite cámara en segundo plano) |

## 3 · Estructura de archivos

```
ios/
  project.yml                  XcodeGen (plantilla en docs/plan/plantillas/project.yml)
  Lente/
    App/LenteApp.swift         Entrada, ciclo de vida (scenePhase), pantalla siempre encendida
    Core/Session.swift         Máquina de estados de la sesión y unión de las piezas
    Core/CameraController.swift  Sesión de captura, lentes, formatos, controles
    Core/Encoder.swift         VTCompressionSession
    Core/AnnexB.swift          AVCC a Annex B y conjuntos de parámetros
    Core/Telemetry.swift       Estado térmico, batería, contadores
    Net/Server.swift           Escucha en 127.0.0.1:27183, conexiones de video y control
    Net/Protocol.swift         LNTE, encabezado de 12 bytes, mensajes de control y del dispositivo
    UI/MainView.swift          Estado y botones
    UI/BlackoutView.swift      Pantalla en negro
    Resources/Assets.xcassets  Solo el ícono
  LenteTests/
    AnnexBTests.swift
    ProtocolTests.swift
    FormatSelectionTests.swift
```

## 4 · Máquina de estados de la sesión

`esperando` → (conexión de video con LNTE válido) → `configurando` → (cámara y codificador listos, OK enviado) → `transmitiendo` → (corte, error o cierre) → `esperando`.

Estados laterales: `interrumpida` (llamada, Centro de Control, otra app usa la cámara) vuelve sola a `transmitiendo` al terminar la interrupción; `sin_permiso` muestra cómo habilitar la cámara en Ajustes.

Al pasar la app a segundo plano: se cierra la sesión limpia y se libera la cámara. Al volver: `esperando`, y el cliente reconecta solo.

## 5 · Cámara (`CameraController`)

* **Dispositivos físicos, nunca virtuales:** `.builtInUltraWideCamera` (id 0), `.builtInWideAngleCamera` trasera (id 1, por defecto), `.builtInTelephotoCamera` (id 2), `.builtInWideAngleCamera` frontal (id 3). Así no hay cambio automático de lente en medio de una grabación.
* `camera_facing=back|front` elige el gran angular de ese lado si no hay `camera_id`.
* **Listado:** con `list_cameras=true` la app responde estado 0 con la lista en el mensaje (id, nombre, resoluciones y cuadros soportados) y cierra. El cliente lo imprime igual que `scrcpy --list-cameras`.
* **Formato:** `sessionPreset = .inputPriority`; se recorre `device.formats` y se elige el formato `420v` cuyas dimensiones coinciden con `camera_size` y cuyo rango de cuadros incluye `camera_fps`. Entre varios, el de menor resolución de sensor que cumpla (menos consumo). Si no hay ninguno: estado 2 con las combinaciones válidas en el mensaje.
* **Cuadros fijos:** `activeVideoMinFrameDuration` y `activeVideoMaxFrameDuration` = 1/fps.
* **Rango dinámico:** HDR apagado (`automaticallyAdjustsVideoHDREnabled = false`, `isVideoHDREnabled = false`), espacio de color sRGB/BT.709. Nada de HLG ni Apple Log en v1.
* **Estabilización:** apagada por defecto (`preferredVideoStabilizationMode = .off`), porque suma cuadros de delay. `lente_stabilization=standard` la activa.
* **Salida:** `AVCaptureVideoDataOutput` con `alwaysDiscardsLateVideoFrames = true`, formato `420v`, cola serial propia de QoS `userInteractive`.
* **Orientación:** `capture_orientation` de scrcpy (verificar los valores en el tag). Por defecto horizontal (1920x1080). En iOS 17 o superior con `videoRotationAngle`; en iOS 16 con `videoOrientation`.
* **Espejo de la frontal:** apagado por defecto, como scrcpy.
* **Controles:** linterna (`torchMode` y nivel), zoom (`videoZoomFactor` con rampa corta, límites del dispositivo), bloqueo de exposición (`.locked`), foco (`.locked`) y balance de blancos (`.locked`), cambio de lente reconfigurando la entrada sin cerrar la sesión de red.
* **Interrupciones:** observar `wasInterrupted`, `interruptionEnded` y `runtimeError`; reiniciar la sesión de captura sola y avisar con `LENTE_EVENT`.

## 6 · Codificador (`Encoder`)

* `VTCompressionSessionCreate` con especificación de baja latencia (`kVTVideoEncoderSpecification_EnableLowLatencyRateControl = true` en H.264; verificar disponibilidad para HEVC en iOS 16 y 17 y documentar lo encontrado).
* Propiedades:

| Propiedad | Valor |
|---|---|
| `RealTime` | true |
| `AllowFrameReordering` | false (sin cuadros B) |
| `ProfileLevel` | H.264 High AutoLevel · HEVC Main AutoLevel |
| `AverageBitRate` | `video_bit_rate` (por defecto 16 Mbps en 1080p60; 4K60 HEVC a definir en la Fase 5, punto de partida 40 Mbps) |
| `DataRateLimits` | 1,5 veces el promedio por segundo |
| `ExpectedFrameRate` | `camera_fps` |
| `MaxKeyFrameIntervalDuration` | `lente_keyframe_interval`, por defecto 2 s |
| `H264EntropyMode` | CABAC |
| Color | Primarios, transferencia y matriz ITU-R BT.709; rango de video |
| `MaximizePowerEfficiency` | false por defecto; medir en la Fase 5 si true no suma delay |

* Cuadro clave a pedido con `kVTEncodeFrameOptionKey_ForceKeyFrame` (reset de video, nueva sesión, cambio de lente).
* Callback: detectar cuadro clave (`kCMSampleAttachmentKey_NotSync` ausente), sacar conjuntos de parámetros del `CMFormatDescription` cuando cambian y mandar paquete de configuración, convertir longitudes de 4 bytes a códigos de inicio.
* Presión de salida: si hay más de 2 cuadros sin enviar en el socket, descartar los no clave hasta el próximo clave y contar en la telemetría. Nunca acumular.

## 7 · Red (`Server` y `Protocol`)

* Network.framework: `NWListener` con `requiredLocalEndpoint = 127.0.0.1:27183`, TCP con `noDelay = true`. Alternativa aceptada si se mide mejor: sockets BSD en un hilo propio.
* Primera conexión con `LNTE` = video; conexión con `LNTC` + sesión = control. Cualquier otra cosa se cierra.
* Escritura del video con control de bytes en vuelo (la presión de salida de la sección 6 se apoya en las confirmaciones de envío).
* Telemetría por la conexión de control cada 2 segundos.
* Modo `raw_stream=true`: sin LNTE ni encabezados, solo Annex B (diagnóstico de la Fase 1).

## 8 · Interfaz

Una pantalla, oscura, con:

* Estado grande: «Esperando la computadora» · «Transmitiendo · 1080p60 · H.264 · 16 Mbps» · «Cámara interrumpida» · «Falta el permiso de cámara».
* Botón «Pantalla negra» (también desde la PC con Alt+O). En negro: brillo al mínimo; doble toque vuelve y restaura el brillo anterior.
* Interruptor «Vista previa», apagado por defecto (la vista previa gasta GPU y batería).
* Texto de ayuda de una línea: «Conectá el cable y abrí Lente en la computadora».
* `isIdleTimerDisabled = true` mientras la app está en primer plano y hay sesión o espera de sesión.

Idioma: español e inglés según el idioma del sistema (`Localizable.strings`).

## 9 · Registro

`os.Logger` con categorías `camera`, `encoder`, `net`, `session`. Nada de impresiones en el camino de cada cuadro. Un resumen por sesión: duración, cuadros, descartes, estado térmico máximo.

## 10 · Pruebas (CI en el simulador)

* `AnnexBTests`: conversión con muestras fijas de H.264 y HEVC, conjuntos de parámetros.
* `ProtocolTests`: armado de LNTE y de la respuesta, encabezado de 12 bytes (bits de configuración y clave), parser de control, telemetría.
* `FormatSelectionTests`: la selección de formato con listas de formatos simuladas.
* La cámara y el codificador por hardware se prueban en el iPhone real en las pruebas guiadas (el simulador no tiene cámara).
