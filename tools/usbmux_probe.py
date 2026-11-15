"""Sonda usbmux de Lente: lista los iPhone conectados y abre un tunel a un puerto de la app.

Uso:
    python usbmux_probe.py --listar
    python usbmux_probe.py --conectar 27183 [--udid UDID] [--segundos 10]
    python usbmux_probe.py --conectar 27183 --lnte "raw_stream=true" --raw | ffplay -f h264 -
    python usbmux_probe.py --conectar 27183 --lnte "camera_fps=60" --demux | ffplay -f h264 -

Con --raw escribe en la salida estandar lo que manda el iPhone, tal cual.
Con --lnte abre una sesion de Lente (parametros clave=valor separados por coma).
Con --demux valida el formato de scrcpy 4.1 (respuesta LNTE, metadatos, paquete de
sesion y encabezados de 12 bytes), escribe el Annex B en la salida estandar y cada
5 segundos imprime en stderr cuadros por segundo, cuadros clave y tasa de bits.
Sin --raw ni --demux imprime cuantos bytes llegaron y los primeros bytes en hexadecimal.

Solo biblioteca estandar. Windows: Apple Mobile Device Service en 127.0.0.1:27015.
Linux: socket /var/run/usbmuxd. USBMUXD_SOCKET_ADDRESS sobrescribe ("UNIX:/ruta" o "host:puerto").
"""
import argparse
import os
import plistlib
import socket
import struct
import sys
import time

PLIST = 8


def abrir_usbmuxd() -> socket.socket:
    destino = os.environ.get("USBMUXD_SOCKET_ADDRESS")
    try:
        if destino:
            if destino.startswith("UNIX:"):
                s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                s.connect(destino[5:])
                return s
            host, puerto = destino.rsplit(":", 1)
            return socket.create_connection((host, int(puerto)))
        if os.name == "nt":
            return socket.create_connection(("127.0.0.1", 27015))
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.connect("/var/run/usbmuxd")
        return s
    except OSError as e:
        if os.name == "nt":
            ayuda = "Instala iTunes descargado de apple.com y conecta el iPhone"
        else:
            ayuda = "Instala usbmuxd (sudo dnf install usbmuxd) y conecta el iPhone"
        sys.exit(f"No pude abrir usbmuxd ({e}). {ayuda}.")


def leer_exacto(s: socket.socket, n: int) -> bytes:
    datos = bytearray()
    while len(datos) < n:
        trozo = s.recv(n - len(datos))
        if not trozo:
            raise ConnectionError("usbmuxd cerro la conexion")
        datos += trozo
    return bytes(datos)


def enviar(s: socket.socket, tag: int, mensaje: dict) -> None:
    cuerpo_dict = {"ClientVersionString": "lente-probe", "ProgName": "lente-probe"}
    cuerpo_dict.update(mensaje)
    cuerpo = plistlib.dumps(cuerpo_dict, fmt=plistlib.FMT_XML)
    s.sendall(struct.pack("<IIII", 16 + len(cuerpo), 1, PLIST, tag) + cuerpo)


def recibir(s: socket.socket) -> dict:
    largo, _version, _tipo, _tag = struct.unpack("<IIII", leer_exacto(s, 16))
    return plistlib.loads(leer_exacto(s, largo - 16))


def listar() -> list:
    s = abrir_usbmuxd()
    enviar(s, 1, {"MessageType": "ListDevices"})
    respuesta = recibir(s)
    s.close()
    return respuesta.get("DeviceList", [])


def elegir(dispositivos: list, udid: str | None) -> dict:
    usb = [d for d in dispositivos if d.get("Properties", {}).get("ConnectionType") == "USB"]
    if udid:
        usb = [d for d in usb if d["Properties"].get("SerialNumber") == udid]
    if not usb:
        sys.exit("No hay ningun iPhone conectado por USB (o el UDID no coincide).")
    return usb[0]


def conectar(dispositivo: dict, puerto: int) -> socket.socket:
    s = abrir_usbmuxd()
    enviar(s, 2, {
        "MessageType": "Connect",
        "DeviceID": dispositivo["DeviceID"],
        "PortNumber": socket.htons(puerto),
    })
    respuesta = recibir(s)
    numero = respuesta.get("Number", -1)
    if numero != 0:
        causas = {2: "dispositivo no encontrado", 3: "conexion rechazada: abri la app en el iPhone"}
        sys.exit(f"usbmuxd respondio {numero} ({causas.get(numero, 'codigo desconocido')}).")
    return s


def abrir_sesion(tunel: socket.socket, parametros: str) -> dict:
    """Manda la apertura LNTE (version 1) y devuelve los parametros enviados."""
    pares = {}
    for item in filter(None, (x.strip() for x in parametros.split(","))):
        clave, _, valor = item.partition("=")
        pares[clave] = valor
    texto = "\n".join(f"{k}={v}" for k, v in pares.items()).encode()
    tunel.sendall(b"LNTE" + struct.pack(">HHI", 1, 0, len(texto)) + texto)
    return pares


def leer_respuesta(tunel: socket.socket) -> None:
    magia, version, estado, sesion, largo = struct.unpack(">4sHBQH", leer_exacto(tunel, 17))
    mensaje = leer_exacto(tunel, largo).decode("utf-8", "replace")
    if magia != b"LNTE":
        sys.exit(f"Respuesta invalida: {magia!r}")
    estados = {0: "OK", 1: "version incompatible", 2: "parametro invalido", 3: "camara no disponible",
               4: "sesion ocupada", 5: "permiso de camara denegado"}
    print(f"LNTE v{version}: {estados.get(estado, estado)} · sesion {sesion:016x} · {mensaje}", file=sys.stderr)
    if estado != 0:
        sys.exit(1)


def demux(tunel: socket.socket, pares: dict, segundos: float) -> None:
    def activo(clave: str) -> bool:
        return pares.get(clave, "true") != "false"

    if activo("send_device_meta"):
        nombre = leer_exacto(tunel, 64).split(b"\0", 1)[0].decode("utf-8", "replace")
        print(f"Dispositivo: {nombre}", file=sys.stderr)
    if activo("send_stream_meta"):
        codec = leer_exacto(tunel, 4)
        print(f"Codec: {codec.decode('ascii', 'replace')}", file=sys.stderr)
    salida = sys.stdout.buffer
    cuadros = claves = bytes_ = 0
    pts_previo = None
    marca = time.monotonic()
    fin = marca + segundos if segundos > 0 else None
    while fin is None or time.monotonic() < fin:
        cabecera = leer_exacto(tunel, 12)
        if cabecera[0] & 0x80:
            ancho, alto = struct.unpack(">II", cabecera[4:])
            print(f"Paquete de sesion: {ancho}x{alto}", file=sys.stderr)
            continue
        banderas, largo = struct.unpack(">QI", cabecera)
        datos = leer_exacto(tunel, largo)
        if not datos.startswith(b"\0\0\0\1"):
            sys.exit(f"Paquete sin codigo de inicio Annex B: {datos[:8].hex(' ')}")
        if banderas & (1 << 62):
            print(f"Paquete de configuracion: {largo} bytes", file=sys.stderr)
        else:
            pts = banderas & ((1 << 61) - 1)
            if pts_previo is not None and pts <= pts_previo:
                print(f"Aviso: PTS no crece ({pts_previo} -> {pts})", file=sys.stderr)
            pts_previo = pts
            cuadros += 1
            claves += bool(banderas & (1 << 61))
        bytes_ += 12 + largo
        salida.write(datos)
        salida.flush()
        ahora = time.monotonic()
        if ahora - marca >= 5:
            t = ahora - marca
            print(f"{cuadros / t:.1f} cuadros/s · {claves} clave · {bytes_ * 8 / t / 1e6:.1f} Mbps", file=sys.stderr)
            cuadros = claves = bytes_ = 0
            marca = ahora


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--listar", action="store_true")
    ap.add_argument("--conectar", type=int, metavar="PUERTO")
    ap.add_argument("--udid")
    ap.add_argument("--raw", action="store_true")
    ap.add_argument("--segundos", type=float, default=10.0)
    ap.add_argument("--lnte", metavar="PARAMETROS")
    ap.add_argument("--demux", action="store_true")
    a = ap.parse_args()

    dispositivos = listar()
    if a.listar or not a.conectar:
        if not dispositivos:
            print("usbmuxd responde, pero no ve ningun iPhone.")
        for d in dispositivos:
            p = d.get("Properties", {})
            print(f"DeviceID {d.get('DeviceID')} · UDID {p.get('SerialNumber')} · "
                  f"{p.get('ConnectionType')} · ProductID {p.get('ProductID')}")
        return

    tunel = conectar(elegir(dispositivos, a.udid), a.conectar)
    print(f"Tunel abierto al puerto {a.conectar} del iPhone.", file=sys.stderr)
    if a.lnte is not None:
        pares = abrir_sesion(tunel, a.lnte)
        if pares.get("raw_stream") != "true":
            leer_respuesta(tunel)
        if a.demux:
            try:
                demux(tunel, pares, a.segundos if a.segundos != 10.0 else 0)
            except (ConnectionError, BrokenPipeError):
                print("Conexion cerrada.", file=sys.stderr)
            return
    if a.raw:
        salida = sys.stdout.buffer
        while True:
            datos = tunel.recv(65536)
            if not datos:
                break
            salida.write(datos)
            salida.flush()
        return

    total, primeros, fin = 0, b"", time.monotonic() + a.segundos
    tunel.settimeout(1.0)
    while time.monotonic() < fin:
        try:
            datos = tunel.recv(65536)
        except socket.timeout:
            continue
        if not datos:
            break
        if len(primeros) < 32:
            primeros += datos[: 32 - len(primeros)]
        total += len(datos)
    print(f"Recibidos {total} bytes en {a.segundos:.0f} s. Primeros bytes: {primeros.hex(' ')}")


if __name__ == "__main__":
    main()
