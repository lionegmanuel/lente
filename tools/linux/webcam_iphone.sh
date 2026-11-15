#!/usr/bin/env bash
# Lente · Webcam iPhone (Linux, cualquier distro)
#
# Prende o apaga la camara del iPhone en la webcam virtual (/dev/video10). OBS la
# toma con "Dispositivo de captura de video (V4L2)". Un clic prende, otro clic apaga.
#
#   webcam_iphone.sh                 prende (o apaga si ya estaba prendida)
#   webcam_iphone.sh --sin-girar     sin dar vuelta la imagen (iPhone con el cable al otro lado)
#   webcam_iphone.sh --ventana       muestra una ventana "Lente" en lugar de la webcam virtual
#                                    (para mirar la camara sin OBS)
#   webcam_iphone.sh --fps 60        fuerza los cuadros (si no, usa los de OBS; si no los encuentra, 30)
#   webcam_iphone.sh --apagar        apaga
#   webcam_iphone.sh --estado        dice si esta prendida
#
# Variables: LENTE_V4L2 (por defecto /dev/video10), LENTE_MBPS (24).
# Registro: ~/.cache/lente/webcam_iphone.log

set -uo pipefail

AQUI="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
TOOLS="$(cd "${AQUI}/.." && pwd)"
DISPOSITIVO="${LENTE_V4L2:-/dev/video10}"
MBPS="${LENTE_MBPS:-24}"
ESTADO_DIR="${XDG_RUNTIME_DIR:-/tmp}"
PIDFILE="${ESTADO_DIR}/lente-webcam-iphone.pid"
LOGDIR="${XDG_CACHE_HOME:-$HOME/.cache}/lente"
LOG="${LOGDIR}/webcam_iphone.log"
mkdir -p "$LOGDIR"

GIRAR="--girar"
VENTANA=false
FPS=""
ACCION="alternar"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --sin-girar) GIRAR="" ;;
        --ventana) VENTANA=true ;;
        --fps) FPS="${2:-}"; shift ;;
        --apagar) ACCION="apagar" ;;
        --estado) ACCION="estado" ;;
        -h|--help) sed -n '2,17p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Opcion desconocida: $1 (ver --help)"; exit 1 ;;
    esac
    shift
done

avisar() {
    # Notificacion de escritorio si hay; siempre tambien en la terminal y en el registro
    echo "$1"
    echo "[$(date '+%F %T')] $1" >> "$LOG"
    if command -v notify-send >/dev/null 2>&1; then
        notify-send -a "Lente" -i camera-web "Webcam iPhone" "$1" 2>/dev/null || true
    elif command -v kdialog >/dev/null 2>&1; then
        kdialog --title "Webcam iPhone" --passivepopup "$1" 5 2>/dev/null || true
    fi
}

prendida() {
    [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null
}

apagar() {
    if prendida; then
        local pid
        pid="$(cat "$PIDFILE")"
        # El lanzador arranca Lente en su propio grupo de procesos: se corta el grupo entero (Lente y FFmpeg)
        kill -TERM -- "-${pid}" 2>/dev/null || kill -TERM "$pid" 2>/dev/null
        rm -f "$PIDFILE"
        avisar "Camara del iPhone apagada."
    else
        rm -f "$PIDFILE"
        echo "La camara del iPhone ya estaba apagada."
    fi
}

# Cuadros por segundo de OBS (perfil activo), para que el iPhone mande lo mismo que se graba
fps_de_obs() {
    local base dir ini tipo valor num den
    for base in "$HOME/.var/app/com.obsproject.Studio/config/obs-studio" "$HOME/.config/obs-studio"; do
        [[ -d "$base/basic/profiles" ]] || continue
        dir="$(grep -h -m1 '^ProfileDir=' "$base/user.ini" "$base/global.ini" 2>/dev/null | head -n1 | cut -d= -f2-)"
        ini="$base/basic/profiles/${dir}/basic.ini"
        [[ -n "$dir" && -f "$ini" ]] || ini="$(ls -t "$base"/basic/profiles/*/basic.ini 2>/dev/null | head -n1)"
        [[ -f "$ini" ]] || continue
        tipo="$(sed -n 's/^FPSType=//p' "$ini" | head -n1)"
        case "${tipo:-0}" in
            1) valor="$(sed -n 's/^FPSInt=//p' "$ini" | head -n1)" ;;
            2) num="$(sed -n 's/^FPSNum=//p' "$ini" | head -n1)"; den="$(sed -n 's/^FPSDen=//p' "$ini" | head -n1)"
               [[ -n "$num" && -n "$den" && "$den" != 0 ]] && valor=$(( (num + den / 2) / den )) ;;
            *) valor="$(sed -n 's/^FPSCommon=//p' "$ini" | head -n1)" ;;
        esac
        valor="${valor%%.*}"
        [[ "$valor" == 29 ]] && valor=30
        [[ "$valor" == 59 ]] && valor=60
        if [[ "$valor" =~ ^[0-9]+$ ]] && (( valor >= 15 && valor <= 60 )); then
            echo "$valor"
            return
        fi
    done
    echo 30
}

case "$ACCION" in
    estado)
        if prendida; then echo "Prendida (PID $(cat "$PIDFILE"))"; else echo "Apagada"; fi
        exit 0 ;;
    apagar)
        apagar; exit 0 ;;
    alternar)
        if prendida; then apagar; exit 0; fi ;;
esac

PYTHON="$(command -v python3 || command -v python || true)"
if [[ -z "$PYTHON" ]]; then
    avisar "Falta Python 3. Correr tools/linux/instalar.sh"
    exit 1
fi
[[ -n "$FPS" ]] || FPS="$(fps_de_obs)"

ARGS=(--fps "$FPS" --mbps "$MBPS")
[[ -n "$GIRAR" ]] && ARGS+=("$GIRAR")
if $VENTANA; then
    DESTINO="ventana Lente"
else
    if [[ ! -e "$DISPOSITIVO" ]]; then
        avisar "No existe ${DISPOSITIVO}: falta la webcam virtual. Correr tools/linux/instalar.sh (o reiniciar si se acaba de instalar)."
        exit 1
    fi
    if [[ ! -w "$DISPOSITIVO" ]]; then
        avisar "Sin permiso en ${DISPOSITIVO}: cerrar sesion y volver a entrar (grupo video), o correr tools/linux/instalar.sh."
        exit 1
    fi
    ARGS+=(--v4l2 "$DISPOSITIVO")
    DESTINO="$DISPOSITIVO"
fi

echo "[$(date '+%F %T')] Inicio: ${ARGS[*]}" >> "$LOG"
# Proceso propio y en su grupo (setsid): sobrevive al cerrar la terminal y se apaga entero
setsid "$PYTHON" "${TOOLS}/lente_rapido.py" "${ARGS[@]}" >> "$LOG" 2>&1 < /dev/null &
PID=$!
echo "$PID" > "$PIDFILE"
sleep 3
if ! kill -0 "$PID" 2>/dev/null; then
    rm -f "$PIDFILE"
    avisar "No arranco. Ultimas lineas de ${LOG}: $(tail -n 3 "$LOG" | tr '\n' ' ')"
    exit 1
fi
avisar "Camara del iPhone prendida en ${DESTINO} a ${FPS} cuadros. Abri Lente en el iPhone. Otro clic la apaga."
