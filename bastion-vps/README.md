# Bastion VPS — Apache Guacamole durci

Stack Docker prête à déployer pour transformer un petit VPS en **bastion
d'administration à distance** : accès web (SSH / RDP / VNC) à un LAN distant, à
travers un tunnel WireGuard, une passerelle [Apache Guacamole](https://guacamole.apache.org/)
durcie, un reverse proxy Nginx et Cloudflare (TLS + authentification en amont).

> Toutes les valeurs sensibles (domaines, IP, identifiants) sont des exemples
> fictifs. Remplacer les `<...>` avant de déployer.

## Fonctionnalités

- **Accès unifié SSH / RDP / VNC** depuis un navigateur via Apache Guacamole 1.5.5.
- **Tunnel WireGuard** : le VPS est *client* d'un serveur WireGuard distant et
  atteint le LAN cible sans exposer aucun port entrant côté site distant.
- **Guacamole durci** : réseaux segmentés (`internal`), secret Docker pour la DB,
  `cap_drop: ALL`, `no-new-privileges`, `read_only` + `tmpfs`, images pinnées,
  limites mémoire/PIDs, port lié à `127.0.0.1`.
- **TLS de bout en bout** derrière Cloudflare (Full strict, certificat Origin,
  Authenticated Origin Pulls / mTLS).
- **Défense en profondeur** : Cloudflare Access (OTP email) → login Guacamole → TOTP.
- **Thème sombre** optionnel packagé en extension Guacamole (voir [`theme/`](theme/)).
- **Hardening hôte** : SSH par clé, UFW, Fail2ban, mises à jour de sécurité automatiques.

## Architecture

```
Navigateur
   │  HTTPS
   ▼
Cloudflare (proxy, Access OTP, Full strict)
   │  mTLS (Authenticated Origin Pulls)
   ▼
VPS : Nginx (443) ──► Guacamole (127.0.0.1:8080) ──► guacd
                                   │
                                   │ WireGuard (VPS = client, sortant)
                                   ▼
                          LAN distant (postes RDP/SSH, NAS, services web)
```

## Structure du dépôt

| Chemin | Rôle |
|---|---|
| [`compose.yml`](compose.yml) | Stack Docker durcie (Guacamole + guacd + PostgreSQL) |
| [`nginx-bastion.conf`](nginx-bastion.conf) | Vhost Nginx (reverse proxy HTTPS + mTLS Cloudflare) |
| [`wg0.example.conf`](wg0.example.conf) | Modèle de config client WireGuard |
| [`50unattended-upgrades`](50unattended-upgrades) | Mises à jour de sécurité automatiques (Debian) |
| [`secrets/`](secrets/) | Emplacement du mot de passe DB (non committé ; voir `.example`) |
| [`theme/`](theme/) | Sources du thème sombre + `build.sh` (génère le `.jar`) |
| [`DEPLOYMENT.md`](DEPLOYMENT.md) | Guide de déploiement pas-à-pas complet |

> Le répertoire `guacamole-home/` n'est **pas** versionné : il contient l'extension
> compilée (`dark-theme.jar`) et se génère avec `theme/build.sh` (voir
> [Thème sombre](#thème-sombre-personnalisation)). Le [`compose.yml`](compose.yml) le
> monte en lecture seule sur `/etc/guacamole` — construire le thème **avant** le premier
> `docker compose up`.

## Démarrage rapide

Le déploiement complet (hardening hôte, WireGuard, Cloudflare) est détaillé dans
[DEPLOYMENT.md](DEPLOYMENT.md). Pour la seule stack Guacamole :

```bash
git clone <URL_DU_DEPOT> guacamole && cd guacamole

# 0. Construire l'extension de thème (crée guacamole-home/extensions/dark-theme.jar,
#    monté par le compose). Voir la section « Thème sombre » pour personnaliser.
( cd theme && ./build.sh )

# 1. Secret DB (sans newline finale)
mkdir -p secrets && chmod 700 secrets
openssl rand -base64 32 | tr -d '\n' > secrets/db_password.txt
chmod 644 secrets/db_password.txt

# 2. Schéma d'init (MÊME version que l'image du compose.yml)
mkdir -p initdb db-data
docker run --rm guacamole/guacamole:1.5.5 /opt/guacamole/bin/initdb.sh --postgresql \
  > initdb/init.sql

# 3. Lancer
docker compose up -d
docker compose logs -f guacamole   # attendre "Server startup"
```

Guacamole écoute alors sur `127.0.0.1:8080` (identifiants par défaut
`guacadmin` / `guacadmin` — **à changer immédiatement**). Exposer ensuite via Nginx
et Cloudflare comme décrit dans le guide.

## Thème sombre (personnalisation)

Le thème est une extension Guacamole (une simple archive `.jar`) construite à partir
des sources de [`theme/`](theme/). Il ne modifie que l'interface web (login, accueil,
listes, paramètres) — l'affichage distant RDP/VNC n'est pas touché.

### Construire / reconstruire le `.jar`

```bash
cd theme
./build.sh          # produit ../guacamole-home/extensions/dark-theme.jar
```

`build.sh` zippe `guac-manifest.json`, `dark.css` et le dossier `images/` (s'il
contient autre chose que `.gitkeep`). Il utilise `zip` si disponible, sinon `python3`.
Après chaque build, redéployer et vider le cache navigateur (Ctrl+Maj+R) :

```bash
docker compose up -d --force-recreate guacamole
```

> Le `.jar` est monté en lecture seule comme *template* `GUACAMOLE_HOME`
> (`./guacamole-home` → `/etc/guacamole:ro`). Au démarrage, l'image copie ce template
> puis y ajoute l'extension d'auth PostgreSQL : les deux coexistent.

### Changer les couleurs

Toute la palette est regroupée en variables CSS en haut de
[`theme/dark.css`](theme/dark.css) (bloc `:root`). Modifier une valeur, reconstruire,
redéployer :

| Variable | Rôle |
|---|---|
| `--guac-bg` | Fond principal |
| `--guac-bg-elevated` | Panneaux, boîtes, en-tête |
| `--guac-bg-input` | Champs de saisie, boutons neutres |
| `--guac-border` | Bordures et séparateurs |
| `--guac-text` | Texte principal |
| `--guac-text-muted` | Texte secondaire |
| `--guac-accent` | Couleur d'accent (liens, boutons d'action) |
| `--guac-accent-hover` | Accent au survol |
| `--guac-accent-text` | Texte sur fond accentué |

> Les sélecteurs CSS sont spécifiques à Guacamole **1.5.5** ; une montée de version
> majeure (1.6+) peut nécessiter de revérifier le thème.

### Changer le logo de la page de login

Le logo est **embarqué en data-URI directement dans `dark.css`** (bloc
`.login-dialog .logo`), volontairement : Guacamole concatène le CSS de l'extension et
ne l'expose pas comme fichier statique, donc une `url()` relative vers une image ne se
résout pas. Pour le remplacer, régénérer le data-URI depuis une image source puis
reconstruire :

```bash
cd theme
python3 - <<'PY'
from PIL import Image
import io, base64, pathlib, re
img = Image.open("../logo-source.png").convert("RGBA").resize((400, 400), Image.LANCZOS)
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

(Remplacer `../logo-source.png` par le chemin de l'image souhaitée. `Pillow` requis :
`pip install Pillow`.)

## Prérequis

- Un VPS Debian 12/13 (2 vCores / 4 Go RAM suffisent).
- Docker Engine + plugin Compose.
- Un serveur WireGuard accessible côté site distant (le VPS en est client).
- Un domaine géré par Cloudflare (pour le TLS Origin et Cloudflare Access).

## Sécurité

- Ne **jamais** committer `secrets/`, `db-data/`, `initdb/init.sql` ni les clés
  WireGuard — le [`.gitignore`](.gitignore) les exclut.
- Les images sont **pinnées** (pas de `latest`) ; l'image `guacamole` et le
  script `initdb.sh` doivent partager **la même version**.
- Le port `8080` n'est **jamais** exposé publiquement : seul Nginx y accède en
  local, et Nginx n'accepte le `443` que depuis les plages IP Cloudflare.
- Voir la checklist de sécurité complète dans [DEPLOYMENT.md](DEPLOYMENT.md) §6.1.

## Composants & versions

| Composant | Version |
|---|---|
| Apache Guacamole / guacd | 1.5.5 |
| PostgreSQL | 16.6 (alpine) |
| Reverse proxy | Nginx |
| Tunnel | WireGuard |

## Licence

Fourni tel quel, à des fins d'exemple et de réutilisation. Adapter les valeurs de
configuration à son propre environnement avant tout déploiement en production.
