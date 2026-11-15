"""Agrega una version de la app a la fuente de SideStore (sidestore-source.json).

    python tools/release/fuente_sidestore.py --version 1.0.0 --ipa Lente-v1.0.0.ipa \
        --notas "Primera version completa"

La fuente se publica desde la rama main por su URL raw:
https://raw.githubusercontent.com/lionegmanuel/lente/main/sidestore-source.json
En SideStore: Sources > + > esa URL. Desde ahi, actualizar Lente es tocar "Update".
"""
import argparse
import datetime
import json
import os
import sys

RAIZ = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
FUENTE = os.path.join(RAIZ, "sidestore-source.json")
PLANTILLA = os.path.join(RAIZ, "docs", "plan", "plantillas", "sidestore-source.json")
REPO = "https://github.com/lionegmanuel/lente"


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--version", required=True)
    ap.add_argument("--build", default="1")
    ap.add_argument("--ipa", required=True, help="IPA publicada en el release v<version>")
    ap.add_argument("--notas", default="")
    ap.add_argument("--fecha", default=datetime.date.today().isoformat())
    a = ap.parse_args()

    base = FUENTE if os.path.exists(FUENTE) else PLANTILLA
    with open(base, encoding="utf-8") as f:
        fuente = json.load(f)
    app = fuente["apps"][0]
    nombre = os.path.basename(a.ipa)
    entrada = {
        "version": a.version,
        "buildVersion": a.build,
        "date": a.fecha,
        "localizedDescription": a.notas or f"Lente {a.version}",
        "downloadURL": f"{REPO}/releases/download/v{a.version}/{nombre}",
        "size": os.path.getsize(a.ipa),
        "minOSVersion": "16.0",
    }
    # Solo versiones publicadas de verdad: fuera las de la plantilla (size 0)
    versiones = [v for v in app.get("versions", []) if v.get("size") and v["version"] != a.version]
    app["versions"] = [entrada] + versiones
    with open(FUENTE, "w", encoding="utf-8", newline="\n") as f:
        json.dump(fuente, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print(f"{FUENTE}: Lente {a.version} ({entrada['size']} bytes) -> {entrada['downloadURL']}")


if __name__ == "__main__":
    sys.exit(main())
