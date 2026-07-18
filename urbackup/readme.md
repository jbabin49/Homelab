# UrBackup — Backups centralisés

Serveur de backup centralisé déployé en Docker sur le **NAS OMV**
(OpenMediaVault 8.5.1, Debian 13) : [UrBackup](https://www.urbackup.org/)
sauvegarde automatiquement les fichiers et images disque de toutes les machines
du homelab sur le RAID 1 du NAS, et notifie chaque résultat via
[ntfy](../ntfy/).

> Toutes les valeurs sensibles (domaines, IP, identifiants) sont des exemples
> fictifs. Remplacer les `<...>` avant de déployer.

## Fonctionnalités

- **Backups fichiers et images disque** : incrémentaux hebdomadaires, full
  mensuels.
- **Découverte réseau** via broadcast UDP (`network_mode: host`).
- **Notifications ntfy** sur chaque backup réussi via 4 scripts post-backup
  (le système Lua natif ne se déclenche que sur les échecs).
- **Conteneur durci** : `no-new-privileges`, limites mémoire (1 Go) et CPU
  (1.5 cœurs).
- **Backup séparé des clés sensibles** : les clés SSH et GPG sont **exclues**
  d'UrBackup et sauvegardées via un script GPG AES256 chiffré mensuel avec
  rotation 3 versions.

## Architecture

```
NAS OMV (192.168.1.10)
├── UrBackup Server (Docker, network_mode: host)
│   └── Stockage : RAID 1 md0 (~2 To)
│
├── Agent : ThinkCentre M73
│   ├── Fichiers hebdo : /etc, /home, composes Docker, volumes, HA
│   └── Images disque : incrémental hebdo, full mensuel (device mapper)
│
└── Agent : Acer AG15
    └── Fichiers hebdo : /etc, /home (~20-25 Go utiles)
```

## Structure du dépôt

| Chemin | Rôle |
|---|---|
| [`docker-compose.yml`](docker-compose.yml) | UrBackup Server (image `uroni/urbackup-server`) |

## Démarrage rapide

```bash
cd ~/docker/urbackup
# Remplacer les <CHANGE_ME_*> dans docker-compose.yml (chemin de stockage)
docker compose up -d
docker compose logs -f urbackup   # attendre le démarrage
```

L'interface web écoute sur le port `55414` de l'hôte. L'accès se fait via le
proxy host `urbackup.home.lab` dans [NPM](../nginx-proxy-manager/), protégé par
[Authelia](../authelia-npm/).

## Agents

Les agents se connectent en mode **internet/active** avec une authkey générée
depuis l'interface web du serveur UrBackup (le broadcast UDP LAN ne fonctionne
pas systématiquement).

### ThinkCentre M73

Installation avec **device mapper** pour les snapshots et images disque (choix 4
à l'install, reboot requis).

Chemins sauvegardés :

- `/etc`
- `/home/<user>`
- `~/docker/authelia/docker-compose.yml` + `config/`
- `~/docker/zabbix/docker-compose.yml`
- `~/docker/npm/docker-compose.yml`
- Volumes Docker : redis, grafana, pgdata
- `/var/lib/homeassistant`

### Acer AG15

Installation en mode **sans snapshot** (choix 5).

Chemins sauvegardés :

- `/etc`
- `/home/<user>` (~20-25 Go utiles après exclusions)

Exclusions : Steam (~117 Go), Akonadi (~15 Go), VMs, caches.

## Notifications ntfy

Quatre scripts shell post-backup sont placés dans `/var/urbackup/` (mappé depuis
`<stockage>/data/`) et appellent `curl` pour envoyer une notification ntfy à
chaque backup terminé :

| Script | Déclencheur |
|---|---|
| `post_incr_filebackup` | Backup fichiers incrémental |
| `post_full_filebackup` | Backup fichiers full |
| `post_incr_imagebackup` | Image disque incrémentale |
| `post_full_imagebackup` | Image disque full |

Le binaire `curl` est monté en lecture seule dans le conteneur
(`/usr/bin/curl:/usr/bin/curl:ro`). La syntaxe here-doc ne fonctionne pas
en SSH — utiliser `nano` pour éditer les scripts.

## Crons quotidiens

Un cron à 4h sur chaque machine génère la liste des paquets installés pour
traçabilité :

- **ThinkCentre / NAS** : `dpkg --get-selections`
- **Acer AG15** : `pacman -Q` + `pacman -Qm` (AUR)

## Sécurité

- Les clés SSH et GPG sont **exclues** des backups UrBackup (le NAS n'a pas de
  chiffrement disque).
- Un script séparé chiffre ces clés en GPG AES256 et les envoie mensuellement
  sur le NAS avec rotation 3 versions.

## Composants & versions

| Composant | Version |
|---|---|
| UrBackup Server | 2.5.x (Docker) |
| UrBackup Agent | dernière (paquet) |

## Licence

Fourni tel quel, à des fins d'exemple et de réutilisation. Adapter les valeurs de
configuration à son propre environnement avant tout déploiement.