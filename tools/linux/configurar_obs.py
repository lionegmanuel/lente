"""Lente: deja OBS (Linux, de la distro o Flatpak) listo para la camara del iPhone.

Crea el perfil y la coleccion de escenas "Lente iPhone" y los deja activos, sin tocar
los perfiles ni las escenas que ya existan:

  * Video 1920x1080 a 30 cuadros (lo que manda el iPhone).
  * Escena "iPhone" con la fuente "Webcam iPhone" (V4L2, /dev/video10), ajustada a toda
    la pantalla, sin bufer y con reinicio solo si deja de llegar imagen. Filtro Apply LUT
    al 90% si encuentra el LUT (Studio_Cinema_HerasHiguera_<lugar>.cube, por defecto el de
    la habitacion de la PC, "room"; si no, el del living, "kitchen").
  * Mic/Aux: si esta enchufado el receptor Boya BY-V, ese microfono con los 6 filtros de la
    plantilla de Velinex (Contenido y Marketing/Plantilla Microfono OBS, la misma de la
    laptop con Windows); si no, el Mic/Aux de la coleccion VELINEX_PRO tal cual (en la PC
    principal, "Fifine Voz" de PipeWire en mono con sus filtros) o, si no existe, el microfono
    por defecto del sistema.
  * Grabacion con la placa, a la maxima calidad (2026-11-16, igual que OBS en la laptop):
    AMD o Intel VA-API H.264 CQP 16; NVIDIA NVENC H.264 CQP 16, preset p7 y dos pasadas
    completas; sin placa, x264 CRF 16. Carpeta: /mnt/d/Videos si existe el disco de datos, si no ~/Videos.

Uso (con OBS cerrado):
    python3 configurar_obs.py [--lut RUTA.cube] [--videos CARPETA] [--fps 30] [--simular]
"""
from __future__ import annotations

import argparse
import configparser
import glob
import json
import os
import shutil
import subprocess
import sys
import uuid
from pathlib import Path

NOMBRE = "Lente iPhone"
CARPETA = "Lente_iPhone"
LUT_LOOK = "Studio_Cinema_HerasHiguera"
# Los LUT van por lugar de grabacion (VELINEX/.../LUTs/README.md): "room" es la habitacion de la PC
# principal (calibrado el 2026-11-17 con el iPhone en su lugar); "kitchen", el living de la laptop.
LUGARES = ("room", "kitchen")
PLANTILLA_MIC = "Contenido y Marketing/Plantilla Microfono OBS/plantilla_mic_boya_byv.json"
COLECCION_FIFINE = "VELINEX_PRO"  # coleccion de la PC principal: el Fifine en Mic/Aux con sus filtros
FLATPAK_ID = "com.obsproject.Studio"


def decir(texto: str) -> None:
    print(f"  {texto}", flush=True)


def correr(cmd: list) -> str:
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=30).stdout
    except (OSError, subprocess.SubprocessError):
        return ""


def instalaciones() -> list:
    """Carpetas de configuracion de cada OBS instalado (Flatpak y de la distro)."""
    dirs = []
    # "flatpak list" ve todas las instalaciones: usuario, sistema y la del disco de datos
    if shutil.which("flatpak") and FLATPAK_ID in correr(["flatpak", "list", "--app", "--columns=application"]).split():
        dirs.append(("Flatpak", Path.home() / ".var/app" / FLATPAK_ID / "config/obs-studio"))
    if shutil.which("obs"):
        dirs.append(("distro", Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "obs-studio"))
    return dirs


def version_obs(tipo: str) -> tuple:
    if tipo == "Flatpak":
        texto = correr(["flatpak", "info", FLATPAK_ID])
        clave = "Version:"
    else:
        texto = correr(["obs", "--version"])
        clave = "OBS Studio"
    for linea in texto.splitlines():
        if clave in linea:
            numeros = "".join(c if c.isdigit() or c == "." else " " for c in linea.split(clave)[-1]).split()
            if numeros:
                try:
                    return tuple(int(x) for x in numeros[0].split(".")[:3])
                except ValueError:
                    pass
    return ()


def obs_abierto() -> bool:
    return bool(correr(["pgrep", "-x", "obs"]).strip())


def placa() -> str:
    tipo = "otra"
    for d in glob.glob("/sys/bus/pci/devices/*"):
        try:
            if not open(f"{d}/class").read().startswith("0x03"):
                continue
            vendor = open(f"{d}/vendor").read().strip()
        except OSError:
            continue
        if vendor == "0x1002":
            tipo = "amd"
        elif vendor == "0x10de" and tipo != "amd":
            tipo = "nvidia"
        elif vendor == "0x8086" and tipo == "otra":
            tipo = "intel"
    return tipo


def buscar_lut(datos: str | None, lugar: str = LUGARES[0]) -> str | None:
    """El LUT vive en el repo VELINEX; se busca donde suele estar montado, sin recorrer todo el disco.
    Primero el del lugar pedido y, si no existe, el de los otros lugares."""
    for l in (lugar,) + tuple(x for x in LUGARES if x != lugar):
        encontrado = buscar_lut_lugar(datos, l)
        if encontrado:
            return encontrado
    return None


def buscar_lut_lugar(datos: str | None, lugar: str) -> str | None:
    nombre = f"{LUT_LOOK}_{lugar}.cube"
    cola = f"Contenido y Marketing/Scrcpy - Webcam Celular/LUTs/{lugar}/{nombre}"
    casa = str(Path.home())
    patrones = [f"{datos}/Documents/MANUEL/VELINEX/{cola}"] if datos else []
    patrones += [f"/mnt/*/Documents/MANUEL/VELINEX/{cola}", f"/run/media/*/*/Documents/MANUEL/VELINEX/{cola}",
                f"/media/*/*/Documents/MANUEL/VELINEX/{cola}", f"{casa}/Documents/MANUEL/VELINEX/{cola}",
                f"{casa}/*/Documents/MANUEL/VELINEX/{cola}", f"{casa}/VELINEX/{cola}", f"{casa}/*/VELINEX/{cola}",
                f"{casa}/.var/app/{FLATPAK_ID}/config/obs-studio/luts/{nombre}"]
    for patron in patrones:
        for c in sorted(glob.glob(patron)):
            if os.path.isfile(c):
                return c
    return None


def buscar_plantilla_mic(datos: str | None) -> dict | None:
    """Plantilla del Boya BY-V del repo VELINEX, buscada en los mismos lugares que el LUT."""
    lut = buscar_lut(datos)
    candidatas = []
    if lut and "/VELINEX/" in lut:
        candidatas.append(lut.split("/VELINEX/")[0] + "/VELINEX/" + PLANTILLA_MIC)
    casa = str(Path.home())
    patrones = ([f"{datos}/Documents/MANUEL/VELINEX/{PLANTILLA_MIC}"] if datos else []) + [
        f"/mnt/*/Documents/MANUEL/VELINEX/{PLANTILLA_MIC}", f"/run/media/*/*/Documents/MANUEL/VELINEX/{PLANTILLA_MIC}",
        f"{casa}/Documents/MANUEL/VELINEX/{PLANTILLA_MIC}", f"{casa}/*/VELINEX/{PLANTILLA_MIC}"]
    for patron in patrones:
        candidatas += sorted(glob.glob(patron))
    for c in candidatas:
        if os.path.isfile(c):
            try:
                return json.loads(Path(c).read_text(encoding="utf-8"))
            except (OSError, ValueError):
                return None
    return None


def mic_existente(base: Path) -> dict:
    """Mic/Aux de la coleccion VELINEX_PRO (el Fifine de la PC principal): dispositivo (por ejemplo
    "fifine_voz", el Fifine con el corte de graves de PipeWire), mono, volumen, desfase y filtros,
    copiados tal cual. Vacio si no existe."""
    archivo = base / "basic/scenes" / f"{COLECCION_FIFINE}.json"
    try:
        mic = json.loads(archivo.read_text(encoding="utf-8")).get("AuxAudioDevice1") or {}
    except (OSError, ValueError):
        return {}
    if not mic:
        return {}
    filtros = []
    for f in mic.get("filters", []):
        copia = json.loads(json.dumps(f))
        copia["uuid"] = str(uuid.uuid4())
        filtros.append(copia)
    return {"device_id": (mic.get("settings") or {}).get("device_id", "default"), "filtros": filtros,
            "flags": mic.get("flags", 0), "volume": mic.get("volume", 1.0), "sync": mic.get("sync", 0)}


def mic_boya() -> str | None:
    """Nombre de PipeWire/PulseAudio del receptor Boya BY-V, si esta enchufado."""
    for linea in correr(["pactl", "list", "short", "sources"]).splitlines():
        partes = linea.split("\t")
        if len(partes) > 1 and not partes[1].endswith(".monitor") and any(
                m in partes[1].lower() for m in ("by-v", "by_v", "boya")):
            return partes[1]
    return None


def carpeta_videos() -> Path:
    if os.path.isdir("/mnt/d"):
        return Path("/mnt/d/Videos")
    xdg = correr(["xdg-user-dir", "VIDEOS"]).strip()
    return Path(xdg) if xdg and xdg != str(Path.home()) else Path.home() / "Videos"


def codificador(tipo_placa: str) -> tuple:
    if tipo_placa in ("amd", "intel"):
        return "ffmpeg_vaapi_tex", {"rate_control": "CQP", "qp": 16, "bf": 0, "keyint_sec": 2}
    if tipo_placa == "nvidia":
        return "obs_nvenc_h264_tex", {"rate_control": "CQP", "cqp": 16, "preset2": "p7", "tune": "hq",
                                      "multipass": "fullres", "profile": "high", "bf": 2}
    return "obs_x264", {"rate_control": "CRF", "crf": 16, "preset": "veryfast", "profile": "high"}


def fuente(nombre: str, id_: str, ajustes: dict, filtros: list | None = None, mixers: int = 0) -> dict:
    s = {
        "prev_ver": 0, "name": nombre, "uuid": str(uuid.uuid4()), "id": id_, "versioned_id": id_,
        "settings": ajustes, "mixers": mixers, "sync": 0, "flags": 0, "volume": 1.0, "balance": 0.5,
        "enabled": True, "muted": False, "push-to-mute": False, "push-to-mute-delay": 0,
        "push-to-talk": False, "push-to-talk-delay": 0, "hotkeys": {}, "deinterlace_mode": 0,
        "deinterlace_field_order": 0, "monitoring_type": 0, "private_settings": {},
    }
    if filtros:
        s["filters"] = filtros
    return s


def coleccion(dispositivo: str, lut: str | None, mic_dispositivo: str = "default",
              plantilla_mic: dict | None = None, mic_defecto: dict | None = None) -> dict:
    filtros = []
    if lut:
        filtro = fuente("Apply LUT", "clut_filter", {"image_path": lut, "clut_amount": 0.9, "passthrough_alpha": False})
        filtros.append(filtro)
    camara = fuente("Webcam iPhone", "v4l2_input",
                    {"device_id": dispositivo, "buffering": False, "auto_reset": True, "timeout_frames": 60},
                    filtros, mixers=0)
    item = {
        "name": camara["name"], "source_uuid": camara["uuid"], "visible": True, "locked": False, "rot": 0.0,
        "pos": {"x": 0.0, "y": 0.0}, "scale": {"x": 1.0, "y": 1.0}, "align": 5,
        "bounds_type": 2, "bounds_align": 0, "bounds": {"x": 1920.0, "y": 1080.0}, "bounds_crop": False,
        "crop_left": 0, "crop_top": 0, "crop_right": 0, "crop_bottom": 0, "id": 1,
        "group_item_backup": False, "scale_filter": "disable", "blend_method": "default", "blend_type": "normal",
        "show_transition": {"duration": 0}, "hide_transition": {"duration": 0}, "private_settings": {},
    }
    escena = fuente("iPhone", "scene", {"items": [item], "id_counter": 1, "custom_size": False})
    escena["canvas_uuid"] = "6c69626f-6273-4c00-9d88-c5136d61696e"  # lienzo principal de OBS 32 (constante de libobs)
    filtros_mic = []
    for f in (plantilla_mic or {}).get("filtros", []):
        filtro = fuente(f["name"], f["id"], f["settings"], mixers=255)
        filtro["versioned_id"] = f.get("versioned_id", f["id"])
        filtros_mic.append(filtro)
    if not plantilla_mic and mic_defecto:
        filtros_mic = mic_defecto["filtros"]
        mic_dispositivo = mic_defecto["device_id"]
    mic = fuente("Mic/Aux", "pulse_input_capture", {"device_id": mic_dispositivo}, filtros_mic, mixers=255)
    if plantilla_mic:
        mic["volume"] = float(plantilla_mic.get("volumen_fuente", 1.0))
    elif mic_defecto:
        mic.update(flags=mic_defecto["flags"], volume=mic_defecto["volume"], sync=mic_defecto["sync"])
    return {
        "AuxAudioDevice1": mic,
        "current_scene": "iPhone", "current_program_scene": "iPhone",
        "scene_order": [{"name": "iPhone"}], "name": NOMBRE,
        "sources": [escena, camara], "groups": [], "quick_transitions": [], "transitions": [],
        "saved_projectors": [], "current_transition": "Fade", "transition_duration": 300,
        "preview_locked": False, "scaling_enabled": False, "scaling_level": 0,
        "scaling_off_x": 0.0, "scaling_off_y": 0.0, "modules": {},
    }


def leer_ini(ruta: Path) -> configparser.ConfigParser:
    cp = configparser.ConfigParser(interpolation=None, strict=False)
    cp.optionxform = str
    if ruta.exists():
        cp.read(ruta, encoding="utf-8-sig")
    return cp


def escribir_ini(cp: configparser.ConfigParser, ruta: Path) -> None:
    ruta.parent.mkdir(parents=True, exist_ok=True)
    with open(ruta, "w", encoding="utf-8") as f:
        cp.write(f, space_around_delimiters=False)


def poner(cp: configparser.ConfigParser, seccion: str, valores: dict) -> None:
    if not cp.has_section(seccion):
        cp.add_section(seccion)
    for k, v in valores.items():
        cp[seccion][k] = str(v)


def configurar(base: Path, tipo: str, a, lut: str | None, videos: Path, enc: str, enc_ajustes: dict,
               boya: str | None = None, plantilla_mic: dict | None = None) -> None:
    version = version_obs(tipo)
    formato = "hybrid_mp4" if version >= (30, 2) else "mkv"
    perfil_dir = base / "basic/profiles" / CARPETA
    ini = leer_ini(perfil_dir / "basic.ini")
    poner(ini, "General", {"Name": NOMBRE})
    poner(ini, "Video", {"BaseCX": 1920, "BaseCY": 1080, "OutputCX": 1920, "OutputCY": 1080,
                         "FPSType": 0, "FPSCommon": a.fps, "FPSInt": a.fps, "FPSNum": a.fps, "FPSDen": 1,
                         "ScaleType": "bicubic", "ColorFormat": "NV12", "ColorSpace": "709", "ColorRange": "Partial"})
    poner(ini, "Audio", {"SampleRate": 48000, "ChannelSetup": "Stereo"})
    poner(ini, "Output", {"Mode": "Advanced"})
    poner(ini, "AdvOut", {"RecType": "Standard", "RecEncoder": enc, "RecFilePath": str(videos),
                          "RecFormat2": formato, "RecTracks": 1, "RecAudioEncoder": "ffmpeg_aac",
                          "TrackIndex": 1, "Encoder": "obs_x264", "Track1Bitrate": 320})
    escenas = base / "basic/scenes" / f"{CARPETA}.json"
    usuario = base / "user.ini"
    globales = base / "global.ini"

    decir(f"OBS {tipo} {'.'.join(map(str, version)) or '(version desconocida)'} en {base}")
    decir(f"Perfil y escenas '{NOMBRE}': 1920x1080 a {a.fps} cuadros, {enc} {json.dumps(enc_ajustes)}, {formato} en {videos}")
    decir(f"Fuente 'Webcam iPhone' en {a.dispositivo}; LUT: {lut or 'no encontrado (se agrega a mano, ver docs/MODO_RAPIDO.md)'}")
    if boya and plantilla_mic:
        decir(f"Mic/Aux: Boya BY-V ({boya}) con la plantilla '{plantilla_mic.get('nombre', '')}' "
              f"v{plantilla_mic.get('version', '')}, {len(plantilla_mic.get('filtros', []))} filtros")
    elif boya:
        decir(f"Mic/Aux: Boya BY-V ({boya}), sin filtros: no encontre la plantilla del repo VELINEX")
    else:
        defecto = mic_existente(base)
        if defecto:
            decir(f"Mic/Aux: el de '{COLECCION_FIFINE}' ({defecto['device_id']}, {len(defecto['filtros'])} filtros"
                  f"{', mono' if defecto['flags'] & 1 else ''}). Para el Boya: enchufar el receptor y volver a correr")
        else:
            decir(f"Mic/Aux: microfono por defecto, sin filtros (no hay coleccion '{COLECCION_FIFINE}'). "
                  "Para el Boya: enchufar el receptor y volver a correr")
    if a.simular:
        return

    escribir_ini(ini, perfil_dir / "basic.ini")
    (perfil_dir / "recordEncoder.json").write_text(json.dumps(enc_ajustes, indent=4), encoding="utf-8")
    escenas.parent.mkdir(parents=True, exist_ok=True)
    datos_escenas = coleccion(a.dispositivo, lut, boya or "default", plantilla_mic if boya else None,
                              None if boya else mic_existente(base))
    escenas.write_text(json.dumps(datos_escenas, indent=4, ensure_ascii=False), encoding="utf-8")
    activo = {"Profile": NOMBRE, "ProfileDir": CARPETA, "SceneCollection": NOMBRE, "SceneCollectionFile": f"{CARPETA}.json"}
    # OBS 31 o superior usa user.ini; los anteriores, global.ini. Se escriben los dos.
    for archivo in (usuario, globales):
        cp = leer_ini(archivo)
        poner(cp, "Basic", activo)
        if archivo == usuario and not cp.has_option("General", "FirstRun"):
            poner(cp, "General", {"FirstRun": "true"})  # sin el asistente de primera vez
        escribir_ini(cp, archivo)
    videos.mkdir(parents=True, exist_ok=True)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--lut")
    ap.add_argument("--videos")
    ap.add_argument("--datos", help="disco de datos (HDD): si el LUT esta ahi, OBS lo usa sin copiarlo")
    ap.add_argument("--lugar", default=LUGARES[0], help="LUT del lugar de grabacion: room (PC, por defecto) o kitchen")
    ap.add_argument("--fps", type=int, default=30)
    ap.add_argument("--dispositivo", default=os.environ.get("LENTE_V4L2", "/dev/video10"))
    ap.add_argument("--placa", choices=["amd", "nvidia", "intel", "otra"])
    ap.add_argument("--simular", action="store_true")
    a = ap.parse_args()

    dirs = instalaciones()
    if not dirs:
        print("No encuentro OBS (ni Flatpak com.obsproject.Studio ni el comando obs). Instalarlo y volver a correr.")
        sys.exit(1)
    if obs_abierto() and not a.simular:
        print("OBS esta abierto: cerrarlo y volver a correr (OBS pisa la configuracion al cerrarse).")
        sys.exit(1)
    lut = a.lut or buscar_lut(a.datos, a.lugar)
    videos = Path(a.videos) if a.videos else carpeta_videos()
    tipo_placa = a.placa or placa()
    enc, enc_ajustes = codificador(tipo_placa)
    boya = mic_boya()
    plantilla_mic = buscar_plantilla_mic(a.datos) if boya else None
    decir(f"Placa: {tipo_placa}")
    for tipo, base in dirs:
        lut_final = lut
        en_datos = bool(lut and a.datos and str(Path(lut).resolve()).startswith(str(Path(a.datos).resolve()).rstrip("/") + "/"))
        if lut and not a.simular and not en_datos:
            # Copia del LUT junto a la configuracion: OBS lo encuentra aunque el disco de datos no este montado
            destino = base / "luts" / Path(lut).name
            destino.parent.mkdir(parents=True, exist_ok=True)
            if Path(lut).resolve() != destino.resolve():
                shutil.copyfile(lut, destino)
            lut_final = str(destino)
        configurar(base, tipo, a, lut_final, videos, enc, enc_ajustes, boya, plantilla_mic)
    print(f"OBS listo: al abrirlo, perfil y escenas '{NOMBRE}'." if not a.simular else "Simulado: no se escribio nada.")


if __name__ == "__main__":
    main()
