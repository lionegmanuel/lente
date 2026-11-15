# Lente · Plan técnico maestro

**Versión:** 1.0 · **Fecha:** 2026-11-15 · **Arquitecto:** Claude (sesión de Manuel) · **Dueño del producto:** Manuel Lione

«Lente» es el nombre provisional. El definitivo lo decide Manuel (ver decisión D3); renombrar antes de la Fase 1 cuesta minutos, después cuesta más.

---

## 1 · Objetivo

Convertir un iPhone en una cámara para la PC, por cable USB, con la misma experiencia que scrcpy daba con Android: conectar, abrir y grabar en OBS. Sin delay perceptible, sin bajar la calidad que el iPhone puede dar, consumiendo lo mínimo posible en el celular y en la PC, gratis y de código abierto.

Caso de uso principal: Manuel graba sus videos en OBS con un iPhone 15 Pro Max como cámara, en una laptop con Windows 10 y en una PC con Fedora KDE. El micrófono va siempre aparte (Boya BY-V por USB a la PC, plantilla en `VELINEX/Contenido y Marketing/Plantilla Microfono OBS/`). **El iPhone nunca aporta audio.**

Visión: que sirva a miles de usuarios. Hoy no existe una herramienta gratis y abierta que haga esto con iPhone por cable.

## 2 · Qué se construye (resumen de arquitectura)

| iPhone | Enlace | PC (Windows 10/11 · Linux) |
|---|---|---|
| App «Lente» en Swift: AVFoundation (cámara), VideoToolbox (H.264 o HEVC), servidor TCP en loopback con el protocolo de scrcpy | Cable USB → usbmuxd | Fork de scrcpy 4.1: backend iOS por usbmux más el backend Android original por adb; decodifica con FFmpeg (GPU opcional); ventana SDL, v4l2 y grabación |

* **App iOS:** mínima (meta: menos de 2 MB), sin dependencias de terceros. Captura la cámara, codifica por hardware y sirve el video en un puerto del iPhone usando el mismo formato de stream que el servidor Android de scrcpy.
* **Cliente PC:** fork de scrcpy 4.1 con un backend nuevo que llega al iPhone por usbmuxd (en Windows, el servicio Apple Mobile Device en `127.0.0.1:27015`; en Linux, `/var/run/usbmuxd`). Todo lo demás es scrcpy: ventana, atajos, `--v4l2-sink`, grabación, decodificación. Android sigue funcionando igual.
* **Repositorio único:** el fork de scrcpy con la carpeta `ios/` agregada. scrcpy ya tiene `server/` (Android) y `app/` (cliente); sumamos `ios/` (servidor iPhone).
* **Compilación sin Mac:** GitHub Actions (macOS para la app iOS, Linux con MinGW para Windows y Linux nativo). Repositorio público: minutos ilimitados y gratis.
* **Instalación en el iPhone sin pagar:** Apple ID gratis + SideStore, con renovación de la firma desde el propio iPhone y actualizaciones por una «fuente» de SideStore publicada en GitHub. Camino pago (USD 99 por año, App Store) documentado para cuando se lance al público.

Detalle: [ARQUITECTURA_Y_PROTOCOLO.md](ARQUITECTURA_Y_PROTOCOLO.md), [APP_IOS.md](APP_IOS.md), [CLIENTE_PC.md](CLIENTE_PC.md), [BUILD_FIRMA_DISTRIBUCION.md](BUILD_FIRMA_DISTRIBUCION.md).

### Por qué un fork de scrcpy y no otra cosa

| Opción | Veredicto |
|---|---|
| `adb` falso que engaña al scrcpy oficial | Descartada. Rápida para uso propio, pero se rompe con cada versión de scrcpy y no sirve como producto |
| Cliente propio desde cero | Descartada. Rehacer ventana, decodificación, atajos, v4l2 y grabación es meses de trabajo para llegar a lo que scrcpy ya hace bien |
| **Fork de scrcpy con backend iOS** | **Elegida.** Réplica exacta de la experiencia, Android incluido, diff acotado y mantenible |
| App multiplataforma (Flutter, React Native) en el iPhone | Descartada. 20 a 50 MB y capas extra que suman delay; en Android ya está scrcpy |

## 3 · Alcance

### Versión 1 (este plan)

* Cámaras: todas las del iPhone (0,5x, 1x, 5x y frontal), sin cambio automático de lente.
* Resoluciones y cuadros: hasta 4K60; 1080p a 60 y 120.
* Códecs: H.264 y HEVC por hardware.
* Ventana como scrcpy, pantalla completa, `--v4l2-sink` en Linux, grabación a archivo.
* Atajos: linterna, zoom, cambio de lente, pantalla en negro (equivalente de apagar), reiniciar video, cerrar.
* Controles: bloquear exposición, foco y balance de blancos; estabilización apagada por defecto.
* Telemetría del iPhone en la PC: temperatura (estado térmico), batería, cuadros entregados.
* Reconexión automática y mensajes de error claros.
* Windows 10/11 x64 y Linux x64 (Fedora 44 KDE como referencia).
* Integración con el flujo de Velinex: lanzadores, accesos directos y OBS en las dos PC.

### Fuera de la versión 1 (anotado para después)

* Audio del iPhone (decisión explícita de Manuel: micrófono siempre aparte).
* Modo Wi-Fi.
* Cliente macOS.
* Cámara virtual de sistema en Windows (para Zoom o Meet) y plugin nativo de OBS.
* Publicación en App Store.
* Duplicar o controlar la pantalla del iPhone.

### Límites impuestos por Apple (no se pueden saltear)

* La app tiene que estar abierta en primer plano en el iPhone. La PC no la puede abrir.
* La pantalla no se apaga: se pone en negro con brillo al mínimo (en OLED, el negro son píxeles apagados).
* Una llamada o el Centro de Control interrumpen la cámara; la app la retoma sola al volver.
* Con Apple ID gratis, la firma dura 7 días y hay un máximo de 3 apps instaladas por fuera de la App Store.

## 4 · Decisiones

| # | Decisión | Valor por defecto del plan | Estado |
|---|---|---|---|
| D1 | Firma e instalación | Apple ID gratis aparte + SideStore; Sideloadly de plan B | Tomada (Manuel) |
| D2 | Repositorio | Público en GitHub, licencia Apache 2.0 (la de scrcpy) | Tomada (Manuel) |
| D3 | Nombre | «Lente» | Tomada (Manuel) |
| D4 | Versión mínima de iOS | iOS 16.0 (el iPhone de Manuel tiene iOS 26) | Tomada |
| D5 | Base del cliente | scrcpy 4.1 (la versión que Manuel ya usa), con política de actualización | Tomada |
| D6 | Puerto en el iPhone | 27183, solo en loopback | Tomada |
| D7 | Audio | Ninguno en v1 | Tomada (Manuel) |
| D8 | Calidad por defecto | 1080p60 H.264 a 16 Mbps (la de scrcpy con el POCO); 4K60 HEVC como opción | Tomada, revisable con mediciones |

Registro completo y razones: [RIESGOS_Y_DECISIONES.md](RIESGOS_Y_DECISIONES.md).

## 5 · Metas medibles (criterios de aceptación globales)

| Métrica | Meta v1 | Cómo se mide |
|---|---|---|
| Delay de vidrio a vidrio, 1080p60 por USB | Mediana 70 ms o menos, percentil 95 de 100 ms o menos | Cronómetro de milisegundos en el monitor filmado por el iPhone y capturas de pantalla (ver PRUEBAS) |
| Cuadros entregados a 1080p60 | 59,5 o más de promedio, sin congelamientos de más de 100 ms en 30 minutos | Contador de la telemetría y log del cliente |
| Sesión continua | 60 minutos a 1080p60 y 30 minutos a 4K60 sin cortes; si el iPhone llega a estado térmico «serious», el cliente lo avisa | Prueba de resistencia |
| Tamaño de la app iOS | IPA de menos de 2 MB | Tamaño del artefacto en CI |
| CPU de la PC a 1080p60 | 8% o menos del total con decodificación por GPU; reportar el valor con CPU | Administrador de tareas, `nvidia-smi`, `radeontop` |
| Batería del iPhone a 1080p60 conectado a USB-C | Que no baje más de 10% por hora | Telemetría |
| Arranque | De doble clic a imagen en 3 segundos o menos con la app abierta | Cronómetro |
| Reconexión | Imagen de vuelta 3 segundos o menos después de reconectar el cable o volver a la app | Prueba manual |
| Android sin cambios | Todas las pruebas de scrcpy 4.1 pasan; un Android sigue funcionando igual | `meson test` y prueba manual si hay Android a mano |

Las metas de delay se recalibran al cierre de la Fase 0 con la primera medición real; si cambian, se anota el porqué en `RIESGOS_Y_DECISIONES.md`.

## 6 · Fases

Cada fase termina con una **compuerta**: entregables listos, pruebas automáticas en verde y, cuando hace falta el iPhone, una prueba guiada con Manuel (checklist en [PRUEBAS_Y_ACEPTACION.md](PRUEBAS_Y_ACEPTACION.md)). No se pasa de fase sin la compuerta. El estado vive en [ESTADO.md](ESTADO.md).

### Fase 0 · Cimientos y pruebas de riesgo

Objetivo: probar lo más riesgoso antes de escribir el producto: compilar sin Mac, instalar gratis y hablar con el iPhone por el cable.

1. Confirmar con Manuel D1, D2 y D3. Sin D2 confirmada no se publica nada en GitHub.
2. Armar el repositorio (pasos exactos en `BUILD_FIRMA_DISTRIBUCION.md` §1): `git init` en `DEV/lente`, scrcpy como `upstream`, rama `main` desde el tag `v4.1`, carpeta `ios/` y estos documentos.
3. Workflow de CI de la app iOS mínima (pantalla «Hola» + permiso de cámara) que produce una IPA sin firmar. Plantillas en `plantillas/`.
4. Cadena de instalación completa con Manuel: Modo desarrollador en el iPhone, SideStore instalado, la IPA mínima instalada desde SideStore y la renovación probada. Esta es la prueba de riesgo número uno.
5. En la laptop: Manuel instala **Apple Devices** desde Microsoft Store (trae Apple Mobile Device Service). Leer con `plantillas/usbmux_probe.py --listar` el UDID del iPhone; la versión de iOS (D4) la lee Manuel en Ajustes › General › Información. La sonda ya se probó el 2026-11-15: sin el servicio, informa el error y la solución.
6. Prueba de riesgo número dos: la app mínima abre un puerto 27183 en loopback que manda bytes conocidos; `usbmux_probe.py --conectar 27183` los recibe en Windows. Confirma si hace falta «Confiar en esta computadora» para conectar a un puerto (riesgo R1).
7. Lo mismo en Fedora con `usbmuxd`, cuando Manuel esté en esa PC (puede quedar para la Fase 2 si la PC no está disponible).
8. Medir la línea de base: delay y CPU de scrcpy 4.1 con un Android si hay uno a mano; si no, se toma la meta de la sección 5.

**Compuerta:** IPA mínima compilada en CI e instalada por SideStore; bytes del iPhone recibidos en la PC por el cable; versión de iOS anotada.

### Fase 1 · Servidor iOS: cámara a stream

Objetivo: la app transmite video real en el formato de scrcpy, probado sin tocar todavía el cliente.

1. Captura con `AVCaptureSession` sobre un dispositivo físico (sin lente automático), formato elegido por resolución y cuadros, estabilización apagada, cuadros fijos.
2. Codificación con `VTCompressionSession` en tiempo real, sin cuadros B, control de tasa de baja latencia, cuadro clave cada 2 segundos y a pedido.
3. Conversión de AVCC a Annex B, paquete de configuración (SPS/PPS, y VPS en HEVC) marcado como en scrcpy.
4. Servidor TCP en `127.0.0.1:27183` con el protocolo de `ARQUITECTURA_Y_PROTOCOLO.md`: mensaje de inicio con parámetros, metadatos del dispositivo y del códec, paquetes con encabezado de 12 bytes.
5. Modo de diagnóstico `raw=true`: Annex B pelado, para verlo con `usbmux_probe.py | ffplay`.
6. Interfaz mínima: estado, ajustes guardados, vista previa apagada por defecto, pantalla siempre encendida mientras transmite.
7. Pruebas XCTest en el simulador (CI): conversión Annex B, armado de paquetes, parser del mensaje de inicio.

**Compuerta:** con Manuel, `usbmux_probe.py --conectar 27183 --raw | ffplay` muestra 1080p60 fluido 10 minutos; delay medido a ojo y anotado.

### Fase 2 · Cliente PC: backend iOS en el fork

Objetivo: `lente.exe` (scrcpy renombrado) muestra el iPhone igual que mostraba el POCO.

1. Módulo `app/src/ios/usbmux.c`: conexión a usbmuxd (TCP en Windows, socket Unix en Linux), plist XML mínimo, `ListDevices`, `Listen` (eventos de conexión), `Connect`.
2. Módulo `app/src/ios/ios_server.c`: el equivalente de `server.c` para iOS. Abre la conexión de video y la de control, manda el mensaje de inicio, valida la respuesta, entrega los sockets al resto de scrcpy sin cambios.
3. Selección de dispositivo: `--ios`, `--ios-udid=`, y detección automática (si no hay Android por adb y hay un iPhone, usa el iPhone).
4. Mapeo de opciones existentes de scrcpy para cámara (`--video-source=camera`, `--camera-facing`, `--camera-id`, `--camera-size`, `--camera-fps`, `--video-codec`, `--video-bit-rate`, `--max-fps`, orientación) al mensaje de inicio. Audio forzado en apagado.
5. Renombrado del binario y de los textos visibles (marca scrcpy fuera de la interfaz, aviso de origen en `--version` y en NOTICE).
6. CI: Windows (cruzado con MinGW, como los releases de scrcpy) y Linux.

**Compuerta:** en la laptop, doble clic en un `.cmd` de prueba abre la ventana «Lente» con el iPhone a 1080p60; Manuel lo captura en OBS con su escena; en Fedora, `--v4l2-sink=/dev/video10` funciona (si la PC está disponible).

### Fase 3 · Controles y telemetría

1. Mensajes de control de cámara (linterna, zoom, cambio de lente) reutilizando los atajos de cámara de scrcpy 4.1 donde existan y agregando los que falten.
2. Alt+O y Alt+Shift+O: pantalla en negro y brillo al mínimo, y restauración.
3. Bloqueo de exposición, foco y balance de blancos (atajos y opciones de línea de comandos).
4. Pedido de cuadro clave y reinicio de video (Alt+Shift+R).
5. Mensaje de telemetría del dispositivo cada 2 segundos: estado térmico, batería, cuadros codificados y descartados. El cliente lo muestra en el título de la ventana y en consola, y avisa en «serious» y «critical».

**Compuerta:** Manuel prueba cada atajo con el checklist.

### Fase 4 · Robustez

1. Reconexión automática: cable desconectado, app enviada al fondo, llamada entrante, Centro de Control, bloqueo de pantalla.
2. Mensajes de error accionables: falta Apple Mobile Device Service, iPhone sin confiar, app cerrada, puerto ocupado, versión de protocolo distinta.
3. Política térmica: nunca bajar calidad sin avisar; opción `--thermal-auto` que baja cuadros por segundo de forma explícita.
4. Varios dispositivos conectados (Android e iPhone a la vez).

**Compuerta:** checklist de robustez completo con Manuel.

### Fase 5 · Rendimiento y calidad

1. Decodificación por GPU opcional (`--hw-decode=auto|d3d11va|vaapi|none`), con prioridad a la placa de video según la regla de Velinex.
2. 4K60 HEVC estable; búsqueda de tasa de bits por resolución.
3. Medición de delay con el procedimiento de PRUEBAS, 1080p60 y 4K60.
4. Prueba de resistencia de 60 minutos y medición de batería y CPU.
5. Ajuste de color: espacio BT.709, rango declarado en el VUI y validado en OBS con el LUT de Manuel.

**Compuerta:** tabla de la sección 5 completa con valores medidos.

### Fase 6 · Distribución

1. Releases en GitHub: ZIP para Windows x64, tarball para Linux x64 e IPA.
2. Fuente de SideStore (`sidestore-source.json`) publicada en el repo, para que la app se actualice desde el iPhone sin la PC.
3. Guía de instalación en español e inglés (README para el público).
4. Versionado: `MAJOR.MINOR.PATCH`, el protocolo con su propia versión.

**Compuerta:** instalación desde cero siguiendo solo la guía, hecha por Manuel en Fedora.

### Fase 7 · Integración en Velinex

Detalle en [INTEGRACION_VELINEX.md](INTEGRACION_VELINEX.md): lanzadores para Windows y Linux, accesos directos «Webcam iPhone», fuente de OBS en las dos PC con la escena, el LUT y la máscara de siempre, sincronización con el micrófono BY-V medida con un aplauso, y actualización de la documentación del módulo de webcam. Lo de scrcpy para Android se mantiene.

**Compuerta:** Manuel graba un video real de punta a punta en la laptop y en Fedora.

## 7 · Cronograma orientativo

| Fase | Esfuerzo estimado | Depende de Manuel |
|---|---|---|
| 0 | 1 a 2 sesiones | Sí: decisiones, Apple Devices, SideStore, pruebas con el iPhone |
| 1 | 2 a 3 sesiones | Una prueba guiada |
| 2 | 3 a 4 sesiones | Una prueba guiada en cada PC |
| 3 | 1 a 2 sesiones | Checklist de atajos |
| 4 | 1 a 2 sesiones | Checklist de robustez |
| 5 | 2 sesiones | Mediciones |
| 6 | 1 sesión | Instalación desde cero |
| 7 | 1 sesión | Grabación real |

Cada prueba con el iPhone es una vuelta de unos 10 a 15 minutos (compilar en CI, actualizar por SideStore, probar, informar). Se agrupan las pruebas para no hacerle perder tiempo a Manuel.

## 8 · Documentos del plan

| Archivo | Contenido |
|---|---|
| `PLAN.md` | Este documento |
| `ARQUITECTURA_Y_PROTOCOLO.md` | Componentes, usbmux, protocolo de stream y de control, extensiones propias |
| `APP_IOS.md` | Especificación de la app del iPhone |
| `CLIENTE_PC.md` | Especificación del fork de scrcpy |
| `BUILD_FIRMA_DISTRIBUCION.md` | Repositorio, CI, firma sin Mac, SideStore, releases, camino App Store |
| `PRUEBAS_Y_ACEPTACION.md` | Pruebas automáticas, pruebas guiadas con Manuel, procedimientos de medición |
| `RIESGOS_Y_DECISIONES.md` | Riesgos con mitigación y registro de decisiones |
| `INTEGRACION_VELINEX.md` | Lanzadores, OBS y documentación en el flujo de Manuel |
| `ESTADO.md` | Tablero de avance por fase (lo actualiza el equipo) |
| `PROMPT_EQUIPO.md` | Prompt completo para el equipo técnico |
| `plantillas/` | Archivos de arranque: XcodeGen, workflow de CI, sonda usbmux, fuente de SideStore |
