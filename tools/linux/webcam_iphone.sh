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
#   webcam_iphone.sh --fps 60        fuerza los cuadros (si no, los de OBS con un maximo de 30; si no los encuentra, 30)
#   webcam_iphone.sh --rapido        usa el modo rapido (ffmpeg) aunque este Lente para la PC
#
# Con Lente para la PC instalado (lente, tools/linux/instalar.sh lo baja al disco de datos)
# usa el cliente completo: reconexion, controles y telemetria. Si no arranca (por ejemplo,
# la app del iPhone es anterior a 1.0 y no rota la imagen), pasa solo al modo rapido.
#   webcam_iphone.sh --apagar        apaga
#   webcam_iphone.sh --estado        dice si esta prendida
#
# Variables: LENTE_V4L2 (por defecto /dev/video10), LENTE_MBPS (24).
# Registro: <disco de datos>/Temp/lente/webcam_iphone.log (o ~/.cache/lente si no hay disco de datos)

set -uo pipefail

AQUI="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
TOOLS="$(cd "${AQUI}/.." && pwd)"
DISPOSITIVO="${LENTE_V4L2:-/dev/video10}"
MBPS="${LENTE_MBPS:-24}"
ESTADO_DIR="${XDG_RUNTIME_DIR:-/tmp}"
PIDFILE="${ESTADO_DIR}/lente-webcam-iphone.pid"
# Registros en el disco de datos (lo dejo instalar.sh en ~/.config/lente/lente.conf)
DATOS=""
CONF="${XDG_CONFIG_HOME:-$HOME/.config}/lente/lente.conf"
[[ -f "$CONF" ]] && . "$CONF"
# Nothing on the system disk: without lente.conf, the data disk if it is mounted
[[ -z "$DATOS" ]] && mountpoint -q /mnt/d 2>/dev/null && DATOS="/mnt/d"
if [[ -n "$DATOS" && -d "$DATOS" ]]; then
    LOGDIR="${DATOS}/Temp/lente"
else
    LOGDIR="${XDG_CACHE_HOME:-$HOME/.cache}/lente"
fi
LOG="${LOGDIR}/webcam_iphone.log"
mkdir -p "$LOGDIR"
# The log never grows past 1 MB: keep the last 500 lines
if [[ -f "$LOG" ]] && (( $(stat -c %s "$LOG" 2>/dev/null || echo 0) > 1048576 )); then
    tail -n 500 "$LOG" > "${LOG}.tmp" && mv -f "${LOG}.tmp" "$LOG"
fi

GIRAR="--girar"
VENTANA=false
RAPIDO=false
FPS=""
ACCION="alternar"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --sin-girar) GIRAR="" ;;
        --ventana) VENTANA=true ;;
        --rapido) RAPIDO=true ;;
        --fps) FPS="${2:-}"; shift ;;
        --apagar) ACCION="apagar" ;;
        --estado) ACCION="estado" ;;
        -h|--help) sed -n '2,23p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
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
# Fewest resources: never more than 30 unless asked with --fps (OBS at 60 just repeats frames)
if [[ -z "$FPS" ]]; then
    FPS="$(fps_de_obs)"
    (( FPS > 30 )) && FPS=30
fi

ARGS=(--fps "$FPS" --mbps "$MBPS")
[[ -n "$GIRAR" ]] && ARGS+=("$GIRAR")
if $VENTANA; then
    ARGS+=(--fija 0 0)
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

# Lente para la PC (cliente completo): en el PATH o en el disco de datos
LENTE_BIN="$(command -v lente || true)"
if [[ -z "$LENTE_BIN" && -n "$DATOS" && -x "${DATOS}/lente-pc/actual/lente" ]]; then
    LENTE_BIN="${DATOS}/lente-pc/actual/lente"
fi

arrancar() {
    # Proceso propio y en su grupo (setsid): sobrevive al cerrar la terminal y se apaga entero
    echo "[$(date '+%F %T')] Inicio: $*" >> "$LOG"
    setsid "$@" >> "$LOG" 2>&1 < /dev/null &
    PID=$!
    echo "$PID" > "$PIDFILE"
}

MODO="rapido"
if [[ -n "$LENTE_BIN" ]] && ! $RAPIDO; then
    MODO="completo"
    # On Linux the client only unbuffers stdout on Windows: to a file it is fully buffered, so
    # the log stays empty and "App del iPhone:" never shows up. stdbuf makes it line buffered.
    CMD=()
    command -v stdbuf >/dev/null 2>&1 && CMD=(stdbuf -oL -eL)
    CMD+=("$LENTE_BIN" --ios --camera-fps="$FPS" --video-bit-rate="${MBPS}M" --ios-reconnect=3600 --pause-on-exit=false)
    [[ -n "$GIRAR" ]] && CMD+=(--capture-orientation=180)
    if $VENTANA; then
        # Igual que Windows (2026-11-16): imagen fija en 1920x1080 con barra de titulo, para que
        # "Captura de ventana" grabe 1080p sin importar el tamano de la pantalla
        CMD+=(--window-title=Lente --window-width=1920 --window-height=1080)
    else
        CMD+=(--v4l2-sink="$DISPOSITIVO" --no-playback --no-window)
    fi
    arrancar "${CMD[@]}"
    # Hasta 20 s: si la sesion arranca, listo; si lente se cierra (sin iPhone, app vieja), modo rapido.
    # Si sigue abierto esperando que se abra la app en el iPhone, se queda (reconecta solo).
    INICIO_LOG=$(wc -l < "$LOG")
    for _ in $(seq 20); do
        sleep 1
        kill -0 "$PID" 2>/dev/null || break
        tail -n +"$((INICIO_LOG + 1))" "$LOG" | grep -q "App del iPhone:" && break
    done
    if ! kill -0 "$PID" 2>/dev/null; then
        rm -f "$PIDFILE"
        echo "[$(date '+%F %T')] Lente para la PC no arranco, paso al modo rapido" >> "$LOG"
        MODO="rapido"
    fi
fi
if [[ "$MODO" == "rapido" ]]; then
    arrancar "$PYTHON" "${TOOLS}/lente_rapido.py" "${ARGS[@]}"
    sleep 3
    if ! kill -0 "$PID" 2>/dev/null; then
        rm -f "$PIDFILE"
        avisar "No arranco. Ultimas lineas de ${LOG}: $(tail -n 3 "$LOG" | tr '\n' ' ')"
        exit 1
    fi
fi
avisar "Camara del iPhone prendida en ${DESTINO} a ${FPS} cuadros (modo ${MODO}). Abri Lente en el iPhone. Otro clic la apaga."
