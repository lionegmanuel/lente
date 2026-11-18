# UPDATES · Lente

Contexto entre sesiones y entre computadoras. Se actualiza solo cuando Manuel lo pide. Se guardan los últimos 3 días; el estado técnico completo está en `docs/plan/ESTADO.md`.

## 2026-11-15

### Fases 0 a 7 y release v1.0.1 (laptop con Windows)

- **Fase 0 y 1:** SideStore con el Apple ID de siempre, Lente instalada en el iPhone 15 Pro Max (iOS 26.6) y video 1920x1080 a 60 cuadros por el cable, aprobado por Manuel en ffplay.
- **Fases 2 a 7:** backend del iPhone en el cliente de scrcpy 4.1 (`app/src/ios/`), controles y telemetría, reconexión, paquetes para Windows y Linux, fuente de SideStore y lanzadores «Webcam iPhone» con respaldo al modo rápido. Todo en verde en CI, pero sin probar con el iPhone real.
- **Releases:** `v1.0.0` (app 1.0.0 y PC) y `v1.0.1` (solo PC: arreglo del cierre en Windows sin iPhone, lanzadores e instalador de Windows).
- **Pendiente:** la prueba final con el iPhone (`docs/plan/PRUEBAS_Y_ACEPTACION.md`, «Prueba final v1.0») y las mediciones de delay, CPU y batería.

## 2026-11-16

### Revisión de punta a punta en la PC con Fedora 44

- **Cliente de Linux 1.0.1:** corre tal cual en Fedora. Con el iPhone simulado graba 1920x1080 y escribe en `/dev/video10`, y la imagen leída de ahí es la correcta. CPU a 1080p30: modo completo 5% de un núcleo, modo rápido 6% (de 12).
- **Arreglos en Linux** (commit `88e1dd60`): `instalar.sh` y `verificar.sh` daban FFmpeg 8 por incompleto y cortaban la instalación; el lanzador esperaba siempre 20 s y su registro quedaba vacío (ahora prende en 1 s); los cuadros salen del perfil de OBS con un máximo de 30; el registro tiene tope de 1 MB y nunca va al disco del sistema; `--simular` ya no crea los accesos directos.
- **Regla nueva de Manuel:** consumir siempre la menor cantidad de recursos y, si hace falta disco, solo el HDD secundario.

---

### Instalación en Fedora y problema del cable

- **Instalado en Fedora:** Manuel corrió `instalar.sh` y `verificar.sh --sin-iphone` da «Todo bien». Lente para la PC 1.0.1 en `/mnt/d/lente-pc` (comando `lente`), OBS Flatpak con el perfil y la escena «Lente iPhone» activos (30 cuadros, VA-API, LUT al 90%). El perfil `VELINEX_PRO` sigue igual y se elige desde el menú Perfil.
- **Cable:** el «OTG» que probó Manuel era una memoria USB de 64 GB y la PC nunca vio el iPhone. La placa ASUS PRIME B650M-A II no tiene USB-C atrás (solo el conector para un USB-C frontal) y en el gabinete XYZ Airone 60 no aparece ningún USB-C. Manuel compra hoy un **cable USB-A a USB-C de datos**.
- **Commits:** `88e1dd60` y `8b000f95`, todo en `main` y sincronizado con GitHub.

---

### Paso a la laptop con Windows (tormenta)

Manuel sigue desde la laptop porque hay tormenta y hoy no usa la PC de escritorio. Va a probar la app completa en Windows y hacer los ajustes en el iPhone.

**Para retomar en la laptop:**

1. `git pull` en `D:\Documents\MANUEL\DEV\lente` (todo quedó en `main`).
2. 📱 Lente en el iPhone tiene que estar en **1.0.0**. Si sigue la de la Fase 1: LocalDevVPN conectada, Safari › `github.com/lionegmanuel/lente/releases` › `Lente-v1.0.0.ipa` › SideStore. **Lente y SideStore vencen el 2026-11-22.**
3. 💻 Si en la laptop no está Lente para la PC 1.0.1: `powershell -ExecutionPolicy Bypass -File D:\Documents\MANUEL\DEV\lente\tools\windows\instalar.ps1`.
4. Seguir los pasos 3 a 6 de «Prueba final v1.0» (`docs/plan/PRUEBAS_Y_ACEPTACION.md`): ventana «Lente» con la imagen derecha y la telemetría en el título, los atajos, desenchufar y volver a enchufar, y OBS grabando 2 minutos.
5. Anotar en `docs/plan/ESTADO.md` lo que ande y lo que falle. Las mediciones van a la tabla de Mediciones.

**Queda para después, en Fedora:** el paso 7 de la prueba final, con el cable nuevo, `verificar.sh` y OBS «Lente iPhone».

---

### Prueba final en la laptop, calidad máxima y app 1.0.2

- **Cable:** el de cargador Motorola USB-A a USB-C pasa datos y el iPhone se ve. El adaptador «OTG» (USB-A macho a USB-C hembra) no sirve para el iPhone (ni siquiera carga), pero sí para el receptor Boya BY-V (48 kHz).
- **Prueba final en Windows aprobada por Manuel:** app 1.0.2, 1920x1080 a 30 cuadros, LUT al 90%, Boya sin saturar. Detalle en `docs/plan/ESTADO.md`.
- **Windows:** la ventana «Lente» tiene la imagen fija en 1920x1080 con barra de título en la esquina del monitor principal; se tapa con cualquier ventana y OBS la sigue grabando. Minimizada o maximizada, no (límite de Windows). OBS en CQP 16, P7, dos pasadas; fuente «Webcam iPh» (escena FullCam) con LUT y ajustada al lienzo; obs-websocket activado.
- **App del iPhone 1.0.2** (release `v1.0.2`): pantalla negra sola a los 20 s transmitiendo, bloqueo normal esperando la computadora. iOS no deja la cámara con el iPhone bloqueado. SideStore renovado hoy con «Refresh All»: vence alrededor del 2026-11-23.
- **Linux:** `configurar_obs.py` con CQP 16 y micrófono Boya (plantilla) o Fifine (filtros de `VELINEX_PRO`); `--ventana` igual que Windows. Auditado en WSL con el iPhone simulado.
- **Commits:** del `b11cb817` al de esta entrada, todo en `main`.

**Para retomar en Fedora:** seguir «Primera grabación en la PC con Fedora» de `docs/MODO_RAPIDO.md` (7 pasos: pull de los dos repos, elegir micrófono, `configurar_obs.py`, iPhone con Confiar, `verificar.sh`, Webcam iPhone y OBS, aplauso para el desfase).

## 2026-11-18

### Lente en la laptop con Linux: se replica la PC sin cambios (laptop con Windows)

- **Contexto:** el `git pull` trajo los commits del 2026-11-17 hechos en la PC con Fedora (`751abaac` y `90c16831`): iPhone real en verde, H.265 a 40 Mbps con exposición y balance fijos, LUT `HerasHiguera_room`, audio a 320 kbps y `configurar_obs.py` sin pisar el micrófono de `VELINEX_PRO`. En la PC la app quedó funcionando y probada con video grabado.
- **Pedido de Manuel:** que la laptop (Acer Nitro AN515-57: i5-11400H, Intel UHD + GTX 1650, SSD de 256 GB y HDD de 1 TB) funcione en Linux igual que la PC, sin diferencias ni decisiones propias del agente.
- **Qué se hizo:** se revisó el plan de la laptop en la migración única (`D:\Temp\migracion-master\v08\LEEME_VERTICAL.md`): se formatean los dos discos, Fedora 44 KDE en el SSD, el HDD en ext4 «Datos» montado en `/mnt/d` (igual que la PC) y `OPTIMIZAR_FEDORA.sh` instala el driver de NVIDIA con la llave MOK. Con eso, el código actual de Lente (commit `90c16831`) ya cubre la laptop: simulado en WSL con la Intel y la GTX 1650 con su driver, `configurar_obs.py` deja OBS en NVENC H.264 CQP 16, P7 y dos pasadas (lo mismo que OBS en Windows) con el mismo perfil, LUT, 30 cuadros y `/mnt/d/Videos` que la PC, e `instalar.sh` instala lo mismo que en la PC. Un intento previo de adaptar los scripts (D: en NTFS, Intel por defecto, LUT `kitchen`) se descartó y se deshizo entero: no quedó nada de eso.
- **Decisiones de Manuel:** no tocar nada de la PC con Fedora (queda completa) ni de Windows (se sigue trabajando ahí hasta formatear la laptop y pasar todo a Linux).
- **Archivos tocados:** solo este `UPDATES.md`.
- **Dato a tener en cuenta:** la vertical 08 dice «OBS del RPM (no el Flatpak)» para la laptop, y en la PC está el Flatpak. A Lente le da igual: `instalar.sh` ve que OBS ya está instalado y lo configura.

**Para retomar en la laptop, después de la migración (vertical 08):**

1. 💻 `git pull` de `lente` y `VELINEX` en `/mnt/d/Documents/MANUEL/`.
2. 💻 `bash /mnt/d/Documents/MANUEL/DEV/lente/tools/linux/instalar.sh`; reiniciar o cerrar sesión si lo pide.
3. 📱 Lente abierta en el iPhone y el cable. La primera vez en esa computadora, tocar **Confiar**.
4. 💻 `bash /mnt/d/Documents/MANUEL/DEV/lente/tools/linux/verificar.sh` tiene que terminar en «Todo bien».
5. 🎬 Clic en **Webcam iPhone**, abrir OBS y grabar con un aplauso para medir el desfase.

**Alerta activa:** Lente y SideStore se renovaron el 2026-11-16 y vencen alrededor del 2026-11-23. Renovar antes en SideStore (Refresh All, con LocalDevVPN conectada).
