#!/bin/sh
#
# Construit l'extension de thème (dark-theme.jar) à partir des sources.
# Un .jar Guacamole est une simple archive ZIP.
#
# Utilise `zip` s'il est présent, sinon `python3` en secours.
#
set -e
cd "$(dirname "$0")"

OUT="../guacamole-home/extensions/dark-theme.jar"
mkdir -p "$(dirname "$OUT")"
rm -f "$OUT"

# On inclut le dossier images/ seulement s'il contient autre chose que .gitkeep
INCLUDE_IMAGES=0
if [ -d images ] && [ -n "$(ls -A images 2>/dev/null | grep -v '^\.gitkeep$')" ]; then
    INCLUDE_IMAGES=1
fi

if command -v zip >/dev/null 2>&1; then
    FILES="guac-manifest.json dark.css"
    [ "$INCLUDE_IMAGES" -eq 1 ] && FILES="$FILES images"
    zip -r "$OUT" $FILES -x '*/.gitkeep' >/dev/null
elif command -v python3 >/dev/null 2>&1; then
    INCLUDE_IMAGES="$INCLUDE_IMAGES" OUT="$OUT" python3 - <<'PY'
import os, zipfile
out = os.environ["OUT"]
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    z.write("guac-manifest.json")
    z.write("dark.css")
    if os.environ["INCLUDE_IMAGES"] == "1":
        for root, _, files in os.walk("images"):
            for f in files:
                if f == ".gitkeep":
                    continue
                p = os.path.join(root, f)
                z.write(p)
PY
else
    echo "Erreur : ni 'zip' ni 'python3' disponible pour construire le .jar" >&2
    exit 1
fi

echo "Construit : $OUT"
