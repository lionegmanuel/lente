#!/usr/bin/env bash
# Arma los paquetes de Lente para la PC a partir de lo que compila el CI.
#
#   bash tools/release/empaquetar_pc.sh <artefactos> <salida>
#
# <artefactos> tiene las carpetas que baja actions/download-artifact:
#   lente-pc-win64-dist/            dist de release/build_windows.sh 64
#   lente-pc-linux-x86_64-dist/     lente-pc-linux-dist.tar.gz (dist de build_linux.sh)
#   scrcpy-server/                  servidor de Android (Android sigue andando igual)
# Deja en <salida>: Lente-PC-windows-x64.zip, Lente-PC-linux-x86_64.tar.gz y sus .sha256.
set -euo pipefail

ART="$(cd "$1" && pwd)"
mkdir -p "$2"
OUT="$(cd "$2" && pwd)"
RAIZ="$(cd "$(dirname "$0")/../.." && pwd)"
VERSION="$(sed -n 's/^# define LENTE_VERSION "\(.*\)"/\1/p' "$RAIZ/app/src/ios/lente_msg.h")"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

notice() {
    cat "$RAIZ/LICENSE" > "$1/LICENSE.txt"
    cat > "$1/NOTICE.txt" <<EOF
Lente ${VERSION}
Copyright (C) 2026 Velinex (https://github.com/lionegmanuel/lente)

Lente is a modified version of scrcpy 4.1
Copyright (C) 2018 Genymobile, Copyright (C) 2018-2026 Romain Vimont
Licensed under the Apache License, Version 2.0 (see LICENSE.txt).

Changes made by Lente to scrcpy 4.1:
 - New iPhone backend (app/src/ios/): usbmux client, minimal XML plist,
   LNTE session opening, reconnection bridge, telemetry in the window title.
 - New options: --ios, --ios-udid, --list-ios-devices, --ios-port,
   --ios-reconnect, --camera-lock, --camera-stabilization, --keyframe-interval.
 - New shortcuts with an iPhone: MOD+o / MOD+Shift+o, MOD+l / MOD+Shift+l,
   MOD+e, MOD+a, MOD+y.
 - New control and device messages in the range 0x60 to 0x6F.
 - The executable is named "lente". The Android behavior is unchanged.
No code from libimobiledevice, libusbmuxd or libplist is included.
EOF
}

leeme() {
    local sistema="$1" destino="$2"
    {
        echo "Lente ${VERSION}: el iPhone como camara de la PC por cable"
        echo
        echo "1. En el iPhone: la app Lente abierta (se instala con SideStore)."
        echo "2. Conectar el iPhone por cable."
        if [[ "$sistema" == windows ]]; then
            echo "3. Doble clic en \"Webcam iPhone.vbs\" (o \"Webcam iPhone (sin girar).vbs\")."
            echo "4. OBS: fuente \"Captura de ventana\" de la ventana \"Lente\" (lente.exe)."
            echo
            echo "Requisito: iTunes descargado de apple.com (trae Apple Mobile Device Service)."
        else
            echo "3. Webcam virtual: lente --ios --v4l2-sink=/dev/video10 --no-playback --no-window"
            echo "   (o el acceso directo \"Webcam iPhone\" que instala tools/linux/instalar.sh)."
            echo "4. OBS: fuente \"Dispositivo de captura de video (V4L2)\" en /dev/video10."
            echo
            echo "Requisitos: usbmuxd y v4l2loopback (tools/linux/instalar.sh los instala)."
        fi
        echo
        echo "Atajos con el iPhone (Alt + tecla): O pantalla negra, Shift+O volver,"
        echo "T linterna, Shift+T apagarla, Arriba/Abajo zoom, L siguiente lente,"
        echo "Shift+L camara frontal, E exposicion, A foco, Y balance de blancos,"
        echo "Shift+R reiniciar el video."
        echo
        echo "Todas las opciones: lente --help. Guia completa: docs/MODO_RAPIDO.md del repositorio."
        echo "Android sigue funcionando igual que scrcpy 4.1 (lente sin --ios)."
    } > "$destino"
}

# Windows
W="$TMP/Lente-PC-windows-x64-v${VERSION}"
mkdir -p "$W"
cp -r "$ART/lente-pc-win64-dist/." "$W/"
mv "$W/scrcpy.exe" "$W/lente.exe"
rm -f "$W/scrcpy-noconsole.vbs"
cp "$ART/scrcpy-server/scrcpy-server" "$W/"
notice "$W"
leeme windows "$W/LEEME.txt"
argumentos='--ios --window-title=Lente --camera-fps=30 --video-bit-rate=24M --ios-reconnect=3600'
# Sin consola, igual que scrcpy-noconsole.vbs de scrcpy: la ventana de video se ve igual.
# Explorer y los accesos directos arrancan en la carpeta del .vbs.
printf 'CreateObject("Wscript.Shell").Run "cmd /c lente.exe %s --capture-orientation=180", 0, false\r\n' \
    "$argumentos" > "$W/Webcam iPhone.vbs"
printf 'CreateObject("Wscript.Shell").Run "cmd /c lente.exe %s", 0, false\r\n' \
    "$argumentos" > "$W/Webcam iPhone (sin girar).vbs"
printf '@echo off\r\ncd /d "%%~dp0"\r\nlente.exe %s --capture-orientation=180 %%*\r\npause\r\n' \
    "$argumentos" > "$W/Webcam iPhone (con consola).cmd"
(cd "$TMP" && zip -qr "$OUT/Lente-PC-windows-x64.zip" "$(basename "$W")")

# Linux
L="$TMP/Lente-PC-linux-x86_64-v${VERSION}"
mkdir -p "$L"
tar -xzf "$ART/lente-pc-linux-x86_64-dist/lente-pc-linux-dist.tar.gz" -C "$TMP"
cp -r "$TMP/dist/." "$L/"
mv "$L/scrcpy" "$L/lente"
cp "$ART/scrcpy-server/scrcpy-server" "$L/"
notice "$L"
leeme linux "$L/LEEME.txt"
tar -C "$TMP" -czf "$OUT/Lente-PC-linux-x86_64.tar.gz" "$(basename "$L")"

cd "$OUT"
for f in Lente-PC-windows-x64.zip Lente-PC-linux-x86_64.tar.gz; do
    sha256sum "$f" > "$f.sha256"
done
ls -l "$OUT"
echo "Version ${VERSION}"
