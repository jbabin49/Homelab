# Gitea — Hébergement Git self-hosted

Service Git self-hosted déployé en binaire sur un **Raspberry Pi 3B** (RPi OS
Lite Trixie 32-bit) : [Gitea](https://about.gitea.com/) héberge le code et la
documentation du homelab avec rendu Markdown natif, wiki intégré par dépôt, et
accès SSH dédié. Les données sont stockées sur le **NAS OMV** via un montage NFS
pour bénéficier du RAID 1.

> Toutes les valeurs sensibles (domaines, IP, identifiants) sont des exemples
> fictifs. Remplacer les `<...>` avant de déployer.

## Fonctionnalités

- **Interface web GitHub-like** : dépôts, issues, wiki Markdown par projet,
  rendu des fichiers `.md` dans l'arborescence.
- **Accès SSH dédié** sur le port `2222` (le port `22` reste pour
  l'administration du RPi).
- **Stockage sur le NAS par NFS** : toutes les données Gitea (repos, avatars, LFS,
  base SQLite) résident sur le NAS OMV.
- **Base SQLite3** : pas de dépendance à un serveur de base de données externe,
  adapté à un usage mono-utilisateur.
- **Binaire standalone** : léger, pas de conteneur Docker, consommation mémoire
  minimale sur le RPi.
- **Supervision Zabbix** via agent2 systemd.

## Architecture

```
RPi 2 (192.168.1.11)
├── Gitea (binaire)
│   ├── :3000    Interface web
│   ├── :2222    SSH Git
│   └── /mnt/nas/gitea (NFS → NAS OMV)
│       ├── gitea-repositories/
│       ├── data/
│       └── gitea.db (SQLite3)
│
└── Zabbix Agent2 (systemd)

NAS OMV (192.168.1.10)
└── Export NFS : /srv/.../gitea → RPi 2
```

## Structure du dépôt

| Chemin | Rôle |
|---|---|
| [`app.ini.example`](app.ini.example) | Configuration Gitea anonymisée |

> Le fichier `app.ini` contient les secrets (clés de session, mot de passe SMTP)
> et ne doit **jamais** être committé tel quel — utiliser le `.example` comme
> modèle.

## Prérequis

- Raspberry Pi OS Lite Trixie (32-bit) ou Debian 13.
- Un export NFS configuré sur le NAS pour les données Gitea.
- Git installé sur le RPi (`sudo apt install git`).

## Déploiement

### 1. Montage NFS

Ajouter dans `/etc/fstab` :

```
192.168.1.10:/srv/<CHANGE_ME_PATH>/gitea  /mnt/nas/gitea  nfs  defaults,_netdev  0  0
```

```bash
sudo mkdir -p /mnt/nas/gitea
sudo mount -a
```

### 2. Utilisateur système

```bash
sudo adduser --system --shell /bin/bash --group --disabled-password gitea
```

### 3. Installation du binaire

```bash
# Télécharger la dernière version ARM (32-bit)
wget -O /tmp/gitea https://dl.gitea.com/gitea/1.26.4/gitea-1.26.4-linux-arm-6
sudo mv /tmp/gitea /usr/local/bin/gitea
sudo chmod +x /usr/local/bin/gitea

# Créer les répertoires
sudo mkdir -p /etc/gitea
sudo chown gitea:gitea /etc/gitea
sudo chmod 750 /etc/gitea
```

### 4. Configuration

```bash
sudo cp app.ini.example /etc/gitea/app.ini
# Éditer /etc/gitea/app.ini : renseigner les chemins, domaine, secrets
sudo chown gitea:gitea /etc/gitea/app.ini
sudo chmod 640 /etc/gitea/app.ini
```

Points clés de la configuration :

| Paramètre | Valeur |
|---|---|
| `RUN_USER` | `gitea` |
| `ROOT_PATH` | `/mnt/nas/gitea/log` |
| `DB_TYPE` | `sqlite3` |
| `PATH` (database) | `/mnt/nas/gitea/data/gitea.db` |
| `REPOSITORY_ROOT` | `/mnt/nas/gitea/gitea-repositories` |
| `HTTP_PORT` | `3000` |
| `SSH_PORT` | `2222` |
| `START_SSH_SERVER` | `true` |

### 5. Service systemd

```bash
sudo nano /etc/systemd/system/gitea.service
```

```ini
[Unit]
Description=Gitea (Git with a cup of tea)
After=network.target mnt-nas-gitea.mount
Requires=mnt-nas-gitea.mount

[Service]
Type=simple
User=gitea
Group=gitea
WorkingDirectory=/mnt/nas/gitea
ExecStart=/usr/local/bin/gitea web --config /etc/gitea/app.ini
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now gitea
sudo systemctl status gitea
```

L'interface web est accessible sur `http://192.168.1.11:3000`.

## Accès Git SSH

Le serveur SSH intégré de Gitea écoute sur le port `2222`. Configurer le client
SSH (`~/.ssh/config`) :

```
Host gitea
    HostName 192.168.1.11
    Port 2222
    User git
    IdentityFile ~/.ssh/<CHANGE_ME_KEY>
```

```bash
git clone gitea:<user>/<repo>.git
```

## Sécurité

- Ne **jamais** committer `app.ini` — il contient les secrets de session et
  SMTP.
- Le montage NFS utilise `_netdev` pour éviter un boot bloqué si le NAS est
  inaccessible.
- Le service systemd dépend explicitement du montage NFS
  (`Requires=mnt-nas-gitea.mount`).
- Le binaire tourne sous l'utilisateur système `gitea` (pas de shell interactif,
  pas de sudo).

## Dépannage

| Symptôme | Cause probable | Solution |
|---|---|---|
| Gitea ne démarre pas | Montage NFS absent | `mount -a` puis `systemctl restart gitea` |
| Interface web inaccessible | Port `3000` bloqué | Vérifier le firewall du RPi |
| SSH `connection refused` sur 2222 | `START_SSH_SERVER` désactivé | Vérifier `app.ini` section `[server]` |
| Erreur SQLite `database is locked` | Accès concurrent (peu probable en mono-user) | Vérifier qu'une seule instance Gitea tourne |

## Composants & versions

| Composant | Version |
|---|---|
| Raspberry Pi OS Lite | Trixie (32-bit) |
| Gitea | 1.26.4 (binaire ARM) |
| SQLite3 | système |
| Zabbix Agent2 | 7.0 (systemd) |

## Licence

Fourni tel quel, à des fins d'exemple et de réutilisation. Adapter les valeurs de
configuration à son propre environnement avant tout déploiement.