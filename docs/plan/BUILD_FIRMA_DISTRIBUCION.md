# Lente · Repositorio, compilación, firma y distribución

Restricción del proyecto: **sin Mac y sin pagar.** Todo lo de Apple se compila en GitHub Actions y se instala con un Apple ID gratis.

## 1 · Repositorio

Carpeta local: `D:\Documents\MANUEL\DEV\lente` (esta). Ya contiene `docs/plan/` y `CLAUDE.md`. Armado en la Fase 0:

```bash
cd /d/Documents/MANUEL/DEV/lente
git init -b main
git remote add upstream https://github.com/Genymobile/scrcpy.git
git fetch upstream --tags
git checkout -B main v4.1          # trae scrcpy 4.1; docs/ y CLAUDE.md quedan (scrcpy no tiene esas rutas)
mkdir -p ios tools
cp docs/plan/plantillas/project.yml ios/project.yml
cp docs/plan/plantillas/usbmux_probe.py tools/usbmux_probe.py
cp docs/plan/plantillas/lente-ios.yml .github/workflows/lente-ios.yml
git add CLAUDE.md docs ios tools .github/workflows/lente-ios.yml
git commit -m "Lente: plan técnico, plantillas y base scrcpy 4.1"
```

* Repositorio independiente (no «fork» de GitHub), con la historia de scrcpy y el remoto `upstream` para traer versiones nuevas.
* Publicación en GitHub **solo después de que Manuel confirme D2**: `gh repo create lionegmanuel/lente --public --source . --remote origin --push` (cuenta ya autenticada en la laptop). Con el nombre definitivo (D3) si ya está.
* Workflows de scrcpy que vengan en `.github/workflows/`: revisar y desactivar los que no apliquen (no deben publicar nada con la marca scrcpy).
* Ramas: `main` estable; una rama por fase (`fase-1-servidor-ios`, etc.) que se fusiona al pasar la compuerta. Tags `vX.Y.Z` disparan releases.
* Actualizar scrcpy: `git fetch upstream --tags` y rebase o merge del tag nuevo; correr todas las pruebas; anotar en `RIESGOS_Y_DECISIONES.md`.

## 2 · Integración continua (GitHub Actions)

Repositorio público: minutos ilimitados en macOS, Linux y Windows.

| Workflow | Runner | Hace |
|---|---|---|
| `lente-ios.yml` | `macos-15` | XcodeGen, pruebas XCTest en simulador, IPA sin firmar, artefacto; en tag, adjunta la IPA al release y actualiza la fuente de SideStore |
| `lente-linux.yml` | `ubuntu-24.04` | Dependencias, `meson setup`, `ninja`, `meson test`, tarball |
| `lente-windows.yml` | `ubuntu-24.04` | Compilación cruzada MinGW con los scripts de `release/` de scrcpy, ZIP win64 |
| `lente-release.yml` | `ubuntu-24.04` | En tag: junta los tres artefactos, crea el release y publica `sidestore-source.json` |

Plantilla de arranque del de iOS: `plantillas/lente-ios.yml`. Fijar versiones de acciones y de Xcode; anotar en `ESTADO.md` la versión de Xcode usada.

### IPA sin firmar

```bash
xcodegen generate --spec ios/project.yml
xcodebuild -project ios/Lente.xcodeproj -scheme Lente -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' \
  -archivePath build/Lente.xcarchive archive \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""
mkdir -p build/Payload
cp -R build/Lente.xcarchive/Products/Applications/Lente.app build/Payload/
(cd build && zip -qr Lente.ipa Payload)
```

SideStore firma la IPA en el iPhone con el Apple ID de Manuel.

## 3 · Instalación gratis en el iPhone (SideStore)

**Regla:** las credenciales del Apple ID las escribe solo Manuel. Ningún agente pide, guarda ni teclea contraseñas, códigos ni datos de cuenta (memoria «celular automatizado sin registros»).

Verificar en la Fase 0 el procedimiento vigente en la documentación oficial de SideStore (`docs.sidestore.io`) y escribirlo en este documento paso a paso con capturas, porque cambia con las versiones de iOS. Esquema esperado:

1. En la PC: la herramienta oficial de instalación de SideStore (hoy «iLoader», para Windows y Linux) instala SideStore en el iPhone por el cable y genera el archivo de emparejamiento.
2. En el iPhone: Ajustes › Privacidad y seguridad › **Modo desarrollador** activado (iOS 16 o superior), reinicio y confirmación.
3. Confiar en el perfil de desarrollador (Ajustes › General › VPN y gestión de dispositivos).
4. Instalar desde la App Store la VPN local gratuita que pide SideStore para renovar sin la PC (hoy «LocalDevVPN»; verificar).
5. En SideStore: agregar la fuente de Lente (URL del `sidestore-source.json` del repositorio) e instalar Lente.
6. Renovación: SideStore renueva las apps antes de los 7 días. Dejar armada una automatización de Atajos de iOS (por ejemplo, todos los días a las 9 o al conectar el cargador) que ejecute la renovación de SideStore. Verificar el nombre exacto de la acción.
7. Actualizaciones: cuando sale una versión nueva, aparece en SideStore y se actualiza desde el iPhone. No hace falta la PC.

Límites del Apple ID gratis, a respetar:

* Máximo 3 apps instaladas por fuera de la App Store (SideStore cuenta como una). Lente es la segunda.
* Máximo 10 identificadores de app nuevos cada 7 días: **nunca cambiar el Bundle ID** después de la Fase 0.
* Si pasan 7 días sin renovar, la app no abre hasta renovar (se renueva desde SideStore, sin reinstalar).

Plan B si SideStore deja de funcionar con alguna versión de iOS: Sideloadly (gratis, de código cerrado) desde Windows, renovando cada 7 días por cable. Plan C: cuenta paga.

## 4 · Fuente de SideStore

Archivo `sidestore-source.json` en la raíz del repositorio, servido por la URL «raw» de GitHub. Formato de fuente de AltStore/SideStore (verificar campos vigentes). Plantilla: `plantillas/sidestore-source.json`. El workflow de release agrega cada versión con su `downloadURL` (asset del release), tamaño, fecha y versión mínima de iOS.

## 5 · Releases

| Artefacto | Contenido |
|---|---|
| `lente-win64-vX.Y.Z.zip` | `lente.exe`, DLL, `adb` y archivos de scrcpy para Android, `lente-iphone.cmd` de ejemplo, LICENSE, NOTICE, README |
| `lente-linux-x86_64-vX.Y.Z.tar.gz` | Binario, servidor Android, script de dependencias para Fedora y Ubuntu, README |
| `Lente-vX.Y.Z.ipa` | App del iPhone sin firmar |

Versionado semántico. La versión del protocolo LNTE es independiente y figura en las notas del release.

### Dependencias en Linux

* `usbmuxd` (en Fedora viene en el repositorio oficial; se activa solo al conectar el iPhone).
* FFmpeg con decodificación H.264 y HEVC: en Fedora, `ffmpeg-free` no trae todos los códecs; usar `ffmpeg-libs` de RPM Fusion. Verificar en la Fedora 44 de Manuel y documentar.
* SDL3, y `v4l2loopback` para la cámara virtual (ya instalado por `instalar_en_linux.sh` del módulo de webcam de Velinex).

### Dependencias en Windows

* Apple Mobile Device Service: app **Apple Devices** de Microsoft Store (gratis, oficial). El cliente detecta si falta y lo explica.

## 6 · Camino pago y App Store (cuando Manuel decida lanzar)

* Apple Developer Program, USD 99 por año. Firma de un año, TestFlight y App Store.
* Firma sin Mac: certificado de distribución y perfil generados por la API de App Store Connect, guardados como secretos de GitHub; subida con una clave de API desde el runner macOS.
* Revisión de Apple: ya hay apps del mismo tipo publicadas (Camo, EpocCam), pero la app depende de un cliente de escritorio: la ficha tiene que explicarlo y enlazar la descarga del cliente. Hace falta política de privacidad (puede ser una página estática en GitHub Pages).
* El código no cambia; cambia solo el workflow de firma. Mientras tanto, todo sigue gratis con SideStore.
