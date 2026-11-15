"""iPhone simulado para probar Lente para la PC sin el telefono.

Hace de usbmuxd (ListDevices y Connect, plist v1, por TCP) y, dentro del tunel,
de la app Lente: valida la apertura LNTE, responde OK, manda el nombre, el codec,
el paquete de sesion y el video H.264 de un archivo Annex B con el formato de
scrcpy 4.1. Acepta la conexion de control (LNTC) y guarda lo que llega.

Uso:
    python3 iphone_simulado.py --puerto 27999 --video prueba.h264 [--sesiones 1]
    USBMUXD_SOCKET_ADDRESS=127.0.0.1:27999 lente --ios ...

Escribe un registro en stderr: parametros recibidos, cuadros enviados y los bytes
de control que llegaron (en hexadecimal), para que la prueba los compare.
"""
import argparse
import plistlib
import socket
import struct
import sys
import threading
import time

ID_DISPOSITIVO = 7
UDID = "SIMULADO-0000-LENTE"
SESION = 0x1122334455667788


def log(texto: str) -> None:
    print(f"[iphone] {texto}", file=sys.stderr, flush=True)


def leer(s: socket.socket, n: int) -> bytes:
    datos = b""
    while len(datos) < n:
        parte = s.recv(n - len(datos))
        if not parte:
            raise ConnectionError("cerrado")
        datos += parte
    return datos


def responder(s: socket.socket, tag: int, cuerpo: dict) -> None:
    xml = plistlib.dumps(cuerpo)
    s.sendall(struct.pack("<IIII", 16 + len(xml), 1, 8, tag) + xml)


def cuadros_annexb(ruta: str) -> tuple:
    datos = open(ruta, "rb").read()
    nalus = [b"\0\0\0\1" + n for n in datos.replace(b"\0\0\0\1", b"\0\0\1").split(b"\0\0\1")[1:]]
    config = b"".join(n for n in nalus if n[4] & 0x1F in (7, 8))
    cuadros = [n for n in nalus if n[4] & 0x1F in (1, 5)]
    return config, cuadros


class Simulador:
    def __init__(self, video: str, sesiones: int, fps: int) -> None:
        self.config, self.cuadros = cuadros_annexb(video)
        self.sesiones_max = sesiones
        self.sesiones = 0
        self.fps = fps
        self.control = bytearray()

    def telemetria(self, s: socket.socket) -> None:
        """Como la app: telemetria cada segundo y un evento de cambio de lente."""
        try:
            s.sendall(evento_bytes(3, "1x"))
            for i in range(1, 30):
                s.sendall(telemetria_bytes(i * 30))
                time.sleep(1)
        except OSError:
            pass

    def atender(self, s: socket.socket) -> None:
        try:
            largo, _v, _t, tag = struct.unpack("<IIII", leer(s, 16))
            msg = plistlib.loads(leer(s, largo - 16))
            tipo = msg.get("MessageType")
            if tipo == "ListDevices":
                responder(s, tag, {"DeviceList": [{
                    "DeviceID": ID_DISPOSITIVO, "MessageType": "Attached",
                    "Properties": {"ConnectionType": "USB", "SerialNumber": UDID,
                                   "ProductID": 4776, "DeviceID": ID_DISPOSITIVO}}]})
                return
            if tipo != "Connect" or msg.get("DeviceID") != ID_DISPOSITIVO:
                responder(s, tag, {"MessageType": "Result", "Number": 2})
                return
            puerto = socket.ntohs(msg["PortNumber"])
            if puerto != 27183:
                responder(s, tag, {"MessageType": "Result", "Number": 3})
                return
            responder(s, tag, {"MessageType": "Result", "Number": 0})
            magia = leer(s, 4)
            if magia == b"LNTC":
                sesion = struct.unpack(">Q", leer(s, 8))[0]
                log(f"control abierto, sesion {'OK' if sesion == SESION else 'INCORRECTA'}")
                threading.Thread(target=self.telemetria, args=(s,), daemon=True).start()
                while True:
                    parte = s.recv(4096)
                    if not parte:
                        break
                    self.control += parte
                    log(f"control: {parte.hex()}")
                return
            if magia != b"LNTE":
                log(f"apertura desconocida: {magia!r}")
                return
            version, _flags, largo = struct.unpack(">HHI", leer(s, 8))
            params = leer(s, largo).decode()
            if self.sesiones >= self.sesiones_max:
                texto = b"another session is active"
                s.sendall(b"LNTE" + struct.pack(">HBQH", 1, 4, 0, len(texto)) + texto)
                return
            self.sesiones += 1
            log(f"sesion {self.sesiones}: LNTE v{version}: {params.strip().replace(chr(10), ' ')}")
            s.sendall(b"LNTE" + struct.pack(">HBQH", 1, 0, SESION, 2) + b"ok")
            s.sendall(b"iPhone simulado".ljust(64, b"\0") + b"h264")
            s.sendall(bytes([0x80, 0, 0, 0]) + struct.pack(">II", 1920, 1080))
            s.sendall(struct.pack(">QI", 1 << 62, len(self.config)) + self.config)
            for i, c in enumerate(self.cuadros):
                clave = (c[4] & 0x1F) == 5
                pts = i * 1_000_000 // self.fps
                s.sendall(struct.pack(">QI", pts | ((1 << 61) if clave else 0), len(c)) + c)
                time.sleep(1 / self.fps)
            log(f"sesion {self.sesiones}: {len(self.cuadros)} cuadros enviados")
            # Queda abierta hasta que la PC corte, como la app
            while s.recv(4096):
                pass
        except (ConnectionError, OSError) as e:
            log(f"conexion cerrada ({e.__class__.__name__})")
        finally:
            s.close()


def telemetria_bytes(cuadros: int) -> bytes:
    # 0x60: termico, bateria, estado de bateria, cuadros, descartados, tasa de bits
    return bytes([0x60, 1, 87, 2]) + struct.pack(">III", cuadros, 0, 24_000_000)


def evento_bytes(codigo: int, texto: str) -> bytes:
    datos = texto.encode()
    return bytes([0x61, codigo]) + struct.pack(">H", len(datos)) + datos


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--puerto", type=int, default=27999)
    ap.add_argument("--video", required=True)
    ap.add_argument("--sesiones", type=int, default=1)
    ap.add_argument("--fps", type=int, default=30)
    a = ap.parse_args()
    sim = Simulador(a.video, a.sesiones, a.fps)
    srv = socket.socket()
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", a.puerto))
    srv.listen()
    log(f"usbmuxd simulado en 127.0.0.1:{a.puerto}: {len(sim.cuadros)} cuadros, config {len(sim.config)} bytes")
    while True:
        c, _ = srv.accept()
        threading.Thread(target=sim.atender, args=(c,), daemon=True).start()


if __name__ == "__main__":
    main()
