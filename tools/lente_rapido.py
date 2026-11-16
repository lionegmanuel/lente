"""Lente modo rapido: la camara del iPhone por cable para OBS, en Windows y en Linux.

Puente hasta que exista el cliente completo (Fase 2): abre una sesion LNTE por
usbmux y pasa el video H.264 (Annex B) a FFmpeg. Dos salidas:

  * Ventana "Lente" (ffplay): para "Captura de ventana" en OBS. Es lo de Windows.
  * Webcam virtual V4L2 (ffmpeg, --v4l2 /dev/video10): para "Dispositivo de captura
    de video (V4L2)" en OBS. Es lo de Linux, en cualquier distro.

Si se corta el cable o se cierra la app del iPhone, la salida queda abierta y
reconecta sola cada segundo. Cerrar la ventana (o terminar el proceso) termina todo.

Uso:
    pythonw lente_rapido.py [--fps 30] [--mbps 24] [--girar]           (Windows)
    python3 lente_rapido.py --v4l2 /dev/video10 [--fps 30] [--girar]   (Linux)

Necesita ffplay o ffmpeg en el PATH (o LENTE_FFPLAY / LENTE_FFMPEG con la ruta).
Codigo de salida: 0 si se cerro normalmente, 2 si FFmpeg no pudo arrancar.
"""
import argparse
import os
import shutil
import struct
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import usbmux_probe as usbmux  # noqa: E402


def avisar(texto: str) -> None:
    """stderr no existe con pythonw (Windows): ahi no se imprime nada."""
    if sys.stderr is not None:
        print(f"[lente {time.strftime('%H:%M:%S')}] {texto}", file=sys.stderr, flush=True)


def programa(nombre: str, variable: str) -> str:
    ruta = os.environ.get(variable) or shutil.which(nombre)
    if not ruta:
        avisar(f"No encuentro {nombre}. Instala FFmpeg o define {variable}.")
        sys.exit(2)
    return ruta


def entrada_h264(fps: int, ventana: bool) -> list:
    # ffplay (ventana) mide el tiempo con su reloj: "nobuffer" y "low_delay" evitan que
    # arrastre un retraso fijo; es la configuracion probada con el iPhone el 2026-11-15.
    # ffmpeg hacia V4L2 escribe cada cuadro apenas lo decodifica: ahi esas opciones no
    # bajan el delay y "nobuffer" tira el primer cuadro clave (2 s sin imagen al conectar).
    rapido = ["-fflags", "nobuffer", "-flags", "low_delay"] if ventana else []
    return rapido + ["-probesize", "32", "-analyzeduration", "0", "-framerate", str(fps),
                     "-f", "h264", "-i", "pipe:0"]


def ffplay_cmd(fps: int, girar: bool, fija=None) -> list:
    cmd = [programa("ffplay", "LENTE_FFPLAY"), "-hide_banner", "-loglevel", "error",
           "-window_title", "Lente", "-framedrop"]
    if fija:
        # Ventana fija de 1920x1080 sin bordes en esa esquina: OBS la captura a 1080p pixel a pixel
        cmd += ["-noborder", "-x", "1920", "-y", "1080", "-left", str(fija[0]), "-top", str(fija[1])]
    cmd += entrada_h264(fps, ventana=True)
    if girar:
        cmd += ["-vf", "hflip,vflip"]
    return cmd


def soporta(ffmpeg: str, opciones: list) -> bool:
    prueba = [ffmpeg, "-hide_banner", "-loglevel", "error", "-f", "lavfi", "-i",
              "color=size=16x16:rate=1", "-frames:v", "1"] + opciones + ["-f", "null", "-"]
    try:
        return subprocess.run(prueba, capture_output=True, timeout=20).returncode == 0
    except (OSError, subprocess.SubprocessError):
        return False


def ffmpeg_v4l2_cmd(fps: int, girar: bool, dispositivo: str) -> list:
    ffmpeg = programa("ffmpeg", "LENTE_FFMPEG")
    # Sin duplicar ni tirar cuadros: cada cuadro del iPhone sale tal cual (FFmpeg 5.1+ o anterior)
    sincronia = ["-fps_mode", "passthrough"] if soporta(ffmpeg, ["-fps_mode", "passthrough"]) else ["-vsync", "passthrough"]
    # Decodifica con la placa si se puede (VA-API, CUDA...); si no, FFmpeg sigue por software solo
    acelerado = ["-hwaccel", "auto"] if os.environ.get("LENTE_SIN_GPU") != "1" else []
    cmd = [ffmpeg, "-hide_banner", "-loglevel", "error", "-nostdin"] + acelerado + entrada_h264(fps, ventana=False)
    if girar:
        cmd += ["-vf", "hflip,vflip"]
    return cmd + sincronia + ["-pix_fmt", "yuv420p", "-f", "v4l2", dispositivo]


def transmitir(tunel, destino) -> None:
    """Lee el formato de scrcpy 4.1 y escribe solo el Annex B en destino."""
    usbmux.leer_exacto(tunel, 64)  # nombre del dispositivo
    usbmux.leer_exacto(tunel, 4)   # codec
    while True:
        cabecera = usbmux.leer_exacto(tunel, 12)
        if cabecera[0] & 0x80:
            ancho, alto = struct.unpack(">II", cabecera[4:])
            avisar(f"Transmitiendo {ancho}x{alto}")
            continue
        _banderas, largo = struct.unpack(">QI", cabecera)
        destino.write(usbmux.leer_exacto(tunel, largo))
        destino.flush()


def main() -> None:
    ap = argparse.ArgumentParser(description="Lente modo rapido: camara del iPhone por cable para OBS")
    ap.add_argument("--fps", type=int, default=30, help="cuadros por segundo, igual que OBS (30)")
    ap.add_argument("--mbps", type=int, default=24, help="tasa de bits del iPhone (24)")
    ap.add_argument("--girar", action="store_true", help="da vuelta la imagen 180 grados")
    ap.add_argument("--v4l2", metavar="DISPOSITIVO", help="Linux: escribe en la webcam virtual (ej. /dev/video10)")
    ap.add_argument("--fija", nargs=2, type=int, metavar=("X", "Y"),
                    help="ventana sin bordes de 1920x1080 con la esquina en X Y (para OBS a 1080p)")
    a = ap.parse_args()

    flags = subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0
    if a.v4l2:
        if not os.access(a.v4l2, os.W_OK):
            avisar(f"No puedo escribir en {a.v4l2}: falta v4l2loopback o el grupo video (ver docs/MODO_RAPIDO.md).")
            sys.exit(2)
        cmd = ffmpeg_v4l2_cmd(a.fps, a.girar, a.v4l2)
    else:
        cmd = ffplay_cmd(a.fps, a.girar, a.fija)
    salida = subprocess.Popen(cmd, stdin=subprocess.PIPE, creationflags=flags)
    avisar(f"Salida: {a.v4l2 or 'ventana Lente'} · esperando el iPhone con Lente abierta")

    parametros = f"camera_fps={a.fps},video_codec=h264,video_bit_rate={a.mbps * 1_000_000}"
    ultimo_aviso = ""
    while salida.poll() is None:
        tunel = None
        try:
            dispositivo = usbmux.elegir(usbmux.listar(), None)
            tunel = usbmux.conectar(dispositivo, 27183)
            usbmux.abrir_sesion(tunel, parametros)
            usbmux.leer_respuesta(tunel)
            ultimo_aviso = ""
            transmitir(tunel, salida.stdin)
        except SystemExit as e:
            texto = str(e.code) if e.code not in (None, 0, 1) else "sin sesion"
            if texto != ultimo_aviso:
                avisar(f"Esperando: {texto}")
                ultimo_aviso = texto
        except (ConnectionError, OSError) as e:
            if salida.poll() is None:
                avisar(f"Conexion cortada ({e.__class__.__name__}), reconectando")
        finally:
            if tunel is not None:
                tunel.close()
        time.sleep(1)

    codigo = salida.returncode
    avisar(f"FFmpeg termino (codigo {codigo})")
    sys.exit(0 if codigo in (0, None) or a.v4l2 is None else 2)


if __name__ == "__main__":
    main()
