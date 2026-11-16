#!/usr/bin/env bash
# Lente · instalacion en Linux (cualquier distro), una sola vez
#
#   bash tools/linux/instalar.sh             instala (pide la clave de sudo cuando hace falta)
#   bash tools/linux/instalar.sh --simular   muestra lo que haria, sin tocar el sistema
#   bash tools/linux/instalar.sh --sin-obs   no instala ni configura OBS
#   bash tools/linux/instalar.sh --sin-cliente   no baja Lente para la PC (queda el modo rapido)
#
# Deja lista la camara del iPhone por cable para OBS:
#   1. usbmuxd (habla con el iPhone por USB), herramientas de libimobiledevice, Python 3,
#      FFmpeg con H.264 y v4l2loopback. Recetas: Fedora y derivadas (dnf), Debian, Ubuntu,
#      Mint y derivadas (apt), Arch, CachyOS, Manjaro y derivadas (pacman), openSUSE (zypper).
#   2. Webcam virtual permanente /dev/video10. Si ya existe (la del celular Android), se usa esa.
#   3. Usuario en el grupo video.
#   4. Accesos directos "Webcam iPhone" y "Webcam iPhone (sin girar)" en el menu y el Escritorio,
#      y el comando webcam-iphone.
#   5. OBS Studio (si falta, el Flatpak de Flathub) con el perfil y la escena "Lente iPhone":
#      1080p a 30 cuadros, la camara en /dev/video10 con el LUT, el microfono del sistema y la
#      grabacion con la placa en CQP 18 (configurar_obs.py). No toca otros perfiles ni escenas.
# Se puede volver a correr: no duplica nada.

set -euo pipefail

AQUI="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
TOOLS="$(cd "${AQUI}/.." && pwd)"
NR=10
DISPOSITIVO="/dev/video${NR}"
USUARIO="${USER:-$(id -un)}"
SIMULAR=false
CON_OBS=true
CON_CLIENTE=true
DATOS=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --simular) SIMULAR=true ;;
        --sin-obs) CON_OBS=false ;;
        --sin-cliente) CON_CLIENTE=false ;;
        --datos) DATOS="${2:-}"; shift ;;
        *) echo "Opcion desconocida: $1"; exit 1 ;;
    esac
    shift
done
CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/lente"

GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; GRIS='\033[0;90m'; NC='\033[0m'
paso() { echo ""; echo -e "${YELLOW}[*] $1${NC}"; }
ok() { echo -e "${GREEN}[OK] $1${NC}"; }
aviso() { echo -e "${YELLOW}  $1${NC}"; }
s() {
    if $SIMULAR; then echo -e "      ${GRIS}[simulado] sudo $*${NC}"; return 0; fi
    sudo "$@"
}
escribir() {
    if $SIMULAR; then echo -e "      ${GRIS}[simulado] escribir $1:${NC}"; sed 's/^/        /'; return 0; fi
    sudo tee "$1" >/dev/null
}
# Lo que corre con el usuario (sin sudo) pero cambia algo: en --simular solo se muestra
u() {
    if $SIMULAR; then echo -e "      ${GRIS}[simulado] $*${NC}"; return 0; fi
    "$@"
}
tiene() { command -v "$1" >/dev/null 2>&1; }
ffmpeg_listo() {
    # Output to a variable first: with pipefail, grep -q closing the pipe early (SIGPIPE) reads as a
    # failure. FFmpeg 8 lists the muxer as "video4linux2,v4l2", hence [ ,] before v4l2.
    tiene ffmpeg || return 1
    local lista
    lista="$(ffmpeg -hide_banner -decoders 2>/dev/null)"
    grep -qE '^ *V[^ ]* +h264 ' <<<"$lista" || return 1
    lista="$(ffmpeg -hide_banner -muxers 2>/dev/null)"
    grep -qE '[ ,]v4l2 ' <<<"$lista"
}

echo -e "${CYAN}=================================================================${NC}"
echo -e "${CYAN}   Lente · Webcam iPhone por cable (Linux)${NC}"
$SIMULAR && echo -e "${CYAN}   Modo simulado: no se toca nada del sistema${NC}"
echo -e "${CYAN}=================================================================${NC}"

if [[ $EUID -eq 0 ]]; then
    echo -e "${RED}[ERROR] Correlo con tu usuario, sin sudo (pide la clave cuando hace falta).${NC}"
    exit 1
fi

. /etc/os-release
DISTRO=" ${ID:-} ${ID_LIKE:-} "
KVER="$(uname -r)"
SECURE_BOOT=false
tiene mokutil && mokutil --sb-state 2>/dev/null | grep -qi "enabled" && SECURE_BOOT=true
PLACA="otra"
for d in /sys/bus/pci/devices/*; do
    [[ "$(cat "$d/class" 2>/dev/null)" == 0x03* ]] || continue
    case "$(cat "$d/vendor" 2>/dev/null)" in
        0x1002) PLACA="amd" ;;
        0x10de) [[ "$PLACA" == "amd" ]] || PLACA="nvidia" ;;
        0x8086) [[ "$PLACA" == "otra" ]] && PLACA="intel" ;;
    esac
done
echo "Distro: ${PRETTY_NAME:-$ID} · kernel ${KVER} · placa ${PLACA} · Secure Boot $($SECURE_BOOT && echo activo || echo apagado)"

# 0. Disco de datos (HDD): ahi va todo lo pesado (OBS si hay que instalarlo, grabaciones, registros)
paso "Disco de datos"
if [[ -z "$DATOS" ]] && mountpoint -q /mnt/d 2>/dev/null; then DATOS="/mnt/d"; fi
if [[ -z "$DATOS" || ! -d "$DATOS" ]]; then
    echo -e "${RED}[ERROR] No encuentro el disco de datos montado en /mnt/d.${NC}"
    echo "        Montarlo (ver docs/MODO_RAPIDO.md) o indicar otro: bash instalar.sh --datos /ruta/del/disco"
    $SIMULAR || exit 1
    DATOS="/mnt/d"
fi
FS_DATOS="$(findmnt -no FSTYPE --target "$DATOS" 2>/dev/null || echo desconocido)"
u mkdir -p "${DATOS}/Videos" "${DATOS}/Temp/lente"
u mkdir -p "$CONF_DIR"
if $SIMULAR; then
    echo -e "      ${GRIS}[simulado] escribir ${CONF_DIR}/lente.conf: DATOS=${DATOS}${NC}"
else
    printf 'DATOS=%q\n' "$DATOS" > "${CONF_DIR}/lente.conf"
fi
ok "Disco de datos: ${DATOS} (${FS_DATOS}). Grabaciones en ${DATOS}/Videos, registros en ${DATOS}/Temp/lente"

# 1. Paquetes
paso "Paquetes: usbmuxd, libimobiledevice, Python 3, FFmpeg con H.264 y v4l2loopback"
MODULO_LISTO=false
modinfo v4l2loopback >/dev/null 2>&1 && MODULO_LISTO=true
if tiene dnf; then
    if [[ "$DISTRO" == *" fedora "* ]] && ! rpm -q rpmfusion-free-release >/dev/null 2>&1; then
        # RPM Fusion: FFmpeg completo (el ffmpeg-free de Fedora no trae H.264) y v4l2loopback
        s dnf install -y "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm"
    fi
    s dnf install -y usbmuxd libimobiledevice-utils python3 libva-utils
    ffmpeg_listo || s dnf install -y --allowerasing ffmpeg
    if [[ "$PLACA" == "amd" ]] && ! rpm -q mesa-va-drivers-freeworld >/dev/null 2>&1; then
        # Decodificar H.264 con la placa AMD (Fedora lo saca de Mesa por patentes)
        s dnf install -y --allowerasing mesa-va-drivers-freeworld || aviso "Sin mesa-va-drivers-freeworld: FFmpeg decodifica por procesador (anda igual)."
    fi
    if ! $MODULO_LISTO; then
        s dnf install -y akmod-v4l2loopback v4l2loopback
        if $SECURE_BOOT; then
            LLAVE="/etc/pki/akmods/certs/public_key.der"
            s dnf install -y akmods mokutil openssl
            [[ -f "$LLAVE" ]] || s kmodgenca -a
            if ! mokutil --test-key "$LLAVE" 2>/dev/null | grep -qi "already enrolled"; then
                echo "  Secure Boot activo: elegi una clave corta para aceptar la llave al reiniciar."
                s mokutil --import "$LLAVE"
                aviso "Al reiniciar aparece una pantalla azul (MOK): 'Enroll MOK', 'Continue', 'Yes' y la clave."
            fi
        fi
        s dnf install -y --skip-unavailable "kernel-devel-${KVER}" || true
        s akmods --force --kernels "$KVER" || aviso "akmods no armo el modulo para ${KVER}: sudo dnf upgrade y reiniciar."
    fi
elif tiene apt-get; then
    s apt-get update
    s apt-get install -y usbmuxd libimobiledevice-utils python3 ffmpeg vainfo
    if ! $MODULO_LISTO; then
        s apt-get install -y v4l2loopback-dkms "linux-headers-${KVER}" \
            || s apt-get install -y v4l2loopback-dkms linux-headers-generic
        $SECURE_BOOT && aviso "Secure Boot: DKMS firma el modulo; si pidio una clave, aceptala en la pantalla MOK al reiniciar."
    fi
elif tiene pacman; then
    PAQ=(usbmuxd libimobiledevice python ffmpeg libva-utils)
    if ! $MODULO_LISTO; then
        HEADERS="$(pacman -Qqo "/usr/lib/modules/${KVER}/vmlinuz" 2>/dev/null || echo linux)-headers"
        PAQ+=(v4l2loopback-dkms "$HEADERS")
    fi
    s pacman -S --needed --noconfirm "${PAQ[@]}"
elif tiene zypper; then
    s zypper --non-interactive install usbmuxd imobiledevice-tools python3 ffmpeg libva-utils
    $MODULO_LISTO || s zypper --non-interactive install v4l2loopback-kmp-default \
        || aviso "openSUSE: instalar v4l2loopback a mano (v4l2loopback-kmp-default)."
    ffmpeg_listo || aviso "openSUSE: el FFmpeg oficial no trae H.264. Instalar el de Packman (ver docs/MODO_RAPIDO.md)."
else
    echo -e "${RED}[AVISO] Sin receta para '${ID:-desconocida}'. Instalar a mano: usbmuxd, libimobiledevice (herramientas),"
    echo -e "        python3, ffmpeg con H.264 y v4l2loopback (modulo del kernel). Despues volver a correr este script.${NC}"
fi
# Lo que se descargo para instalar no queda ocupando el disco del sistema
if tiene dnf; then s dnf clean packages >/dev/null || true
elif tiene apt-get; then s apt-get clean || true
elif tiene pacman; then s pacman -Sc --noconfirm >/dev/null || true
elif tiene zypper; then s zypper --non-interactive clean || true
fi
if $SIMULAR || ffmpeg_listo; then ok "Paquetes listos (sistema: no se pueden instalar en otro disco; cache de descargas limpia)"; else
    echo -e "${RED}[ERROR] FFmpeg sin decodificador H.264 o sin salida v4l2. Ver docs/MODO_RAPIDO.md, seccion Linux.${NC}"
    exit 1
fi

# 2. Webcam virtual /dev/video10
paso "Webcam virtual ${DISPOSITIVO}"
if [[ -e "$DISPOSITIVO" ]]; then
    ok "Ya existe: $(cat /sys/class/video4linux/video${NR}/name 2>/dev/null || echo "$DISPOSITIVO") (se usa esa, no se toca)"
elif grep -qsE "^options +v4l2loopback .*video_nr=([0-9,]*,)?${NR}(,|[[:space:]]|$)" /etc/modprobe.d/*.conf; then
    aviso "Ya hay configuracion con video_nr=${NR}: se carga el modulo."
    s modprobe v4l2loopback || aviso "No cargo ahora: reiniciar (y con Secure Boot, aceptar la llave en la pantalla MOK)."
elif grep -qsE "^options +v4l2loopback" /etc/modprobe.d/*.conf; then
    aviso "Hay otra configuracion de v4l2loopback sin video${NR}:"
    grep -sE "^options +v4l2loopback" /etc/modprobe.d/*.conf | sed 's/^/        /'
    aviso "Agregar ${NR} a video_nr (y un card_label) en ese archivo, reiniciar y volver a correr este script."
else
    echo "v4l2loopback" | escribir /etc/modules-load.d/lente-v4l2loopback.conf
    echo "options v4l2loopback devices=1 video_nr=${NR} card_label=\"Lente iPhone\" exclusive_caps=1" \
        | escribir /etc/modprobe.d/lente-v4l2loopback.conf
    if [[ -d /sys/module/v4l2loopback ]]; then
        s modprobe -r v4l2loopback || aviso "v4l2loopback esta en uso (cerrar OBS): queda lista al reiniciar."
    fi
    s modprobe v4l2loopback || aviso "No cargo ahora: reiniciar (y con Secure Boot, aceptar la llave en la pantalla MOK)."
fi
[[ -e "$DISPOSITIVO" ]] && ok "Webcam virtual lista en ${DISPOSITIVO}"

# 3. Permisos
paso "Permisos"
REINICIAR_SESION=false
if id -nG "$USUARIO" | tr ' ' '\n' | grep -qx video; then
    ok "${USUARIO} ya esta en el grupo video"
else
    s usermod -aG video "$USUARIO"
    REINICIAR_SESION=true
    ok "${USUARIO} agregado al grupo video (vale desde el proximo inicio de sesion)"
fi

# 4. Accesos directos
paso "Accesos directos"
if $SIMULAR; then
    echo -e "      ${GRIS}[simulado] comando ~/.local/bin/webcam-iphone y accesos 'Webcam iPhone' y 'Webcam iPhone (sin girar)' en el menu y el Escritorio${NC}"
else
chmod +x "${AQUI}"/*.sh
mkdir -p "$HOME/.local/bin" "$HOME/.local/share/applications"
ln -sf "${AQUI}/webcam_iphone.sh" "$HOME/.local/bin/webcam-iphone"
ESCRITORIO="$(xdg-user-dir DESKTOP 2>/dev/null || true)"
[[ -n "$ESCRITORIO" && "$ESCRITORIO" != "$HOME" ]] || ESCRITORIO="$HOME/Desktop"
crear_lanzador() {
    local archivo="$1" nombre="$2" extra="$3"
    cat > "$HOME/.local/share/applications/${archivo}" <<EOF
[Desktop Entry]
Type=Application
Name=${nombre}
Comment=Lente: camara del iPhone por cable para OBS (un clic prende, otro apaga)
Exec=bash "${AQUI}/webcam_iphone.sh"${extra}
Icon=camera-web
Terminal=false
Categories=AudioVideo;Video;
EOF
    chmod +x "$HOME/.local/share/applications/${archivo}"
    if [[ -d "$ESCRITORIO" ]]; then
        cp "$HOME/.local/share/applications/${archivo}" "$ESCRITORIO/${archivo}"
        chmod +x "$ESCRITORIO/${archivo}"
        # GNOME pide marcarlo como confiable; en KDE alcanza con que sea ejecutable
        tiene gio && gio set "$ESCRITORIO/${archivo}" metadata::trusted true 2>/dev/null || true
    fi
}
crear_lanzador "lente-webcam-iphone.desktop" "Webcam iPhone" ""
crear_lanzador "lente-webcam-iphone-sin-girar.desktop" "Webcam iPhone (sin girar)" " --sin-girar"
tiene update-desktop-database && update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
fi
ok "Menu y Escritorio: 'Webcam iPhone' y 'Webcam iPhone (sin girar)'. En terminal: webcam-iphone"

# 4b. Lente para la PC (cliente completo): en el disco de datos, verificado por SHA256
if $CON_CLIENTE; then
    paso "Lente para la PC (cliente completo)"
    URL="https://github.com/lionegmanuel/lente/releases/latest/download"
    DEST="${DATOS}/lente-pc"
    if $SIMULAR; then
        echo -e "      ${GRIS}[simulado] bajar ${URL}/Lente-PC-linux-x86_64.tar.gz a ${DEST}${NC}"
    elif TMPD="$(mktemp -d -p "${DATOS}/Temp/lente")" \
            && curl -fsSL --retry 3 -o "${TMPD}/Lente-PC-linux-x86_64.tar.gz" "${URL}/Lente-PC-linux-x86_64.tar.gz" \
            && curl -fsSL --retry 3 -o "${TMPD}/Lente-PC-linux-x86_64.tar.gz.sha256" "${URL}/Lente-PC-linux-x86_64.tar.gz.sha256" \
            && (cd "$TMPD" && sha256sum -c Lente-PC-linux-x86_64.tar.gz.sha256 >/dev/null); then
        mkdir -p "$DEST"
        tar -xzf "${TMPD}/Lente-PC-linux-x86_64.tar.gz" -C "$DEST"
        CARPETA="$(tar -tzf "${TMPD}/Lente-PC-linux-x86_64.tar.gz" | sed -n '1s|/.*||p')"
        ln -sfn "${DEST}/${CARPETA}" "${DEST}/actual"
        ln -sf "${DEST}/actual/lente" "$HOME/.local/bin/lente"
        rm -rf "$TMPD"
        ok "$("${DEST}/actual/lente" --version 2>/dev/null | head -n1) en ${DEST}/actual (comando: lente)"
    else
        [[ -n "${TMPD:-}" ]] && rm -rf "$TMPD"
        aviso "No se pudo bajar Lente para la PC (sin internet o sin release publicado): queda el modo rapido."
    fi
fi

# 5. OBS
if $CON_OBS; then
    paso "OBS Studio"
    # All installations (system, user and extra ones like "datos"); into a variable, not grep -q in a pipe
    APPS_FLATPAK="$(tiene flatpak && flatpak list --app --columns=application 2>/dev/null || true)"
    if grep -qx com.obsproject.Studio <<<"$APPS_FLATPAK" || tiene obs; then
        ok "OBS ya esta instalado"
    elif tiene flatpak && [[ "$FS_DATOS" =~ ^(ext4|btrfs|xfs|f2fs)$ ]]; then
        # Flatpak de Flathub (el mismo OBS en cualquier distro, con todos los codecs) instalado
        # en el disco de datos: una instalacion de Flatpak propia en ${DATOS}/flatpak
        escribir /etc/flatpak/installations.d/datos.conf <<EOF
[Installation "datos"]
Path=${DATOS}/flatpak
DisplayName=Disco de datos
StorageType=harddisk
EOF
        s mkdir -p "${DATOS}/flatpak"
        s flatpak remote-add --installation=datos --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
        s flatpak install --installation=datos -y --noninteractive flathub com.obsproject.Studio
        ok "OBS instalado en el disco de datos (${DATOS}/flatpak). Aparece en el menu despues de cerrar sesion y volver a entrar."
    elif tiene flatpak || tiene dnf || tiene apt-get || tiene pacman || tiene zypper; then
        # Flatpak no funciona sobre NTFS (necesita permisos de Linux): OBS va por la distro, al disco del sistema
        [[ "$FS_DATOS" =~ ^(ext4|btrfs|xfs|f2fs)$ ]] || aviso "El disco de datos es ${FS_DATOS}: Flatpak no se puede instalar ahi. OBS va por la distro (unos 200 MB en el sistema)."
        if tiene dnf; then
            s dnf install -y obs-studio obs-studio-plugin-x264 || s dnf install -y obs-studio
        elif tiene apt-get; then
            s apt-get install -y obs-studio
        elif tiene pacman; then
            s pacman -S --needed --noconfirm obs-studio
        elif tiene zypper; then
            s zypper --non-interactive install obs-studio
        else
            aviso "Instalar OBS Studio a mano (obsproject.com) y volver a correr este script."
        fi
    else
        aviso "Instalar OBS Studio a mano (obsproject.com) y volver a correr este script."
    fi

    paso "OBS: perfil y escena 'Lente iPhone'"
    OBS_ARGS=(--videos "${DATOS}/Videos" --datos "$DATOS")
    if $SIMULAR; then
        python3 "${AQUI}/configurar_obs.py" "${OBS_ARGS[@]}" --simular || aviso "No se pudo simular la configuracion de OBS."
    elif pgrep -x obs >/dev/null 2>&1; then
        aviso "OBS esta abierto: cerrarlo y correr: python3 \"${AQUI}/configurar_obs.py\" --videos \"${DATOS}/Videos\" --datos \"${DATOS}\""
    else
        python3 "${AQUI}/configurar_obs.py" "${OBS_ARGS[@]}" || aviso "OBS sin configurar: ver el mensaje de arriba y docs/MODO_RAPIDO.md."
    fi
fi

echo ""
echo -e "${CYAN}=================================================================${NC}"
echo -e "${GREEN}   Instalacion completa${NC}"
echo -e "${CYAN}=================================================================${NC}"
if $SECURE_BOOT && [[ ! -e "$DISPOSITIVO" ]]; then
    echo "Reiniciar una vez y aceptar la llave en la pantalla azul (MOK)."
elif [[ ! -e "$DISPOSITIVO" ]]; then
    echo "Reiniciar una vez para que aparezca ${DISPOSITIVO}."
elif $REINICIAR_SESION; then
    echo "Cerrar sesion y volver a entrar una vez (grupo video)."
fi
echo "Prueba de punta a punta (iPhone conectado y Lente abierta): bash \"${AQUI}/verificar.sh\""
echo "Uso diario: abrir Lente en el iPhone, conectar el cable, clic en 'Webcam iPhone' y abrir OBS (perfil y escena 'Lente iPhone')."
