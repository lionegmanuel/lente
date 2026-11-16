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
