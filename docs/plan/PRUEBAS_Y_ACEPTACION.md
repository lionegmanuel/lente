# Lente · Pruebas y aceptación

Todo archivo de prueba (grabaciones, capturas, logs, CSV) va a `D:\Temp\operius\lente\` en Windows y a la ruta equivalente del disco de datos en Fedora. Nunca en C:. Se borra al cerrar la fase, salvo los resultados resumidos que van a `ESTADO.md`.

## 1 · Pruebas automáticas (CI, en cada push)

| Capa | Pruebas | Dónde |
|---|---|---|
| App iOS | `AnnexBTests`, `ProtocolTests`, `FormatSelectionTests` en simulador | `lente-ios.yml` |
| Cliente | `meson test`: las de scrcpy 4.1 más `test_usbmux_plist` y `test_lente_msg` | `lente-linux.yml` |
| Integración | `tools/fake_ios_server.py` con un video H.264 de muestra: el cliente abre sesión, recibe 300 cuadros y cierra sin errores | `lente-linux.yml` |
| Compilación Windows | El ZIP se arma y `lente.exe --version` corre bajo Wine | `lente-windows.yml` |

Regla: nada se fusiona a `main` con CI en rojo.

## 2 · Procedimientos de medición

### Delay de vidrio a vidrio

1. Abrir `tools/reloj.html` en el monitor de la PC: un contador de milisegundos grande, actualizado con `requestAnimationFrame`.
2. Poner el iPhone filmando ese monitor; la ventana de Lente en el mismo monitor, al lado del reloj.
3. Grabar la pantalla con OBS a 60 cuadros por segundo durante 20 segundos (o sacar 20 capturas separadas).
4. En cada cuadro: delay = reloj real menos reloj que se ve dentro de la ventana de Lente.
5. Informar mediana y percentil 95 de al menos 20 muestras, con la frecuencia del monitor (la laptop puede ser de 144 Hz; anotarla).
6. Opcional: `tools/medir_delay.py` lee los dos relojes por OCR sobre la grabación, con la GPU (regla de Velinex) y respetando `tope80.py`.

Medir en: 1080p60 H.264 16 Mbps, 1080p60 HEVC, 4K60 HEVC, y 1080p120 si se habilita.

### Cuadros y fluidez

El cliente imprime la telemetría con `-V debug` (una línea cada 2 s: térmico, batería, codificados, descartados, tasa real). `tools/telemetria_csv.py` la convierte en CSV y calcula promedio de cuadros, congelamientos de más de 100 ms y descartes.

### Consumo en la PC

* Windows: Administrador de tareas (CPU de `lente.exe`), `nvidia-smi dmon` para la GTX 1650.
* Linux: `top` y `radeontop` para la RX 9060 XT.
* Medir con `--hw-decode=none` y con GPU, a 1080p60 y 4K60.

### Temperatura y batería

Prueba de resistencia: 60 minutos a 1080p60 y 30 minutos a 4K60, iPhone conectado al USB-C de la laptop, sin funda, apoyado como en una grabación real. Registrar estado térmico máximo, minutos hasta «serious» si llega, batería al inicio y al final.

## 3 · Pruebas guiadas con Manuel

Cada prueba guiada se le pasa a Manuel como una lista corta, en su idioma, con qué tocar y qué contestar. Se agrupan para que cada sesión no pase de 15 minutos. Formato de respuesta pedido: «OK» o qué vio, y una captura si algo falla.

### Fase 0

1. Instalar iTunes descargado directo de Apple (laptop), que trae Apple Mobile Device Service; Apple Devices queda de alternativa. Conectar el iPhone y tocar «Confiar» si lo pide.
2. Seguir la guía de SideStore de `BUILD_FIRMA_DISTRIBUCION.md` §3 (Manuel escribe su Apple ID; el equipo nunca).
3. Instalar la app mínima desde la fuente de prueba. Abrirla. Contestar: ¿abrió? ¿pidió permiso de cámara?
4. Con la app mínima abierta, el equipo corre `usbmux_probe.py --conectar 27183`. Contestar: ¿el iPhone mostró algún aviso?
5. Leer la versión de iOS (Ajustes › General › Información) si la sonda no la obtuvo.

### Fase 1

1. Abrir Lente en el iPhone, apoyarlo horizontal mirando a Manuel.
2. El equipo corre `usbmux_probe.py --conectar 27183 --raw | ffplay` durante 10 minutos.
3. Contestar: ¿se ve fluido? ¿colores normales? ¿el iPhone se calentó? Medición del delay a ojo con el reloj.

### Fase 2

1. Doble clic en `lente-iphone.cmd` de prueba. Contestar: ¿cuánto tardó en aparecer la imagen?
2. En OBS, agregar «Captura de ventana» de «Lente» con la escena de siempre. Contestar: ¿se ve igual que con el POCO? ¿el LUT queda bien?
3. En Fedora (cuando esté disponible): `lente --ios --v4l2-sink=/dev/video10 --no-playback` y la fuente de OBS de siempre.

### Fase 3

Probar cada atajo de `CLIENTE_PC.md` §6 y marcar OK o falla. Ver que el título de la ventana muestre temperatura y batería.

### Fase 4

1. Desconectar y reconectar el cable con la ventana abierta.
2. Salir de la app y volver.
3. Abrir el Centro de Control y cerrarlo.
4. Recibir una llamada de prueba (o simularla con FaceTime de audio).
5. Bloquear la pantalla y desbloquear.
6. Cerrar Apple Devices o detener usbmuxd y abrir Lente (debe explicar qué falta).

En cada caso: ¿volvió la imagen sola? ¿en cuántos segundos? ¿el mensaje se entendió?

### Fase 5

Las mediciones de la sección 2, con el equipo guiando. Duración total aproximada: una sesión de prueba de resistencia más 15 minutos de delay.

### Fase 6

Instalar desde cero en Fedora siguiendo solo el README publicado. Anotar cada paso donde dudó.

### Fase 7

Grabar un video real de prueba (2 minutos) en la laptop y en Fedora con el flujo final: acceso directo, OBS con escena, LUT y máscara, micrófono BY-V sincronizado. Revisar el archivo con el equipo.

### Prueba final v1.0 (junta las fases 2 a 7, decisión de Manuel del 2026-11-15)

Manuel pidió una sola prueba al final en lugar de una por fase. Unos 20 minutos, con el iPhone. Cada paso dice dónde se hace (📱 iPhone, 💻 PC).

1. 📱 Actualizar la app a **1.0.0**: LocalDevVPN conectada, Safari › `github.com/lionegmanuel/lente/releases` › `Lente-v1.0.0.ipa` › SideStore › My Apps › «+». Opcional: en SideStore › Sources › «+», agregar `https://raw.githubusercontent.com/lionegmanuel/lente/main/sidestore-source.json` (desde ahí las actualizaciones son «Update»).
2. 💻 Windows (laptop): `powershell -ExecutionPolicy Bypass -File D:\Documents\MANUEL\DEV\lente\tools\windows\instalar.ps1`. Tiene que bajar Lente para la PC y crear los tres accesos directos.
3. 📱 Lente abierta y el cable conectado. 💻 Doble clic en **Webcam iPhone**: se abre la ventana «Lente» con la imagen derecha. El título muestra cuadros por segundo, Mbps, temperatura y batería.
4. 💻 Con la ventana «Lente» enfocada, probar y anotar OK o falla: Alt+T y Alt+Shift+T (linterna), Alt+Arriba y Alt+Abajo (zoom), Alt+L (lente 0,5x, 1x, 5x), Alt+Shift+L (frontal), Alt+E, Alt+A, Alt+Y (bloqueos; el registro dice «bloqueado» o «automático»), Alt+O y Alt+Shift+O (pantalla del iPhone en negro y de vuelta; también doble toque en el iPhone), Alt+Shift+R (reinicio del video).
5. 📱 Desenchufar el cable 10 segundos y volver a enchufarlo, y aparte salir de Lente y volver a abrirla: la ventana sigue abierta y la imagen vuelve sola.
6. 💻 OBS: la fuente «Webcam iPh 15 Pro Max» (Captura de ventana) tiene que mostrar la ventana «Lente» de `lente.exe`. Si se ve negra, elegir de nuevo la ventana **«[lente.exe]: Lente»**. Grabar 2 minutos hablando y revisar imagen, LUT y sincronía con el micrófono.
7. 💻 Fedora (PC principal): seguir `docs/MODO_RAPIDO.md` sección 3 (instalar, verificar, «Webcam iPhone»). El registro (`/mnt/d/Temp/lente/webcam_iphone.log`) tiene que decir «modo completo». En OBS, perfil y escena «Lente iPhone». Grabar 2 minutos.
8. Mediciones (tabla de `ESTADO.md`): delay a ojo con el cronómetro de `PRUEBAS_Y_ACEPTACION.md` §2, CPU de la PC durante la grabación (Administrador de tareas o `btop`), batería del iPhone en 30 minutos.

Si algo falla, el acceso directo «Webcam iPhone (modo rápido)» (Windows) o `webcam-iphone --rapido` (Linux) sigue funcionando igual que hasta ahora.

## 4 · Definición de terminado de la versión 1

* Todas las compuertas de `PLAN.md` §6 pasadas y anotadas en `ESTADO.md`.
* Tabla de metas de `PLAN.md` §5 con valores medidos (y explicación si alguna meta se recalibró).
* CI en verde, release `v1.0.0` publicado con los tres artefactos y la fuente de SideStore.
* Manuel grabó un video real con el flujo final en las dos PC.
* Documentación de usuario y del módulo de Velinex actualizada.
