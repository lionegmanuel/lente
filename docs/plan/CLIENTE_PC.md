# Lente · Cliente de PC (fork de scrcpy 4.1)

## 1 · Principios

* **Diff chico y aislado:** todo lo nuevo vive en `app/src/ios/` y en pocos puntos de enganche en el código existente. Así se puede actualizar a versiones nuevas de scrcpy con un rebase razonable.
* **Lo que funciona no se toca:** demuxer, decodificador, pantalla, v4l2, grabación y atajos de scrcpy se reutilizan tal cual.
* **Android intacto:** el backend adb y el servidor Java siguen funcionando igual. Todas las pruebas de scrcpy pasan.
* **Estilo de scrcpy:** C11, mismas convenciones de nombres (`sc_`), mismo manejo de errores y de logs (`LOGI`, `LOGW`, `LOGE`).
* **Comentarios y textos nuevos sin guiones largos ni medios** (regla de Velinex).

## 2 · Lectura obligatoria antes de tocar código

Del tag `v4.1`: `app/src/scrcpy.c` (orquestación), `app/src/server.c` y `app/src/server.h` (cómo arranca y conecta el servidor), `app/src/adb/` (túnel), `app/src/demuxer.c`, `app/src/controller.c`, `app/src/control_msg.h`, `app/src/device_msg.h`, `app/src/receiver.c`, `app/src/cli.c` y `app/src/options.h` (opciones), `app/src/input_manager.c` o el archivo de atajos de esa versión, `doc/build.md`, `doc/camera.md`, `release/`. Anotar en `docs/plan/ESTADO.md` cualquier diferencia con lo que dicen estos documentos.

## 3 · Módulos nuevos

```
app/src/ios/
  usbmux.c / usbmux.h          Cliente usbmuxd: conexión, plist XML mínimo, ListDevices, Listen, Connect
  plist_min.c / plist_min.h    Escritura y lectura del subconjunto de plist XML necesario (dict, string, integer, array)
  ios_server.c / ios_server.h  Equivalente de server.c para iOS: abre video y control, LNTE, entrega los sockets
  lente_msg.c / lente_msg.h    Mensajes propios (0x60 a 0x6F) y telemetría
app/tests/
  test_usbmux_plist.c          Armado y lectura de mensajes usbmux
  test_lente_msg.c             Serialización de mensajes propios y de LNTE
```

### `usbmux`

* Windows: socket TCP a `127.0.0.1:27015`. Linux: socket Unix `/var/run/usbmuxd`. `USBMUXD_SOCKET_ADDRESS` lo sobrescribe (`UNIX:/ruta` o `host:puerto`).
* Funciones: `sc_usbmux_list_devices`, `sc_usbmux_listen` (hilo que publica eventos de conexión y desconexión), `sc_usbmux_connect(device_id, port)` que devuelve un socket listo para usar como túnel.
* Errores traducidos: servicio ausente («Instalá Apple Devices desde Microsoft Store» en Windows; «Instalá y activá usbmuxd» en Linux), dispositivo no encontrado, conexión rechazada («Abrí Lente en el iPhone»).
* No se usa ni se copia libusbmuxd (LGPL). Reimplementación propia del subconjunto descrito en `ARQUITECTURA_Y_PROTOCOLO.md` §3.

### `ios_server`

* Misma interfaz pública que `server.c` hacia `scrcpy.c` (verificar qué estructura espera: sockets de video, audio y control, nombre del dispositivo, tamaño). Con audio siempre deshabilitado.
* Pasos: elegir dispositivo (UDID o primero disponible), `Connect` al 27183 para video, mandar LNTE con los parámetros, leer respuesta, si OK `Connect` al 27183 para control con LNTC, devolver los sockets.
* Errores de LNTE mapeados a mensajes en español e inglés.
* Reconexión: si `--ios-reconnect` (por defecto 30 s) y se corta, reintenta y reabre la sesión con los mismos parámetros sin cerrar la ventana. Verificar si scrcpy 4.1 ya tiene un mecanismo para reiniciar el stream sin recrear la pantalla; si no, implementarlo en el backend iOS sin tocar el flujo de Android.

## 4 · Puntos de enganche en el código existente

| Archivo | Cambio |
|---|---|
| `app/src/scrcpy.c` | Elegir backend: si `--ios`, `--ios-udid` o detección automática, usar `ios_server` en lugar de `server` |
| `app/src/cli.c` y `options.h` | Opciones nuevas (sección 5) y validación: con iOS, `--video-source` solo admite `camera` y el audio queda apagado |
| `app/src/receiver.c` | Despachar mensajes del dispositivo `0x60` y `0x61` a `lente_msg` |
| `app/src/control_msg.c` y `.h` | Serializar los mensajes `0x60` y `0x61` (linterna y zoom usan los de scrcpy) |
| Atajos | Mapear los de la sección 6 al backend activo |
| `app/src/screen.c` | Título de la ventana con telemetría (opcional por `--ios-telemetry-title`, por defecto encendido) |
| `meson.build` | Sumar los archivos nuevos y las pruebas |

## 5 · Opciones de línea de comandos

Se reutilizan las de cámara de scrcpy: `--video-source=camera`, `--camera-id`, `--camera-facing`, `--camera-size`, `--camera-fps`, `--camera-high-speed`, `--video-codec`, `--video-bit-rate`, `--max-fps`, `--capture-orientation`, `--list-cameras`, `--window-title`, `--v4l2-sink`, `--no-playback`, `--record`, `--fullscreen`, `--always-on-top`, `--render-driver`. Nuevas:

| Opción | Efecto |
|---|---|
| `--ios` | Fuerza el backend iOS |
| `--ios-udid=UDID` | Elige el iPhone por UDID |
| `--list-ios-devices` | Lista los iPhone conectados (UDID, modelo) |
| `--ios-port=N` | Puerto de la app (por defecto 27183) |
| `--ios-reconnect=S` | Segundos de reintento (0 apaga) |
| `--camera-lock=exposure,focus,wb` | Bloqueos al arrancar |
| `--camera-stabilization` | Activa la estabilización (suma delay) |
| `--keyframe-interval=S` | Intervalo de cuadro clave |
| `--hw-decode=auto\|d3d11va\|cuda\|vaapi\|none` | Decodificación por GPU (Fase 5) |
| `--thermal-auto` | Permite bajar cuadros por segundo de forma explícita si el iPhone llega a «serious» |

Detección automática: si no se pasa ni `--ios` ni `-s`, y adb no ve dispositivos pero usbmux ve un iPhone, se usa el iPhone. Si hay ambos, se usa Android como hace scrcpy hoy y se avisa que existe `--ios`.

## 6 · Atajos (modificador por defecto Alt, como scrcpy)

| Atajo | Con iPhone |
|---|---|
| Alt+O / Alt+Shift+O | Pantalla en negro / volver |
| Alt+T / Alt+Shift+T | Linterna encendida / apagada (son las teclas de cámara de scrcpy 4.1, verificado) |
| Alt+Arriba / Alt+Abajo | Zoom de cámara (son los de scrcpy 4.1, verificado) |
| Alt+L | Siguiente lente (0,5x → 1x → 5x) |
| Alt+E / Alt+F / Alt+W | Bloquear o liberar exposición, foco, balance de blancos |
| Alt+Shift+R | Reiniciar video (pide cuadro clave) |
| Alt+Q | Cerrar |
| Los atajos de toque, teclado y portapapeles | No hacen nada con iPhone, sin errores |

Si un atajo nuevo choca con uno de scrcpy 4.1, se elige otra tecla y se documenta acá.

## 7 · Decodificación por GPU (Fase 5)

* scrcpy decodifica por software. Se suma `--hw-decode` con FFmpeg `hwaccel`: `d3d11va` en Windows (sirve con NVIDIA, AMD e Intel), `vaapi` en Linux (RX 9060 XT de Manuel), `cuda` opcional.
* Con SDL hay que pasar los cuadros a memoria del sistema (`av_hwframe_transfer_data`) salvo que se implemente presentación sin copia; medir si la transferencia se come la ganancia. Si no conviene en 1080p60, dejar `auto` activo solo para 4K y HEVC.
* Fallback silencioso a software solo con aviso en el log.
* Regla de Velinex: GPU antes que CPU. Medir y documentar ambos.

## 8 · Marca y licencia

* Binario `lente` (`lente.exe` en Windows). Título de ventana por defecto: «Lente».
* `--version` muestra: «Lente X.Y.Z, basado en scrcpy 4.1 (Genymobile, Apache 2.0)».
* Se conservan `LICENSE` y `NOTICE` de scrcpy; se agrega al NOTICE la lista de cambios. «scrcpy» no se usa como nombre ni logo del producto.

## 9 · Compilación

* Linux: `meson` + `ninja` como `doc/build.md` del tag, con FFmpeg, SDL3 (3.2 o superior, lo pide `app/meson.build` del tag) y libusb del sistema (en Fedora: `ffmpeg-free-devel` o RPM Fusion; verificar qué códecs trae cada paquete y documentarlo).
* Windows: compilación cruzada con MinGW desde Linux, usando los scripts de `release/` de scrcpy y sus dependencias precompiladas, igual que los releases oficiales. Sale un ZIP con `lente.exe`, las DLL, `adb` (para Android) y los `.cmd` de ejemplo.
* Las dos en GitHub Actions (ver `BUILD_FIRMA_DISTRIBUCION.md`). Nunca se compila en C: de Windows: si se compila local, en `D:\Temp\operius\lente-build`.

## 10 · Pruebas

* `meson test` con las pruebas de scrcpy más las nuevas (`test_usbmux_plist`, `test_lente_msg`).
* Prueba de integración sin iPhone: un servidor falso en Python (`tools/fake_ios_server.py`) que habla LNTE y manda un video H.264 de muestra, expuesto con un usbmuxd simulado o con `USBMUXD_SOCKET_ADDRESS` apuntando a un proxy de prueba. Así el CI prueba el camino completo del cliente.
* Con iPhone: pruebas guiadas de `PRUEBAS_Y_ACEPTACION.md`.
