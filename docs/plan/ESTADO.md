# Lente · Estado

Lo actualiza el equipo al cerrar cada tarea y cada compuerta. Una línea por avance, con fecha. Las mediciones van con su número.

## Decisiones de Manuel

- [x] D1 · Firma gratis con SideStore y el Apple ID de siempre de Manuel (cambio del 2026-11-15: el Apple ID aparte no pudo iniciar sesión en iloader, ver Registro); Sideloadly de plan B (Manuel, 2026-11-15)
- [x] D2 · Repositorio público en GitHub, Apache 2.0 (Manuel, 2026-11-15)
- [x] D3 · Nombre definitivo «Lente», Bundle ID `digital.velinex.lente` (Manuel, 2026-11-15)
- [x] D4 · iPhone de Manuel con iOS 26; versión mínima de la app 16.0 (Manuel, 2026-11-15)

## Fases

| Fase | Estado | Compuerta pasada | Notas |
|---|---|---|---|
| 0 · Cimientos y pruebas de riesgo | Terminada | 2026-11-15 | IPA de CI instalada por SideStore, bytes del iPhone recibidos en la laptop por el cable, iOS 26.6. Fedora queda para la Fase 2 |
| 1 · Servidor iOS | Pendiente | | |
| 2 · Cliente PC | Pendiente | | |
| 3 · Controles y telemetría | Pendiente | | |
| 4 · Robustez | Pendiente | | |
| 5 · Rendimiento y calidad | Pendiente | | |
| 6 · Distribución | Pendiente | | |
| 7 · Integración Velinex | Pendiente | | |

## Mediciones

| Métrica | Meta | Medido | Fecha |
|---|---|---|---|
| Delay 1080p60 H.264 (mediana / p95) | 70 / 100 ms | | |
| Delay 4K60 HEVC (mediana / p95) | a definir | | |
| Cuadros promedio 1080p60, 30 min | 59,5 o más | | |
| CPU PC 1080p60 (GPU / software) | 8% o menos con GPU | | |
| Batería iPhone por hora, 1080p60 | 10% o menos | | |
| Tamaño IPA | menos de 2 MB | 75.419 bytes (app de la Fase 1) | 2026-11-15 |
| Sonda por cable, Windows (Fase 0) | bytes íntegros | 7.236 bytes en unos 30 s, 603 bloques `LENTE-F0` con contador 0 a 602 sin saltos | 2026-11-15 |
| Arranque hasta imagen | 3 s o menos | | |
| Reconexión | 3 s o menos | | |

## Diferencias encontradas entre el plan y el código de scrcpy 4.1

(anotar acá, con archivo y línea)

Revisión del 2026-11-15 contra el tag `v4.1` (commit `2926c06`). Documentos corregidos en el mismo commit.

1. **Encabezado de 12 bytes** (`app/src/demuxer.c:14-17`, `Streamer.java:17-19`): bit 63 marca paquete de sesión, bit 62 configuración, bit 61 cuadro clave y PTS en los bits 0 a 60. El plan decía 63 configuración y 62 clave.
2. **Paquete de sesión nuevo** (`app/src/demuxer.c:81-93` y `:225-245`): antes del primer paquete de video va un paquete de 12 bytes con el ancho y el alto, y se repite cuando cambia el tamaño. scrcpy 4.1 cambia de tamaño a mitad del stream sin cerrar la ventana, así que el cambio de lente no necesita reabrir la sesión.
3. **Metadatos del stream** (`app/src/demuxer.c:61-69`): solo el identificador del códec (u32); el ancho y el alto pasaron al paquete de sesión. La clave se llama `send_stream_meta`, no `send_codec_meta` (`Options.java:559`).
4. **Byte de prueba** (`app/src/server.c:489-506`): con túnel directo, el servidor manda un byte en 0 al conectar. En Lente lo reemplaza la respuesta LNTE.
5. **Diagnóstico Annex B**: scrcpy ya tiene `raw_stream` (`Options.java:562`); se usa esa clave en lugar de `lente_raw`.
6. **Linterna y zoom** (`app/src/control_msg.h:48-50`, `input_manager.c:650-667`): existen `CAMERA_SET_TORCH`, `CAMERA_ZOOM_IN` y `CAMERA_ZOOM_OUT` con Alt+T, Alt+Shift+T y Alt+Arriba/Abajo. Se quitan `LENTE_TORCH` y `LENTE_ZOOM`; el rango `0x60` a `0x6F` está libre en control y en mensajes del dispositivo.
7. **SDL3** (`app/meson.build:130`): el cliente 4.1 usa SDL 3.2 o superior, no SDL2.
8. **Versión de upstream:** ya existen `v5.0` (2026-10-05) y `v5.0.1`. Se sigue en 4.1 por D5; evaluar el salto después de la v1 de Lente.
9. `.github/workflows/release.yml` de scrcpy solo corre a mano (`workflow_dispatch`) y no publica releases: se deja como está.

## Registro

- 2026-11-15 · Plan técnico 1.0 creado por el arquitecto.
- 2026-11-15 · Fase 0: repositorio local con `git init`, remoto `upstream` y `main` desde el tag `v4.1`. Nada publicado (D2 pendiente).
- 2026-11-15 · Fase 0: protocolo de scrcpy 4.1 verificado en el código; 9 diferencias anotadas arriba y plan corregido.
- 2026-11-15 · Fase 0: app mínima (pantalla «Hola», permiso de cámara, sonda en `127.0.0.1:27183` que manda `LENTE-F0` más un contador cada 50 ms), prueba XCTest y workflow `lente-ios.yml` escritos. Sin compilar todavía: el CI necesita el repo publicado (D2).
- 2026-11-15 · Fase 0: laptop sin Apple Mobile Device Service (`usbmux_probe.py --listar` responde «Instalá Apple Devices»). Falta que Manuel lo instale.
- 2026-11-15 · Fase 0: Manuel confirmó D1 a D4 en un solo mensaje. «Lente» libre en GitHub (`lionegmanuel/lente` no existía).
- 2026-11-15 · Fase 0: repo publicado en `github.com/lionegmanuel/lente` (D2). Ramas `main` y `fase-0-cimientos`.
- 2026-11-15 · Fase 0: primer CI de iOS en verde (run 43741142940): Xcode 16.4 en macOS 15.8.2, 2 pruebas XCTest pasadas en simulador, IPA sin firmar de 29.183 bytes. Pre-release `v0.1.0-fase0` con la IPA.
- 2026-11-15 · Fase 0: procedimiento de SideStore verificado en `docs.sidestore.io` y escrito en `BUILD_FIRMA_DISTRIBUCION.md` §3. Cambio: en Windows, iTunes directo de Apple en lugar de Apple Devices (lo pide iloader; Apple Devices queda de alternativa).
- 2026-11-15 · Fase 0: en la laptop, iTunes e iloader 2.4.1 instalados; iloader ve el iPhone (iOS 26.6) por USB. Con el Apple ID aparte, sin dispositivo de confianza, el código llega solo por SMS e iloader falla con «Cannot submit code without knowing which method to use» (`isideload/src/auth/apple_account.rs:329`; mismo caso en `nab138/iloader#1162`, abierto). Manuel cambia D1: se firma con su Apple ID de siempre, cuyo código llega al iPhone como notificación.
- 2026-11-15 · Fase 0: SideStore instalado con iloader (Apple ID de siempre), Modo desarrollador activado, LocalDevVPN conectada y primera renovación hecha. Lente `v0.1.0-fase0` instalada desde SideStore («Sideloaded», vence en 7 días); quedan 9 identificadores de app esta semana.
- 2026-11-15 · Fase 0: `usbmux_probe.py --listar` ve el iPhone (DeviceID 3, USB, ProductID 4776, iOS 26.6). Con Lente cerrada, usbmuxd responde 3 (conexión rechazada); con Lente abierta, `--conectar 27183` recibe 603 bloques íntegros. Riesgo R1: anda con el iPhone ya en «Confiar» con la laptop; sin confianza no se probó.
- 2026-11-15 · Compuerta de la Fase 0 pasada. Línea de base con Android: no hay uno a mano, se toma la meta del plan (sección 5). Fedora queda para la Fase 2.
- 2026-11-15 · Fase 0, respuestas de Manuel: Lente abrió, pidió la cámara y el permiso quedó concedido; después de la sonda vuelve a «Esperando la computadora» (correcto). El iPhone no mostró ningún aviso durante la conexión (riesgo R1: con el iPhone en «Confiar», conectar a un puerto no pide nada).
- 2026-11-15 · Fase 1: rama `fase-1-servidor-ios`. App 0.2.0: cámara física con formato `420v` elegido por tamaño y cuadros, estabilización y HDR apagados; `VTCompressionSession` con control de tasa de baja latencia, sin cuadros B; AVCC a Annex B; servidor LNTE con el formato de scrcpy 4.1 (respuesta, nombre del modelo, códec, paquete de sesión, encabezados de 12 bytes) y `raw_stream`; descarte de cuadros no clave con más de 2 envíos pendientes. La conexión de control se acepta y se ignora hasta la Fase 3. `usbmux_probe.py` suma `--lnte` y `--demux` (valida el formato y mide cuadros por segundo y tasa de bits).
- 2026-11-15 · Fase 1: CI en verde (run 43759257697): 30 pruebas XCTest pasadas (AnnexB, protocolo y selección de formato), IPA sin firmar de 75.419 bytes. Pre-release `v0.2.0-fase1`. Falta la prueba guiada con Manuel (ffplay 10 minutos y delay a ojo).
