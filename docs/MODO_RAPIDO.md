# Lente · Modo rápido: el iPhone como cámara de OBS por cable (Windows y Linux)

Guía completa para dejar andando la cámara del iPhone en OBS, en Windows y en cualquier Linux. Sirve para Manuel y para cualquier agente del equipo: tiene los pasos exactos, cómo comprobar cada uno y qué hacer si algo falla.

**Desde la versión 1.0 (2026-11-15):** los accesos directos «Webcam iPhone» usan **Lente para la PC** (el cliente completo, basado en scrcpy: reconexión sola, atajos de cámara y telemetría en el título) y, si no arranca, pasan solos al modo rápido de esta guía. Los instaladores (`tools/windows/instalar.ps1`, `tools/linux/instalar.sh`) bajan Lente para la PC del último release y verifican su SHA256. Atajos con el iPhone (Alt + tecla): O pantalla negra y Shift+O volver, T y Shift+T linterna, Arriba y Abajo zoom, L lente siguiente y Shift+L frontal, E exposición, A foco, Y balance de blancos, Shift+R reiniciar el video. Opciones: `lente --help`. El modo rápido queda como respaldo: «Webcam iPhone (modo rápido)» en Windows y `webcam-iphone --rapido` en Linux.

**Qué es el modo rápido:** un puente para grabar ya, mientras se termina Lente para la PC (la Fase 2 del plan). La app del iPhone es la definitiva; en la PC, en lugar del cliente basado en scrcpy, corre `tools/lente_rapido.py`, que recibe el video por el cable y lo entrega con FFmpeg:

| Sistema | Cómo lo toma OBS | Acceso directo |
|---|---|---|
| Windows | **Captura de ventana** de la ventana «Lente» (ffplay) | «Webcam iPhone» en el Escritorio |
| Linux (cualquier distro) | **Dispositivo de captura de video (V4L2)** en `/dev/video10`, la webcam virtual | «Webcam iPhone» en el menú y el Escritorio |

Estado al 2026-11-15: probado con el iPhone 15 Pro Max de Manuel en Windows 10 (imagen, reconexión al desenchufar y OBS aprobados por Manuel). En Linux, probado en Ubuntu 26.04 con un iPhone simulado (los 180 cuadros llegan idénticos y reconecta solo) y con un OBS simulado (perfil y escena generados y verificados). Falta lo que solo se puede hacer en la PC: la primera prueba con el iPhone real (paso 6 de la sección Linux) y abrir OBS por primera vez con la escena generada.

**Punto de partida en la PC con Linux de Manuel:** nada armado. Nunca se usó ahí una cámara de celular: no hay webcam virtual ni OBS configurado para cámara. El instalador hace todo desde cero.

---

## 1. El iPhone (igual para Windows y Linux)

Ya está hecho en el iPhone de Manuel; se repite solo en un iPhone nuevo.

1. La app **Lente** instalada con SideStore (`docs/plan/BUILD_FIRMA_DISTRIBUCION.md` §3). Versión actual: `v0.2.0-fase1` en `github.com/lionegmanuel/lente/releases`.
2. **Cada 7 días** hay que renovar la firma. Se automatiza una sola vez con Atajos y después es solo (pendiente de Manuel): pasos en [MANTENIMIENTO_IPHONE_Y_PC.md](MANTENIMIENTO_IPHONE_Y_PC.md). A mano: LocalDevVPN conectada, SideStore › My Apps › tocar el contador de días. Si pasan 7 días sin renovar, Lente no abre hasta renovar (no se pierde nada).
3. Para usarla: **Lente abierta en pantalla** y el iPhone conectado por cable. La app no deja que se apague la pantalla mientras está abierta. Si se va a otra app o se bloquea, la cámara se corta y vuelve sola al abrir Lente de nuevo.
4. **La primera vez en una PC nueva**, el iPhone pregunta «¿Confiar en esta computadora?»: tocar **Confiar** y poner el código.

**Orientación:** con el iPhone horizontal y el cable hacia la PC (como lo usa Manuel), la imagen sale girada 180 grados y el acceso directo «Webcam iPhone» la endereza. Si el iPhone se pone con el cable al otro lado, usar «Webcam iPhone (sin girar)».

---

## 2. Windows

### Una sola vez

1. Instalar **iTunes descargado de Apple**: `apple.com/itunes/download/win64`. No el de Microsoft Store ni la app Apple Devices. Trae «Apple Mobile Device Service», que es lo que habla con el iPhone por el cable; iTunes no tiene que estar abierto.
2. Tener el repositorio en la PC (en la laptop de Manuel: `D:\Documents\MANUEL\DEV\lente`). En otra PC: `git clone https://github.com/lionegmanuel/lente.git` en un disco que no sea C:.
3. En PowerShell:
   ```powershell
   powershell -ExecutionPolicy Bypass -File D:\Documents\MANUEL\DEV\lente\tools\windows\instalar.ps1
   ```
   Revisa el servicio de Apple, Python y ffplay (si falta FFmpeg, lo instala con winget) y crea «Webcam iPhone» y «Webcam iPhone (sin girar)» en el Escritorio.

### Uso diario

1. Lente abierta en el iPhone y el cable conectado.
2. Doble clic en **Webcam iPhone**: se abre la ventana «Lente» con la cámara.
3. OBS: la fuente **Captura de ventana** de **«[lente.exe]: Lente»** (con el modo rápido, «[ffplay.exe]: Lente»). En la laptop ya existe: «Webcam iPh 15 Pro Max», con el LUT HerasHiguera kitchen al 90%.

Desde el 2026-11-16 la ventana «Lente» abre **fija en 1920x1080, sin bordes y fuera de la vista**: a la izquierda de todo el escritorio, medido al abrirla, con uno, dos o los monitores que haya y de cualquier resolución. No ocupa ninguna pantalla y OBS la sigue capturando en vivo (probado en la laptop). OBS captura la ventana al tamaño que tiene, así que graba siempre 1080p pixel a pixel, sin escalar. La imagen se mira en la vista previa de OBS; Alt+Tab enfoca la ventana para los atajos. Otras formas: `webcam_iphone.ps1 -Visible` (misma ventana en la esquina del monitor principal) y `-VentanaLibre` (la ventana común de antes).

Nunca minimizar la ventana: Windows deja de dibujar las ventanas minimizadas y OBS recibe negro (pasó el 2026-11-16). Tapada por otras ventanas o fuera de la vista sí se graba. Si se corta el cable, la ventana queda abierta y la imagen vuelve sola al reconectar. Para terminar, cerrar la ventana «Lente» (Alt+F4).

### Configuración de OBS para la máxima calidad (laptop, 2026-11-16)

* Captura de ventana: método **Windows 10 (1903 y posteriores)**, sin capturar el cursor. La fuente va ajustada al lienzo (Transformar › Ajustar a la pantalla, 1920x1080): si la ventana cambia de tamaño, la imagen igual llena el cuadro.
* Grabación: Salida › modo Avanzado › Grabación › codificador **NVIDIA NVENC H.264**, control de tasa **CQP 16**, preset **P7**, dos pasadas a resolución completa, perfil high. Antes estaba en CBR sin bitrate (2.500 kbps), que ensuciaba cualquier imagen, y el 2026-11-15 en CQP 18 con P5.
* Video: 1920x1080 a 30 cuadros. El iPhone manda 30 cuadros y 24 Mbps por defecto (`--fps 30 --mbps 24`), igual que graba OBS: a 30 cuadros la cámara junta más luz por cuadro y hay menos ruido adentro de casa.

---

## 3. Linux (cualquier distro)

Probado con recetas para **Fedora y derivadas** (dnf), **Debian, Ubuntu, Mint y derivadas** (apt), **Arch, CachyOS, Manjaro y derivadas** (pacman) y **openSUSE** (zypper). En otra distro, el instalador dice qué paquetes poner a mano y el resto es igual.

Lo que hace falta y para qué:

| Pieza | Para qué |
|---|---|
| `usbmuxd` | Habla con el iPhone por el cable (el equivalente del servicio de Apple de Windows) |
| `libimobiledevice` (herramientas) | Diagnóstico y emparejamiento (`idevice_id -l`, `idevicepair`) |
| Python 3.8 o superior | Corre `lente_rapido.py` y `configurar_obs.py` (solo biblioteca estándar, sin pip) |
| FFmpeg **con decodificador H.264** y salida `v4l2` | Decodifica el video y lo escribe en la webcam virtual. En Fedora, el `ffmpeg-free` oficial no trae H.264: se usa el de RPM Fusion |
| `v4l2loopback` | La webcam virtual `/dev/video10` que lee OBS |
| OBS Studio | Si no está, el instalador pone el Flatpak de Flathub (si hay Flatpak) o el de la distro |

### Todo lo pesado va al disco de datos (HDD)

Regla de Manuel: lo que pesa va al disco secundario, no al del sistema. En la PC con Fedora ese disco está montado en **`/mnt/d`** (el «D:» de Windows, con la misma estructura; ver `VELINEX/DEV & INFRAESTRUCTURA IA/Pase de Windows a Linux.md`).

| Qué | Dónde queda |
|---|---|
| Repositorio de Lente | `/mnt/d/Documents/MANUEL/DEV/lente` |
| OBS, si hay que instalarlo | Flatpak de Flathub en una instalación propia del disco de datos, `/mnt/d/flatpak` (se registra en `/etc/flatpak/installations.d/datos.conf`). Si el disco es NTFS, Flatpak no funciona ahí: OBS va por la distro, al sistema, unos 200 MB, y el instalador lo avisa |
| Grabaciones de OBS | `/mnt/d/Videos` |
| LUT | Se usa directo desde el repo VELINEX en `/mnt/d`, sin copias |
| Registros y fotos de prueba | `/mnt/d/Temp/lente` |
| Paquetes del sistema (usbmuxd, FFmpeg, módulo de la webcam virtual) | En el sistema: Linux no deja instalarlos en otro disco. Son unos cientos de MB; el instalador limpia la caché de descargas al terminar |
| Configuración de OBS y de Lente | En la carpeta del usuario (archivos de texto chicos): `~/.config/obs-studio` o `~/.var/app/com.obsproject.Studio`, y `~/.config/lente/lente.conf` (dice dónde está el disco de datos) |

Si el disco de datos no está montado, el instalador se frena con un error en lugar de llenar el disco del sistema. Para otro punto de montaje: `instalar.sh --datos /ruta/del/disco`.

### Paso a paso

1. **Cerrar OBS** si está abierto y comprobar el disco de datos: `ls /mnt/d/Documents/MANUEL` tiene que mostrar las carpetas de siempre.
2. **Tener el repositorio en el disco de datos.** Si ya está en `/mnt/d/Documents/MANUEL/DEV/lente`, hacer `git pull` ahí. Si no:
   ```bash
   mkdir -p /mnt/d/Documents/MANUEL/DEV
   git clone https://github.com/lionegmanuel/lente.git /mnt/d/Documents/MANUEL/DEV/lente
   ```
   En adelante, `LENTE=/mnt/d/Documents/MANUEL/DEV/lente`.
3. **Ver qué va a hacer, sin tocar nada:**
   ```bash
   bash "$LENTE/tools/linux/instalar.sh" --simular
   ```
4. **Instalar** (con el usuario normal, sin sudo; pide la clave cuando hace falta):
   ```bash
   bash "$LENTE/tools/linux/instalar.sh"
   ```
   * Instala los paquetes de la tabla. En Fedora agrega RPM Fusion si falta, cambia `ffmpeg-free` por `ffmpeg` solo si el que hay no trae H.264, y en placas AMD suma `mesa-va-drivers-freeworld` para decodificar con la placa.
   * **Webcam virtual:** si `/dev/video10` ya existe (por ejemplo, la del instalador del celular Android de VELINEX), la usa tal cual y no toca su configuración. Si no existe, crea `/dev/video10` «Lente iPhone» y la deja cargada en cada arranque. Si hay otra configuración de `v4l2loopback` sin el 10, no la pisa: avisa qué agregar.
   * **Secure Boot:** en Fedora firma el módulo con una llave propia y pide una clave corta; al reiniciar aparece una pantalla azul (MOK): *Enroll MOK* · *Continue* · *Yes* · la clave.
   * Agrega el usuario al grupo `video` y crea los accesos directos **Webcam iPhone** y **Webcam iPhone (sin girar)** en el menú y el Escritorio, más el comando `webcam-iphone`.
   * **OBS:** lo instala si falta y crea el perfil y la colección de escenas **«Lente iPhone»** y los deja activos (`tools/linux/configurar_obs.py`). No borra ni cambia otros perfiles o escenas. Detalle en «OBS en Linux», abajo.
5. **Reiniciar o cerrar sesión** si el instalador lo pide al final (grupo `video`, módulo nuevo o llave MOK).
6. **Prueba de punta a punta**, con el iPhone conectado y Lente abierta:
   ```bash
   bash "$LENTE/tools/linux/verificar.sh"
   ```
   Revisa la instalación y el disco de datos, que `usbmuxd` vea el iPhone, manda la cámara a `/dev/video10`, lee un cuadro real de ahí (lo mismo que hace OBS) y guarda la foto en `/mnt/d/Temp/lente/`. Tiene que terminar en «Todo bien». Sin el iPhone: `verificar.sh --sin-iphone` revisa solo la instalación.
7. **Abrir OBS:** tiene que abrir con el perfil y la escena «Lente iPhone» y mostrar la cámara. Si abre con otro, elegir «Lente iPhone» en los menús **Perfil** y **Colección de escenas**.

### Uso diario

1. Lente abierta en el iPhone y el cable conectado.
2. Clic en **Webcam iPhone**: aparece el aviso «Cámara del iPhone prendida en /dev/video10». No abre ninguna ventana: la imagen va directo a la webcam virtual.
3. Abrir OBS (perfil y escena «Lente iPhone»).
4. Para apagarla: otro clic en **Webcam iPhone** (o `webcam-iphone --apagar`).

Sigue andando aunque se desenchufe el cable o se cierre Lente en el iPhone: al volver, la imagen vuelve sola. Orden recomendado: primero la cámara y después OBS.

**Cuadros por segundo:** 30, igual que en la laptop (decisión de Manuel, 2026-11-15). El perfil «Lente iPhone» viene a 30 y el lanzador lee los cuadros del perfil activo de OBS (de la distro o Flatpak) con un máximo de 30, para gastar lo menos posible (batería y calor del iPhone, procesador de la PC): con un perfil a 60, como `VELINEX_PRO`, el iPhone igual manda 30. Si no los encuentra, usa 30. Para forzar otro valor: `webcam-iphone --fps 60`.

Opciones: `webcam-iphone --help`. Las principales: `--sin-girar`, `--fps N`, `--ventana` (muestra una ventana «Lente» para mirar sin OBS), `--estado`, `--apagar`. Variables: `LENTE_V4L2` (otro dispositivo), `LENTE_MBPS` (tasa, 24 por defecto). Registro: `/mnt/d/Temp/lente/webcam_iphone.log`.

### OBS en Linux

El instalador lo deja hecho con `tools/linux/configurar_obs.py`. Se puede volver a correr solo, con OBS cerrado: `python3 "$LENTE/tools/linux/configurar_obs.py" --datos /mnt/d --videos /mnt/d/Videos` (`--simular` muestra qué haría). Sirve para el OBS de la distro y para el Flatpak, y configura los dos si están los dos.

| Qué | Cómo queda |
|---|---|
| Perfil y colección | **«Lente iPhone»**, activos al abrir OBS. Los demás perfiles y escenas quedan como estaban |
| Video | 1920x1080 a 30 cuadros |
| Escena «iPhone» | Fuente **«Webcam iPhone»**: Dispositivo de captura de video (V4L2) en `/dev/video10`, ajustada a toda la pantalla, sin búfer (menos delay) y con reinicio solo si deja de llegar imagen |
| Color | Filtro **Apply LUT** con `Studio_Cinema_HerasHiguera_kitchen.cube` al 90%, igual que la laptop. Lo busca en el repo VELINEX, primero en el disco de datos (`/mnt/d/Documents/MANUEL/VELINEX/...`) y lo usa desde ahí. Solo si lo encuentra fuera del disco de datos lo copia a la carpeta de OBS (`luts/`) |
| Audio | Mic/Aux = el micrófono por defecto del sistema (en la PC principal, el Fifine: dejarlo como entrada por defecto en la configuración de sonido) |
| Micrófono | Si el receptor Boya BY-V está enchufado (en la PC con Fedora, por el adaptador USB común a USB-C), Mic/Aux queda en ese micrófono con los 6 filtros de la plantilla de Velinex, igual que la laptop. Si no está, el micrófono por defecto sin filtros: enchufarlo y volver a correr `configurar_obs.py` con OBS cerrado (2026-11-16) |
| Grabación | Máxima calidad, igual que la laptop (2026-11-16). Placa AMD o Intel: **VA-API H.264, CQP 16**. NVIDIA: **NVENC H.264, CQP 16**, preset P7, dos pasadas completas. Sin placa: x264 CRF 16. Formato MP4 híbrido (OBS 30.2 o superior; si no, MKV). Carpeta: `/mnt/d/Videos` (el disco de datos) |

* **Si dice «LUT: no encontrado»:** el repo VELINEX no está en esa PC. Traerlo (o copiar solo el `.cube` desde `Contenido y Marketing/Scrcpy - Webcam Celular/LUTs/kitchen/`) y correr `python3 "$LENTE/tools/linux/configurar_obs.py" --lut /ruta/Studio_Cinema_HerasHiguera_kitchen.cube`.
* **Si OBS no puede grabar con la placa AMD:** en Fedora falta H.264 en VA-API (el instalador pone `mesa-va-drivers-freeworld`). Con el OBS Flatpak, cambiar en Ajustes › Salida › Grabación el codificador a «x264» como alternativa y avisar.
* **Para usar la cámara en otra escena:** agregar una fuente **Dispositivo de captura de video (V4L2)** con el dispositivo `/dev/video10`, o copiar «Webcam iPhone» y pegarla como referencia.
* OBS Flatpak ve `/dev/video10` sin permisos extra.

### Si algo falla

| Síntoma | Causa y arreglo |
|---|---|
| `verificar.sh`: «usbmuxd no ve el iPhone» | Desbloquear el iPhone y tocar **Confiar**. Desenchufar y volver a enchufar (usbmuxd arranca solo al conectar). Probar otro cable o puerto USB. Ver `idevice_id -l`. Si sigue: `sudo systemctl restart usbmuxd`. |
| «conexion rechazada: abri la app en el iPhone» | Lente no está abierta en pantalla. Abrirla; el modo rápido conecta solo. |
| El iPhone no pregunta «Confiar» y no conecta | `idevicepair pair` con el iPhone desbloqueado, tocar Confiar, y `idevicepair validate` tiene que decir SUCCESS. |
| «No existe /dev/video10» | Reiniciar después de instalar. Si sigue: `sudo modprobe v4l2loopback`. «Key was rejected by service» = Secure Boot: volver a correr `instalar.sh` y aceptar la llave en la pantalla MOK al reiniciar. «not found» = falta el módulo para ese kernel: en Fedora `sudo akmods --force` y reiniciar; en apt/pacman, reinstalar `v4l2loopback-dkms` con los headers del kernel. |
| «Sin permiso en /dev/video10» | Falta cerrar sesión después de instalar (grupo `video`). |
| FFmpeg sin H.264 | Fedora: `sudo dnf install --allowerasing ffmpeg` (RPM Fusion). openSUSE: FFmpeg de Packman. |
| OBS no muestra la cámara | Prender primero la cámara y después abrir OBS. Con OBS abierto: doble clic en la fuente «Webcam iPhone» y Aceptar (la reabre). Revisar que el perfil y la escena sean «Lente iPhone». |
| OBS abre con otra escena | Menús **Perfil** y **Colección de escenas** › «Lente iPhone». Si no aparecen: `python3 "$LENTE/tools/linux/configurar_obs.py"` con OBS cerrado. |
| La imagen sale dada vuelta | Usar el otro acceso directo («sin girar» o el normal). |
| Imagen congelada | `webcam-iphone --apagar` y prender de nuevo. Ver `/mnt/d/Temp/lente/webcam_iphone.log`. |
| «No encuentro el disco de datos montado en /mnt/d» | Montar el HDD (`lsblk -f` para ver el disco; guía en `VELINEX/DEV & INFRAESTRUCTURA IA/Pase de Windows a Linux.md`) y volver a correr `instalar.sh`. Si está montado en otro lado: `instalar.sh --datos /ruta`. |
| Lente no abre en el iPhone | Pasaron 7 días: renovar en SideStore (sección 1). |

---

## 4. Para el agente del equipo

* **Archivos:** `tools/lente_rapido.py` (el puente, Windows y Linux), `tools/linux/configurar_obs.py` (OBS en Linux), `tools/usbmux_probe.py` (diagnóstico de usbmux: `--listar`, `--conectar 27183 --lnte "camera_fps=30" --demux` valida el formato y mide cuadros por segundo y tasa), `tools/linux/instalar.sh`, `tools/linux/webcam_iphone.sh`, `tools/linux/verificar.sh`, `tools/windows/instalar.ps1`.
* **Cómo funciona:** `lente_rapido.py` abre una sesión con la app del iPhone por usbmux (puerto 27183 del iPhone), recibe H.264 con el formato de scrcpy 4.1 y le pasa el video a ffplay (ventana, Windows) o a ffmpeg (`-f v4l2 /dev/video10`, Linux). Protocolo en `docs/plan/ARQUITECTURA_Y_PROTOCOLO.md`.
* **Diagnóstico rápido en Linux:** `python3 tools/usbmux_probe.py --listar` (tiene que mostrar el iPhone por USB), `webcam-iphone --estado`, `tail -f /mnt/d/Temp/lente/webcam_iphone.log`, `bash tools/linux/verificar.sh`.
* **Reglas:** el Apple ID, contraseñas y códigos los escribe solo Manuel. Si ya existe una configuración de `v4l2loopback`, no pisarla (el instalador no la toca). En OBS, no borrar perfiles ni escenas de Manuel: lo de Lente vive en «Lente iPhone». Detener procesos solo por PID (el lanzador guarda el suyo en `$XDG_RUNTIME_DIR/lente-webcam-iphone.pid`). Nada pesado ni temporal en el disco del sistema, ni en Windows ni en Linux: todo al disco de datos (`/mnt/d`). No avanzar fases de Lente sin que Manuel lo pida.
* **Al terminar:** anotar el resultado en `docs/plan/ESTADO.md` (una línea con fecha: distro, qué se instaló, salida de `verificar.sh`) y hacer commit.
