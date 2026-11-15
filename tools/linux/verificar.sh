#!/usr/bin/env bash
# Lente · verificacion en Linux, de punta a punta
#
#   bash tools/linux/verificar.sh               iPhone conectado por cable y Lente abierta en pantalla
#   bash tools/linux/verificar.sh --sin-iphone  revisa solo la instalacion
#
# Revisa paquetes, webcam virtual, permisos y accesos directos. Con el iPhone, manda 10 s de
# camara a /dev/video10, lee un cuadro real de ahi (lo mismo que hace OBS) y guarda la foto.

set -uo pipefail

AQUI="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
TOOLS="$(cd "${AQUI}/.." && pwd)"
DISPOSITIVO="${LENTE_V4L2:-/dev/video10}"
CON_IPHONE=true
[[ "${1:-}" == "--sin-iphone" ]] && CON_IPHONE=false
if [[ -d /mnt/d/Temp ]]; then SALIDA="/mnt/d/Temp/lente"; else SALIDA="${TMPDIR:-/tmp}/lente"; fi
mkdir -p "$SALIDA"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
FALLAS=0
bien() { echo -e "${GREEN}[OK]${NC} $1"; }
mal() { echo -e "${RED}[FALLA]${NC} $1"; FALLAS=$((FALLAS + 1)); }
nota() { echo -e "${YELLOW}[INFO]${NC} $1"; }

echo "== Instalacion"
PY="$(command -v python3 || true)"
if [[ -n "$PY" ]] && "$PY" -c 'import sys; sys.exit(sys.version_info < (3, 8))'; then
    bien "Python $("$PY" -c 'import platform; print(platform.python_version())')"
else
    mal "Falta Python 3.8 o superior"
fi
if command -v ffmpeg >/dev/null; then
    if ffmpeg -hide_banner -decoders 2>/dev/null | grep -qE '^ *V[^ ]* +h264 '; then bien "FFmpeg decodifica H.264"; else mal "FFmpeg sin H.264 (Fedora: sudo dnf install --allowerasing ffmpeg de RPM Fusion)"; fi
    if ffmpeg -hide_banner -muxers 2>/dev/null | grep -qE ' v4l2 '; then bien "FFmpeg escribe en V4L2"; else mal "FFmpeg sin salida v4l2"; fi
else
    mal "Falta ffmpeg"
fi
if command -v usbmuxd >/dev/null || [[ -x /usr/sbin/usbmuxd || -x /usr/bin/usbmuxd ]]; then bien "usbmuxd instalado"; else mal "Falta usbmuxd"; fi
if [[ -e "$DISPOSITIVO" ]]; then
    bien "Webcam virtual ${DISPOSITIVO}: $(cat "/sys/class/video4linux/$(basename "$DISPOSITIVO")/name" 2>/dev/null)"
    if [[ -w "$DISPOSITIVO" ]]; then bien "Permiso de escritura en ${DISPOSITIVO}"; else mal "Sin permiso en ${DISPOSITIVO}: cerrar sesion y volver a entrar (grupo video)"; fi
else
    mal "No existe ${DISPOSITIVO}: correr tools/linux/instalar.sh y reiniciar"
fi
if [[ -f "$HOME/.local/share/applications/lente-webcam-iphone.desktop" ]]; then bien "Acceso directo 'Webcam iPhone'"; else mal "Falta el acceso directo: correr tools/linux/instalar.sh"; fi

if $CON_IPHONE; then
    echo ""
    echo "== iPhone"
    if LISTA="$("$PY" "${TOOLS}/usbmux_probe.py" --listar 2>&1)" && grep -q "USB" <<<"$LISTA"; then
        bien "iPhone por USB: $(grep USB <<<"$LISTA" | head -n1)"
    else
        mal "usbmuxd no ve el iPhone: ${LISTA}. Desbloquearlo, tocar 'Confiar' y probar otro cable o puerto."
    fi
    if command -v idevicepair >/dev/null; then
        nota "Emparejamiento: $(idevicepair validate 2>&1 | head -n1)"
    fi

    echo ""
    echo "== Camara a ${DISPOSITIVO} y lectura de un cuadro (como OBS)"
    FOTO="${SALIDA}/verificacion_$(date +%Y%m%d_%H%M%S).jpg"
    PROPIO=""
    if bash "${AQUI}/webcam_iphone.sh" --estado | grep -q Prendida; then
        nota "La Webcam iPhone ya estaba prendida: se lee de ahi."
    else
        setsid "$PY" "${TOOLS}/lente_rapido.py" --v4l2 "$DISPOSITIVO" --fps 30 > "${SALIDA}/verificacion.log" 2>&1 < /dev/null &
        PROPIO=$!
        sleep 6
    fi
    if timeout 15 ffmpeg -hide_banner -loglevel error -y -f v4l2 -i "$DISPOSITIVO" -frames:v 1 "$FOTO" 2>"${SALIDA}/lectura.log" \
        && [[ -s "$FOTO" ]]; then
        bien "Cuadro leido de ${DISPOSITIVO}: ${FOTO} ($(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0:s=x "$FOTO" 2>/dev/null))"
    else
        mal "No se pudo leer un cuadro de ${DISPOSITIVO}. Ver ${SALIDA}/verificacion.log y ${SALIDA}/lectura.log (Lente abierta en el iPhone?)"
    fi
    if [[ -n "$PROPIO" ]]; then
        kill -TERM -- "-${PROPIO}" 2>/dev/null || kill -TERM "$PROPIO" 2>/dev/null
        sleep 1
        grep -E "Transmitiendo|Esperando|cortada|FFmpeg" "${SALIDA}/verificacion.log" | tail -n 4 | sed 's/^/        /'
    fi
fi

echo ""
if (( FALLAS == 0 )); then
    echo -e "${GREEN}Todo bien.${NC} Uso diario: Lente abierta en el iPhone, cable, clic en 'Webcam iPhone', OBS."
else
    echo -e "${RED}${FALLAS} falla(s).${NC} Arreglos en docs/MODO_RAPIDO.md, seccion 'Si algo falla'."
fi
exit $(( FALLAS > 0 ))
