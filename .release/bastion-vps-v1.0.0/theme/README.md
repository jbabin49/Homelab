# Thème sombre Guacamole (Bastion Dark)

Extension CSS qui applique un thème sombre à l'interface web de
Guacamole 1.5.5 (login, accueil, listes de connexions, paramètres, menus).
L'affichage distant (RDP/VNC) n'est pas modifié.

## Structure

| Fichier | Rôle |
|---|---|
| `guac-manifest.json` | Descripteur de l'extension (JSON strict, pas de commentaires) |
| `dark.css` | Feuille de style du thème (palette en variables `:root`) |
| `build.sh` | Assemble le tout en `../guacamole-home/extensions/dark-theme.jar` |
| `images/` | Emplacement du logo optionnel (`logo.png`) |

## Construire / mettre à jour le thème

```sh
cd theme
./build.sh
```

Puis redéployer Guacamole :

```sh
docker compose up -d --force-recreate guacamole
```

Rechargez la page en vidant le cache (Ctrl+Maj+R) — le CSS est mis en cache
par le navigateur.

## Comment c'est branché

Le `.jar` est monté en lecture seule comme *template* `GUACAMOLE_HOME`
(`./guacamole-home` → `/etc/guacamole:ro`). Au démarrage, l'image copie ce
template dans son home runtime puis y ajoute l'extension d'auth PostgreSQL :
les deux coexistent sans conflit.

## Logo (page de login)

Le logo est **embarqué en data-URI directement dans `dark.css`** (bloc
`.login-dialog .logo`). C'est volontaire : Guacamole n'expose pas le CSS de
l'extension comme un fichier statique (il le concatène), donc une `url()`
relative vers une image ne se résout pas. Le data-URI évite tout problème de
chemin (nginx sert l'app à la racine).

Pour changer le logo, régénérez le data-URI depuis l'image source
(`../bastion-logo.png`) puis reconstruisez :

```sh
python3 - <<'PY'
from PIL import Image
import io, base64, pathlib, re
img = Image.open("../bastion-logo.png").convert("RGBA").resize((400, 400), Image.LANCZOS)
buf = io.BytesIO(); img.save(buf, format="PNG", optimize=True)
b64 = base64.b64encode(buf.getvalue()).decode()
css = pathlib.Path("dark.css").read_text()
css = re.sub(r"url\('data:image/png;base64,[^']*'\)",
             f"url('data:image/png;base64,{b64}')", css)
pathlib.Path("dark.css").write_text(css)
print("logo mis à jour")
PY
./build.sh
```

## Ajuster les couleurs

Modifiez les variables en haut de `dark.css` (bloc `:root`), reconstruisez,
redéployez. Les classes CSS sont spécifiques à la **1.5.5** : une mise à jour
majeure de Guacamole (1.6+) demandera de revérifier le thème.
