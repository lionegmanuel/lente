# Lente · Arquitectura y protocolo

Todo lo que dice «verificar en el tag» se confirma leyendo el código de scrcpy en `v4.1` antes de implementar. Si el código dice otra cosa, manda el código y se corrige este documento en el mismo commit.

## 1 · Componentes

| Componente | Dónde vive | Lenguaje | Responsabilidad |
|---|---|---|---|
| Servidor iOS | `ios/` | Swift 5.9+, sin dependencias | Cámara, codificación, servidor TCP, controles, telemetría, interfaz mínima |
| Cliente | `app/` (fork de scrcpy) | C11, como scrcpy | Conexión por usbmux o adb, demuxer, decodificador, pantalla, v4l2, grabación, atajos |
| Servidor Android | `server/` | Java (scrcpy original) | Sin cambios. Se mantiene para que la herramienta sirva con Android |
| Herramientas | `tools/` | Python 3 (biblioteca estándar) | Sonda usbmux, medición de delay, utilidades de prueba |
| CI | `.github/workflows/` | YAML | Builds de iOS, Windows y Linux, pruebas, releases |

## 2 · Camino del video

1. `AVCaptureSession` entrega `CMSampleBuffer` (NV12, rango de video `420v`) desde un dispositivo físico de cámara.
2. `VTCompressionSession` codifica por hardware en tiempo real: sin reordenamiento de cuadros, control de tasa de baja latencia.
3. La app convierte la salida AVCC a Annex B, arma el encabezado de 12 bytes de scrcpy y escribe en el socket de video.
4. usbmuxd del iPhone lleva la conexión por el cable hasta el usbmuxd de la PC (Apple Mobile Device Service en Windows, `usbmuxd` en Linux).
5. El cliente lee con el demuxer de scrcpy sin cambios, decodifica con FFmpeg y muestra con SDL3 o escribe en v4l2.

No hay buffers intermedios: cada etapa entrega apenas tiene un cuadro. La única cola permitida es la del socket, con tamaño acotado; si se llena, la app descarta cuadros no clave y lo informa en la telemetría.

## 3 · usbmux

usbmuxd multiplexa conexiones TCP sobre USB. El cliente habla con el usbmuxd de la PC y le pide conectarse a un puerto del iPhone. Desde ese momento el socket es un túnel transparente.

### Dónde está usbmuxd

| Sistema | Dirección | Lo provee |
|---|---|---|
| Windows | TCP `127.0.0.1:27015` | Apple Mobile Device Service (app Apple Devices de Microsoft Store, o iTunes) |
| Linux | Socket Unix `/var/run/usbmuxd` | Paquete `usbmuxd` (activado por udev al conectar el iPhone) |

Variable de entorno `USBMUXD_SOCKET_ADDRESS` para sobrescribir la dirección (mismo nombre que usa libimobiledevice), útil para pruebas.

### Formato de mensaje (versión 1, plist)

Encabezado de 16 bytes, **little endian**:

| Campo | Tipo | Valor |
|---|---|---|
| length | u32 | Largo total, encabezado incluido |
| version | u32 | 1 |
| message | u32 | 8 (plist) |
| tag | u32 | Número que el cliente elige; la respuesta lo repite |

Cuerpo: un plist XML (diccionario). Claves que manda el cliente en todos los mensajes: `MessageType`, `ClientVersionString`, `ProgName`.

| MessageType | Claves extra | Respuesta |
|---|---|---|
| `ListDevices` | | `DeviceList`: lista de `{DeviceID, Properties{SerialNumber (UDID), ConnectionType, ProductID, ...}}` |
| `Listen` | | `Result` con `Number` 0, y después eventos `Attached` y `Detached` en el mismo socket |
| `Connect` | `DeviceID`, `PortNumber` | `Result` con `Number` 0 si conectó. **`PortNumber` va en orden de red**: el entero es `htons(puerto)` |

Códigos de `Result`: 0 conectado, 2 dispositivo no encontrado, 3 conexión rechazada (nadie escucha en el puerto, la app no está abierta). Verificar contra `libusbmuxd` y anotar cualquier otro código observado.

Referencia de implementación: `libusbmuxd` (LGPL). **No se copia código LGPL al cliente** (Apache 2.0): se reimplementa el subconjunto de arriba, que es chico. La sonda `plantillas/usbmux_probe.py` es la versión de referencia en Python.

Pregunta abierta que responde la Fase 0 (riesgo R1): si `Connect` a un puerto de una app exige que el iPhone haya aceptado «Confiar en esta computadora». Si lo exige, el cliente detecta el error y le explica al usuario qué tocar en el iPhone.

## 4 · Puertos y sesiones

* La app escucha en **`127.0.0.1:27183`** (loopback). Las conexiones que llegan por usbmux entran por loopback; escuchar solo ahí evita exponer la cámara a la red Wi-Fi.
* Una sesión = una conexión de **video** más una de **control**, las dos al mismo puerto.
* Solo una sesión activa. Una segunda conexión de video recibe estado 4 (ocupado) y se cierra.

## 5 · Apertura de sesión (extensión propia «LNTE»)

En Android, el cliente le pasa los parámetros al servidor por `adb shell`. En iOS no se puede lanzar la app desde la PC, así que los parámetros viajan en un mensaje de apertura. Todo en **big endian**, como el protocolo de scrcpy.

### Conexión de video

Cliente → app, apenas conecta:

| Campo | Tipo | Valor |
|---|---|---|
| magic | 4 bytes | `LNTE` |
| version | u16 | Versión del protocolo (1) |
| flags | u16 | 0 (reservado) |
| length | u32 | Largo del texto que sigue |
| params | UTF-8 | Líneas `clave=valor` separadas por `\n` |

Las claves son **las mismas del servidor Android de scrcpy** (verificar los nombres en `server/src/main/java/com/genymobile/scrcpy/Options.java` del tag): `video_codec`, `video_bit_rate`, `max_size`, `max_fps`, `camera_id`, `camera_facing`, `camera_size`, `camera_fps`, `camera_high_speed`, `camera_ar`, `camera_torch`, `camera_zoom`, `capture_orientation`, `send_device_meta`, `send_stream_meta`, `send_frame_meta`, `raw_stream`, `list_cameras`, `list_camera_sizes`, `control` (verificado en el tag `v4.1`). Las propias de Lente llevan prefijo `lente_`: `lente_lock_exposure`, `lente_lock_focus`, `lente_lock_wb`, `lente_stabilization`, `lente_keyframe_interval`. Una clave desconocida devuelve estado 2 con su nombre en el mensaje (falla temprano, nunca en silencio).

App → cliente:

| Campo | Tipo | Valor |
|---|---|---|
| magic | 4 bytes | `LNTE` |
| version | u16 | Versión que habla la app |
| status | u8 | 0 OK · 1 versión incompatible · 2 parámetro inválido · 3 cámara no disponible · 4 sesión ocupada · 5 permiso de cámara denegado |
| session | u64 | Identificador de sesión (aleatorio), 0 si hubo error |
| msg_len | u16 | Largo del mensaje |
| msg | UTF-8 | Detalle legible (en inglés; el cliente lo traduce si conoce el código) |

Si el estado es 0, sigue el stream de scrcpy en la misma conexión (sección 6).

### Conexión de control

Cliente → app: `LNTC` (4 bytes) + `session` (u64). Si no coincide con la sesión activa, la app cierra. Después, mensajes de control de scrcpy en las dos direcciones (sección 7).

Orden: el cliente abre video, espera el OK, y recién ahí abre control.

## 6 · Stream de video (formato de scrcpy)

Verificado en `app/src/demuxer.c`, `app/src/server.c` y `server/.../device/Streamer.java` del tag `v4.1` (2026-11-15).

0. **Byte de prueba:** en Android, el servidor manda un byte en 0 apenas conecta (`send_dummy_byte`) para que el cliente sepa que hay alguien escuchando detrás del túnel. En Lente cumple esa función la respuesta LNTE; después de un OK no se manda byte de prueba.
1. **Metadatos del dispositivo** (si `send_device_meta=true`): 64 bytes con el nombre del dispositivo en UTF-8, completado con ceros (`SC_DEVICE_NAME_FIELD_LENGTH`). Usar el nombre del modelo («iPhone 15 Pro Max»), nunca el nombre personal del iPhone.
2. **Metadatos del stream** (si `send_stream_meta=true`): solo u32 identificador del códec (`h264` = `0x68323634`, `h265` = `0x68323635`). El valor 0 significa stream deshabilitado y 1 error de configuración en el dispositivo. En 4.1 el ancho y el alto ya no van acá: van en el paquete de sesión.
3. **Paquete de sesión** (solo video, obligatorio antes del primer paquete de medios): 12 bytes. Byte 0 con el bit más alto en 1; bit 0 del byte 3 = «la PC pidió el cambio de tamaño» (en Lente, siempre 0); bytes 4 a 7 ancho u32; bytes 8 a 11 alto u32. Se manda de nuevo cada vez que cambia el tamaño (rotación, otro lente, otro formato): scrcpy 4.1 lo soporta a mitad del stream sin cerrar la ventana (`sc_packet_source_sinks_push_session`), así que no hace falta reabrir la sesión.
4. **Paquetes de medios** (si `send_frame_meta=true`), cada uno con encabezado de 12 bytes:

| Campo | Tipo | Contenido |
|---|---|---|
| pts_flags | u64 | Bit 63 en 0 (paquete de medios). Bit 62: paquete de configuración. Bit 61: cuadro clave. Bits 0 a 60: PTS en microsegundos |
| size | u32 | Largo del paquete |
| data | bytes | Annex B (códigos de inicio `00 00 00 01`) |

* El paquete de configuración lleva SPS y PPS (en HEVC también VPS), se manda antes del primer cuadro y cada vez que cambian. El cliente lo une con el paquete siguiente (`packet_merger`), igual que con Android.
* PTS: tiempo de presentación del `CMSampleBuffer`, en microsegundos desde el primer cuadro de la sesión.
* Con `raw_stream=true` (la clave de scrcpy, en lugar de una propia) no hay apertura LNTE ni metadatos: Annex B pelado. Solo para diagnóstico con `ffplay`.

## 7 · Control

Reutilizar los tipos de mensaje de scrcpy 4.1 cuando existan (verificar en `app/src/control_msg.h` y `app/src/device_msg.h`):

| Función | Mensaje |
|---|---|
| Pantalla en negro y volver (Alt+O, Alt+Shift+O) | El de «display power» de scrcpy; la app lo interpreta como negro más brillo mínimo |
| Reiniciar video y pedir cuadro clave (Alt+Shift+R) | El de «reset video» de scrcpy |
| Linterna (Alt+T / Alt+Shift+T) | `CAMERA_SET_TORCH` de scrcpy 4.1 (tipo 18, cuerpo u8 encendido). El nivel de la linterna queda fijo en el máximo |
| Zoom de cámara (Alt+Arriba / Alt+Abajo) | `CAMERA_ZOOM_IN` y `CAMERA_ZOOM_OUT` de scrcpy 4.1 (tipos 19 y 20, sin cuerpo) |
| Mensajes de toque, teclado, portapapeles, UHID | No aplican: la app los ignora sin cortar la sesión |

Mensajes propios, en el rango `0x60` a `0x6F` para no chocar con los de scrcpy (verificado en el tag: los de control llegan hasta `SCAN_FILE` = 22 y los del dispositivo hasta `UHID_OUTPUT` = 2):

| Tipo | Nombre | Cuerpo |
|---|---|---|
| `0x60` | `LENTE_SET_LENS` | u8: 0 ultra gran angular, 1 gran angular, 2 teleobjetivo, 3 frontal |
| `0x61` | `LENTE_LOCK` | u8 qué (bit 0 exposición, bit 1 foco, bit 2 balance de blancos) + u8 encendido |

Mensajes del dispositivo al cliente:

| Tipo | Nombre | Cuerpo |
|---|---|---|
| `0x60` | `LENTE_TELEMETRY` (cada 2 s) | u8 estado térmico (0 nominal, 1 fair, 2 serious, 3 critical) · u8 batería en % (255 desconocida) · u8 estado de batería (0 desconocido, 1 descargando, 2 cargando, 3 llena) · u32 cuadros codificados · u32 cuadros descartados · u32 tasa de bits real en bps |
| `0x61` | `LENTE_EVENT` | u8 código (1 interrupción de cámara, 2 cámara retomada, 3 cambio de lente hecho) + u16 largo + texto |

## 8 · Reconexión

* El cliente escucha eventos `Attached` y `Detached` de usbmux.
* Si se corta la conexión, reintenta cada 500 ms durante 30 segundos (configurable con `--ios-reconnect`), muestra «Esperando al iPhone» en la ventana y conserva la ventana abierta. OBS sigue capturando la misma ventana.
* La app, al volver a primer plano o terminar una interrupción, reabre la cámara y queda escuchando. El cliente reabre la sesión con los mismos parámetros.

## 9 · Versionado del protocolo

* `version` en LNTE empieza en 1. Un cambio incompatible sube el número.
* La app acepta su versión y la anterior cuando sea posible; si no, responde estado 1 con la versión que necesita. El cliente muestra: «Actualizá la app del iPhone» o «Actualizá Lente en la PC».

## 10 · Seguridad y privacidad

* Solo loopback; nada escucha en Wi-Fi.
* Sin cuentas, sin telemetría a internet, sin analítica.
* La app pide únicamente el permiso de cámara.
* Nombre del dispositivo en los metadatos: el modelo, no el nombre personal.
