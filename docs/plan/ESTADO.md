# Lente · Estado

Lo actualiza el equipo al cerrar cada tarea y cada compuerta. Una línea por avance, con fecha. Las mediciones van con su número.

## Decisiones de Manuel

- [x] D1 · Firma gratis con SideStore y un Apple ID gratis aparte, creado solo para esto; Sideloadly de plan B (Manuel, 2026-11-15)
- [x] D2 · Repositorio público en GitHub, Apache 2.0 (Manuel, 2026-11-15)
- [x] D3 · Nombre definitivo «Lente», Bundle ID `digital.velinex.lente` (Manuel, 2026-11-15)
- [x] D4 · iPhone de Manuel con iOS 26; versión mínima de la app 16.0 (Manuel, 2026-11-15)

## Fases

| Fase | Estado | Compuerta pasada | Notas |
|---|---|---|---|
| 0 · Cimientos y pruebas de riesgo | En curso | | D1 a D4 confirmadas; repo y app mínima listos; espera Apple Devices y la instalación por SideStore |
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
| Tamaño IPA | menos de 2 MB | | |
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
