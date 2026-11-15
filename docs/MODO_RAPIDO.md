# Lente · Modo rápido: el iPhone como cámara de OBS por cable (Windows y Linux)

Guía completa para dejar andando la cámara del iPhone en OBS, en Windows y en cualquier Linux. Sirve para Manuel y para cualquier agente del equipo: tiene los pasos exactos, cómo comprobar cada uno y qué hacer si algo falla.

**Qué es el modo rápido:** un puente para grabar ya, mientras se termina Lente para la PC (la Fase 2 del plan). La app del iPhone es la definitiva; en la PC, en lugar del cliente basado en scrcpy, corre `tools/lente_rapido.py`, que recibe el video por el cable y lo entrega con FFmpeg:

| Sistema | Cómo lo toma OBS | Acceso directo |
|---|---|---|
| Windows | **Captura de ventana** de la ventana «Lente» (ffplay) | «Webcam iPhone» en el Escritorio |
| Linux (cualquier distro) | **Dispositivo de captura de video (V4L2)** en `/dev/video10`, la webcam virtual | «Webcam iPhone» en el menú y el Escritorio |

Estado al 2026-11-15: probado con el iPhone 15 Pro Max de Manuel en Windows 10 (imagen, reconexión al desenchufar y OBS aprobados por Manuel). En Linux, probado de punta a punta en Ubuntu 26.04 con un iPhone simulado (los 180 cuadros llegan idénticos y reconecta solo); falta la primera prueba con el iPhone real en Fedora, que es el paso 6 de la sección Linux.

---

## 1. El iPhone (igual para Windows y Linux)

Ya está hecho en el iPhone de Manuel; se repite solo en un iPhone nuevo.

1. La app **Lente** instalada con SideStore (`docs/plan/BUILD_FIRMA_DISTRIBUCION.md` §3). Versión actual: `v0.2.0-fase1` en `github.com/lionegmanuel/lente/releases`.
2. **Cada 7 días** hay que renovar: en el iPhone, LocalDevVPN conectada, SideStore › My Apps › tocar el contador de días. Si pasan 7 días sin renovar, Lente no abre hasta renovar (no se pierde nada).
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
3. OBS: la fuente **Captura de ventana** de **«[ffplay.exe]: Lente»** (en la laptop ya existe: «Webcam iPh 15 Pro Max», con el LUT HerasHiguera kitchen al 90%).

La ventana no se puede minimizar (OBS no captura ventanas minimizadas), pero puede quedar detrás de otras. Si se corta el cable, la ventana queda abierta y la imagen vuelve sola al reconectar. Para terminar, cerrar la ventana «Lente».

### Configuración de OBS para la mejor calidad (laptop, 2026-11-15)

* Captura de ventana: método **Windows 10 (1903 y posteriores)**, sin capturar el cursor.
* Grabación: Salida › modo Avanzado › Grabación › codificador **NVIDIA NVENC H.264**, control de tasa **CQP 18**, preset P5, perfil high. Antes estaba en CBR sin bitrate (2.500 kbps), que ensuciaba cualquier imagen.
* Video: 1920x1080 a 30 cuadros. El iPhone manda 30 cuadros y 24 Mbps por defecto (`--fps 30 --mbps 24`), igual que graba OBS: a 30 cuadros la cámara junta más luz por cuadro y hay menos ruido adentro de casa.

---

## 3. Linux (cualquier distro)

Probado con recetas para **Fedora y derivadas** (dnf), **Debian, Ubuntu, Mint y derivadas** (apt), **Arch, CachyOS, Manjaro y derivadas** (pacman) y **openSUSE** (zypper). En otra distro, el instalador dice qué paquetes poner a mano y el resto es igual.

Lo que hace falta y para qué:

| Pieza | Para qué |
|---|---|
| `usbmuxd` | Habla con el iPhone por el cable (el equivalente del servicio de Apple de Windows) |
| `libimobiledevice` (herramientas) | Diagnóstico y emparejamiento (`idevice_id -l`, `idevicepair`) |
| Python 3.8 o superior | Corre `lente_rapido.py` (solo biblioteca estándar, sin pip) |
| FFmpeg **con decodificador H.264** y salida `v4l2` | Decodifica el video y lo escribe en la webcam virtual. En Fedora, el `ffmpeg-free` oficial no trae H.264: se usa el de RPM Fusion |
| `v4l2loopback` | La webcam virtual `/dev/video10` que lee OBS |

### Paso a paso

1. **Cerrar OBS.**
2. **Tener el repositorio.** Si el disco de datos está montado en `/mnt/d` con la misma estructura que en Windows, el repo ya está en `/mnt/d/Documents/MANUEL/DEV/lente` (hacer `git pull` ahí). Si no:
   ```bash
   git clone https://github.com/lionegmanuel/lente.git ~/lente
   ```
   En adelante, `LENTE` es esa carpeta (por ejemplo `LENTE=/mnt/d/Documents/MANUEL/DEV/lente`).
3. **Ver qué va a hacer, sin tocar nada:**
   ```bash
   bash "$LENTE/tools/linux/instalar.sh" --simular
   ```
4. **Instalar** (con el usuario normal, sin sudo; pide la clave cuando hace falta):
   ```bash
   bash "$LENTE/tools/linux/instalar.sh"
   ```
   * Instala los paquetes de la tabla. En Fedora agrega RPM Fusion si falta, cambia `ffmpeg-free` por `ffmpeg` solo si el que hay no trae H.264, y en placas AMD suma `mesa-va-drivers-freeworld` para decodificar con la placa.
   * **Webcam virtual:** si `/dev/video10` ya existe (en la PC con Fedora la dejó el instalador del celular Android, como «Celular Webcam»), la usa tal cual y no toca su configuración. Si no existe, crea `/dev/video10` «Lente iPhone» y la deja cargada en cada arranque. Si hay otra configuración de `v4l2loopback` sin el 10, no la pisa: avisa qué agregar.
   * **Secure Boot:** en Fedora firma el módulo con una llave propia y pide una clave corta; al reiniciar aparece una pantalla azul (MOK): *Enroll MOK* · *Continue* · *Yes* · la clave.
   * Agrega el usuario al grupo `video` y crea los accesos directos **Webcam iPhone** y **Webcam iPhone (sin girar)** en el menú y el Escritorio, más el comando `webcam-iphone`.
5. **Reiniciar o cerrar sesión** si el instalador lo pide al final (grupo `video`, módulo nuevo o llave MOK).
6. **Prueba de punta a punta**, con el iPhone conectado y Lente abierta:
   ```bash
   bash "$LENTE/tools/linux/verificar.sh"
   ```
   Revisa la instalación, que `usbmuxd` vea el iPhone, manda la cámara a `/dev/video10`, lee un cuadro real de ahí (lo mismo que hace OBS) y guarda la foto en `/mnt/d/Temp/lente/` (o en `/tmp/lente/` si no hay `/mnt/d`). Tiene que terminar en «Todo bien». Sin el iPhone: `verificar.sh --sin-iphone` revisa solo la instalación.
7. **OBS** (ver abajo).

### Uso diario

1. Lente abierta en el iPhone y el cable conectado.
2. Clic en **Webcam iPhone**: aparece el aviso «Cámara del iPhone prendida en /dev/video10». No abre ninguna ventana: la imagen va directo a la webcam virtual.
3. Abrir OBS.
4. Para apagarla: otro clic en **Webcam iPhone** (o `webcam-iphone --apagar`).

Sigue andando aunque se desenchufe el cable o se cierre Lente en el iPhone: al volver, la imagen vuelve sola. Orden recomendado: primero la cámara y después OBS.

**Cuadros por segundo:** el lanzador lee los cuadros del perfil activo de OBS (OBS de la distro o Flatpak) y pide esos mismos al iPhone; si no los encuentra, usa 30. El perfil `VELINEX_PRO` de la PC con Fedora está a 60. Para forzar: `webcam-iphone --fps 30`.

Opciones: `webcam-iphone --help`. Las principales: `--sin-girar`, `--fps N`, `--ventana` (muestra una ventana «Lente» para mirar sin OBS), `--estado`, `--apagar`. Variables: `LENTE_V4L2` (otro dispositivo), `LENTE_MBPS` (tasa, 24 por defecto). Registro: `~/.cache/lente/webcam_iphone.log`.

### OBS en Linux

* **En la PC con Fedora de Manuel no hay que crear nada:** la fuente `Webcam Xiaomi` de la colección `VELINEX_PRO` ya lee `/dev/video10` con los filtros, el LUT y la máscara circular. Con el modo rápido prendido, muestra el iPhone. Se le puede cambiar el nombre a «Webcam iPhone».
* En otra PC: **Fuentes › + › Dispositivo de captura de video (V4L2)** › dispositivo **/dev/video10** (el nombre que se ve es «Celular Webcam» o «Lente iPhone») › resolución 1920x1080. Marcar «Reiniciar al no recibir cuadros» si aparece la opción.
* **Filtros recomendados para el iPhone** (lo mismo que se dejó en Windows): **Apply LUT** con `Studio_Cinema_HerasHiguera_kitchen.cube` al 90%. Los LUT están en `VELINEX/Contenido y Marketing/Scrcpy - Webcam Celular/LUTs/kitchen/`. El filtro «Color Correction» de la fuente se ajustó para el POCO: apagarlo (ojo cerrado) y ver si hace falta.
* **Calidad de grabación con placa AMD:** Ajustes › Salida › modo Avanzado › Grabación › codificador **FFmpeg VAAPI H.264** (o «AMD HW H.264 (VA-API)»), control de tasa **CQP**, **QP 18** (el perfil viene en 20). Con NVIDIA: NVENC CQP 18, igual que la laptop.
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
| OBS no muestra la cámara | Prender primero la cámara y después abrir OBS. Con OBS abierto: doble clic en la fuente y Aceptar (la reabre). |
| La imagen sale dada vuelta | Usar el otro acceso directo («sin girar» o el normal). |
| Imagen congelada | `webcam-iphone --apagar` y prender de nuevo. Ver `~/.cache/lente/webcam_iphone.log`. |
| Lente no abre en el iPhone | Pasaron 7 días: renovar en SideStore (sección 1). |

---

## 4. Para el agente del equipo

* **Archivos:** `tools/lente_rapido.py` (el puente, Windows y Linux), `tools/usbmux_probe.py` (diagnóstico de usbmux: `--listar`, `--conectar 27183 --lnte "camera_fps=30" --demux` valida el formato y mide cuadros por segundo y tasa), `tools/linux/instalar.sh`, `tools/linux/webcam_iphone.sh`, `tools/linux/verificar.sh`, `tools/windows/instalar.ps1`.
* **Cómo funciona:** `lente_rapido.py` abre una sesión con la app del iPhone por usbmux (puerto 27183 del iPhone), recibe H.264 con el formato de scrcpy 4.1 y le pasa el video a ffplay (ventana, Windows) o a ffmpeg (`-f v4l2 /dev/video10`, Linux). Protocolo en `docs/plan/ARQUITECTURA_Y_PROTOCOLO.md`.
* **Diagnóstico rápido en Linux:** `python3 tools/usbmux_probe.py --listar` (tiene que mostrar el iPhone por USB), `webcam-iphone --estado`, `tail -f ~/.cache/lente/webcam_iphone.log`, `bash tools/linux/verificar.sh`.
* **Reglas:** el Apple ID, contraseñas y códigos los escribe solo Manuel. No tocar la configuración de `v4l2loopback` del celular Android si ya existe (el instalador no la toca). Detener procesos solo por PID (el lanzador guarda el suyo en `$XDG_RUNTIME_DIR/lente-webcam-iphone.pid`). Nada de archivos temporales en el disco del sistema de Windows. No avanzar fases de Lente sin que Manuel lo pida.
* **Al terminar:** anotar el resultado en `docs/plan/ESTADO.md` (una línea con fecha: distro, qué se instaló, salida de `verificar.sh`) y hacer commit.
