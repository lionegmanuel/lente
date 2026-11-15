"""Sonda usbmux de Lente: lista los iPhone conectados y abre un tunel a un puerto de la app.

Uso:
    python usbmux_probe.py --listar
    python usbmux_probe.py --conectar 27183 [--udid UDID] [--segundos 10]
    python usbmux_probe.py --conectar 27183 --raw | ffplay -fflags nobuffer -flags low_delay -f h264 -

Con --raw escribe en la salida estandar lo que manda el iPhone, tal cual.
Sin --raw imprime cuantos bytes llegaron y los primeros bytes en hexadecimal.

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
            ayuda = "Instala la app Apple Devices desde Microsoft Store y conecta el iPhone"
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


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--listar", action="store_true")
    ap.add_argument("--conectar", type=int, metavar="PUERTO")
    ap.add_argument("--udid")
    ap.add_argument("--raw", action="store_true")
    ap.add_argument("--segundos", type=float, default=10.0)
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
