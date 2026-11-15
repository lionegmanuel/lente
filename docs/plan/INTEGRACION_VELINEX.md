# Lente · Integración en el flujo de Velinex (Fase 7)

Objetivo: que Manuel use el iPhone como usaba el POCO: un doble clic y grabar en OBS, en la laptop (Windows hoy, Fedora después) y en la PC principal con Fedora.

## 1 · Dónde vive cada cosa

| Qué | Dónde |
|---|---|
| Código de Lente | `D:\Documents\MANUEL\DEV\lente` |
| Binario en Windows | `D:\Programs\lente\` (igual que `D:\Programs\scrcpy\`). Nunca en C: |
| Binario en Fedora | Donde instala hoy `instalar_en_linux.sh` a scrcpy; seguir el mismo patrón |
| Lanzadores, accesos directos y guías | `D:\Documents\MANUEL\VELINEX\Contenido y Marketing\Scrcpy - Webcam Celular\iphone\` |
| Plantilla del micrófono | `D:\Documents\MANUEL\VELINEX\Contenido y Marketing\Plantilla Microfono OBS\` |
| Temporales, pruebas y builds locales | `D:\Temp\operius\lente\` |

Lo de scrcpy para Android (lanzadores, accesos «Webcam Celular (scrcpy)») **no se borra ni se modifica**: queda para cuando Manuel use un Android.

## 2 · Conexión física (laptop Acer Nitro AN515-57)

* iPhone al **USB-C** (Thunderbolt 4): carga mejor mientras graba. Cable de la caja (USB 2), alcanza para 4K60.
* Receptor del Boya BY-V a un **USB-A** con el adaptador USB-A macho a USB-C hembra. Nunca al jack de 3,5 mm (calidad de llamada, medido el 2026-11-15).
* En Windows: app Apple Devices instalada (Apple Mobile Device Service).

## 3 · Lanzadores

Mismo comportamiento y estilo que `webcam_launcher.ps1` y `webcam_launcher.sh` del módulo (leerlos antes):

* `iphone/webcam_iphone.ps1` y `iphone/webcam_iphone.cmd` (Windows): verifica Apple Mobile Device Service, lista el iPhone, avisa si la app no está abierta, muestra modelo, batería y temperatura, y lanza `lente.exe --ios --window-title="Webcam iPhone" --camera-size=1920x1080 --camera-fps=60 --video-codec=h264 --video-bit-rate=16M`. Parámetros opcionales: `-4K`, `-Lente 0.5|1|5|frontal`, `-ListCameras`.
* `iphone/webcam_iphone.sh` (Fedora): lo mismo, con `--v4l2-sink=/dev/video10 --no-playback` por defecto y `--solo-ventana` como en el lanzador actual. Verifica `usbmuxd` y `v4l2loopback`.
* Accesos directos «Webcam iPhone» en el escritorio: sumarlos a `crear_acceso_directo_windows.ps1` y `crear_acceso_directo_linux.sh` sin quitar los de scrcpy.
* `instalar_en_linux.sh` y `verificar_webcam_linux.sh`: sumar `usbmuxd`, el binario de Lente y la comprobación del iPhone, sin romper lo de Android.

## 4 · OBS

### Windows (laptop)

* Fuente nueva «Webcam iPhone»: Captura de ventana, ventana «Webcam iPhone», ejecutable `lente.exe`, método Windows Graphics Capture.
* Copiar los filtros de «Webcam Xiaomi Poco» (corrección de color, LUT `Studio_Cinema_HerasHiguera_kitchen.cube` al 0,903, enfoque, máscara de círculo) y agregarla a las escenas donde está la del POCO.
* Se edita el JSON de la colección con OBS cerrado, igual que `aplicar_plantilla_mic.py`. El LUT y la corrección de color se recalibran a ojo con Manuel, porque el color del iPhone no es el del POCO (en `LUTs/` hay un generador por lugar).
* La fuente «Mic Celular (Boya M1)» queda como está (sirve solo con el POCO). El micrófono con el iPhone es `Mic/Aux` = Boya BY-V con su plantilla.

### Fedora

* La fuente de OBS que hoy lee `/dev/video10` sigue igual: Lente escribe en el mismo dispositivo. Opcional: renombrar la etiqueta de v4l2loopback a «iPhone Webcam» en `/etc/modprobe.d/v4l2loopback.conf`.
* PC principal: micrófono Fifine en `Mic/Aux`, sin cambios.
* Laptop con Fedora: BY-V con `aplicar_plantilla_mic.py` (ver la plantilla).

## 5 · Sincronización de imagen y sonido

El video llega con el delay de la cámara (meta: unos 70 ms) y el micrófono USB casi sin delay, así que el audio va adelantado. Procedimiento:

1. Grabar en OBS 10 segundos con 3 aplausos frente a la cámara.
2. Medir la diferencia entre el pico del aplauso en el audio y el cuadro donde se juntan las manos (script en `tools/` o a mano en DaVinci).
3. Poner esa diferencia en Propiedades avanzadas de audio › Sincronización de `Mic/Aux`, en milisegundos.
4. Anotar el valor en el README de la plantilla del micrófono y en la guía del módulo.

## 6 · Documentación a actualizar

* `Scrcpy - Webcam Celular/README.md`: sección «iPhone con Lente».
* `GUIA_RAPIDA_LINUX.md`: uso diario con iPhone.
* `Plantilla Microfono OBS/README.md`: desfase medido.
* Memoria de Claude `iphone-webcam-por-cable`: estado final.

## 7 · Reglas de Velinex que aplican

* Nada se guarda en C:.
* Procesamiento de video e IA con GPU (GTX 1650 en la laptop, RX 9060 XT en Fedora), con el tope del 80% de `tope80.py` para cualquier proceso pesado (OCR de mediciones, por ejemplo).
* Procesos se detienen solo por PID, nunca por nombre (hay varias sesiones en paralelo).
* Sin copias de respaldo propias; lo temporal se borra al terminar.
* Cero guiones largos y medios en todo texto, código y comentario.
