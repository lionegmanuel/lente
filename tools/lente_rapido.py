"""Lente modo rapido: muestra la camara del iPhone en una ventana "Lente" para OBS.

Puente hasta que exista el cliente completo (Fase 2): abre una sesion LNTE por
usbmux y pasa el Annex B a ffplay. Si se corta el cable o se cierra la app, la
ventana queda abierta y reconecta sola cada segundo. Cerrar la ventana termina todo.

Uso:
    pythonw lente_rapido.py [--fps 60] [--codec h264] [--girar]

Necesita ffplay en el PATH (o LENTE_FFPLAY con la ruta).
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


def ffplay_cmd(fps: int, girar: bool) -> list:
    ruta = os.environ.get("LENTE_FFPLAY") or shutil.which("ffplay")
    if not ruta:
        sys.exit("No encuentro ffplay. Instala FFmpeg o define LENTE_FFPLAY.")
    cmd = [ruta, "-hide_banner", "-loglevel", "error", "-window_title", "Lente",
           "-fflags", "nobuffer", "-flags", "low_delay", "-framedrop",
           "-probesize", "32", "-analyzeduration", "0", "-framerate", str(fps)]
    if girar:
        cmd += ["-vf", "hflip,vflip"]
    return cmd + ["-f", "h264", "-i", "-"]


def transmitir(tunel, destino) -> None:
    """Lee el formato de scrcpy 4.1 y escribe solo el Annex B en destino."""
    usbmux.leer_exacto(tunel, 64)  # nombre del dispositivo
    usbmux.leer_exacto(tunel, 4)   # codec
    while True:
        cabecera = usbmux.leer_exacto(tunel, 12)
        if cabecera[0] & 0x80:
            continue  # paquete de sesion (ancho y alto)
        _banderas, largo = struct.unpack(">QI", cabecera)
        destino.write(usbmux.leer_exacto(tunel, largo))
        destino.flush()


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--fps", type=int, default=60)
    ap.add_argument("--codec", choices=["h264", "h265"], default="h264")
    ap.add_argument("--girar", action="store_true", help="da vuelta la imagen 180 grados")
    a = ap.parse_args()
    if a.codec == "h265":
        sys.exit("El modo rapido solo muestra H.264.")

    flags = subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0
    ffplay = subprocess.Popen(ffplay_cmd(a.fps, a.girar), stdin=subprocess.PIPE, creationflags=flags)
    parametros = f"camera_fps={a.fps},video_codec={a.codec}"
    while ffplay.poll() is None:
        tunel = None
        try:
            dispositivo = usbmux.elegir(usbmux.listar(), None)
            tunel = usbmux.conectar(dispositivo, 27183)
            usbmux.abrir_sesion(tunel, parametros)
            usbmux.leer_respuesta(tunel)
            transmitir(tunel, ffplay.stdin)
        except (SystemExit, ConnectionError, OSError):
            pass
        finally:
            if tunel is not None:
                tunel.close()
        time.sleep(1)


if __name__ == "__main__":
    main()
