# Home Assistant — Domotique

Plateforme domotique du homelab, déployée en mode **Supervised** sur le
**ThinkCentre M73** (Debian 13 Trixie) :
[Home Assistant](https://www.home-assistant.io/) gère l'ensemble de
l'automatisation du domicile, avec des addons pour les capteurs ESP, le MQTT,
le streaming vidéo et l'administration.

> Home Assistant Supervised est géré par le Supervisor (conteneur Docker
> `hassio_supervisor`). Les addons sont des conteneurs Docker gérés
> automatiquement — pas de compose manuel.

## Fonctionnalités

- **Home Assistant Supervised** : installation officielle sur Debian, avec
  gestion automatique des conteneurs par le Supervisor.
- **ESPHome** : programmation et gestion OTA des capteurs/actionneurs ESP8266 /
  ESP32 sans écrire de code.
- **Mosquitto** : broker MQTT pour la communication entre les appareils IoT et
  Home Assistant.
- **go2rtc** : passerelle de streaming vidéo (RTSP, WebRTC, HomeKit) pour les
  caméras.
- **File editor** : éditeur de fichiers YAML directement dans l'interface web.
- **Terminal & SSH** : accès SSH et terminal web au conteneur Home Assistant.
- **HACS** : store communautaire pour les intégrations et thèmes tiers.
- **Notifications ntfy** : événements domotiques (démarrage, arrêt, mises à jour)
  envoyés via `rest_command` natif.

## Architecture

```
ThinkCentre M73 (Debian 13)
├── hassio_supervisor (Docker, géré par systemd)
│   └── homeassistant (:8123)
│
├── Addons (conteneurs gérés par le Supervisor) :
│   ├── Mosquitto (:1883 MQTT / :8883 MQTTS)
│   ├── ESPHome (:6052)
│   ├── go2rtc (:1984 API / :8554 RTSP)
│   ├── Terminal & SSH (:22 interne)
│   ├── File editor (web intégré)
│   └── MariaDB (arrêté)
│
└── Accès externe : ha.domain.fr
    └── NPM → homeassistant:8123 (auth native HA, pas Authelia)
```

## Addons installés

| Addon | Version | État | Rôle |
|---|---|---|---|
| ESPHome Device Builder | 2026.6.5 | Actif | Gestion OTA des capteurs ESP |
| Mosquitto broker | 7.1.0 | Actif | Broker MQTT |
| go2rtc | 1.9.14 | Actif | Streaming vidéo |
| Terminal & SSH | 10.3.0 | Actif | Accès SSH/terminal web |
| File editor | 6.0.0 | Actif | Éditeur de configuration YAML |
| MariaDB | 3.0.1 | Arrêté | Base SQL (non utilisée actuellement) |
| Get HACS | 1.3.1 | Arrêté | Installeur HACS (one-shot) |

## Structure du dépôt

| Chemin | Rôle |
|---|---|
| [`configuration.yaml.example`](configuration.yaml.example) | Configuration Home Assistant anonymisée |
| [`secrets.yaml.example`](secrets.yaml.example) | Secrets (tokens, mots de passe) — modèle |

> Les fichiers `configuration.yaml`, `secrets.yaml`, `automations.yaml`,
> `scripts.yaml` et `scenes.yaml` contiennent des données personnelles et des
> secrets — ne **jamais** les committer tels quels. Utiliser les `.example`
> comme modèles.

## Accès

| URL | Méthode | Authelia |
|---|---|---|
| `https://ha.domain.fr` | NPM → homeassistant:8123 | Non (auth native HA) |
| `http://192.168.1.5:8123` | Direct LAN | Non |

Home Assistant utilise sa propre authentification (comptes locaux, MFA TOTP) —
il n'est **pas** protégé par Authelia car HA gère nativement ses sessions et
l'authentification externe casserait certaines intégrations (app mobile,
Companion).

## Installation depuis Debian 13 neuf

### Prérequis

- Debian 13 (Trixie) installé avec un utilisateur sudoer.
- Connexion réseau fonctionnelle.
- Docker Engine installé depuis le repo officiel (pas le paquet Debian) :

```bash
# Ajouter le repo Docker officiel
sudo apt install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/debian trixie stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker $USER
```

### 1. Dépendances HA Supervised

```bash
sudo apt install -y \
  apparmor cifs-utils curl dbus jq libglib2.0-bin lsb-release \
  network-manager nfs-common systemd-journal-remote systemd-resolved \
  udisks2 wget bluez
```

> Le paquet `bluez` est nécessaire même sans périphérique Bluetooth — le
> Supervisor vérifie sa présence au démarrage.

### 2. OS Agent

```bash
wget https://github.com/home-assistant/os-agent/releases/download/1.9.0/os-agent_1.9.0_linux_x86_64.deb
sudo dpkg -i os-agent_1.9.0_linux_x86_64.deb

# Vérifier
gdbus introspect --system --dest io.hass.os --object-path /io/hass/os
# Doit afficher "Version = '1.9.0'"
```

### 3. Home Assistant Supervised

```bash
wget https://github.com/home-assistant/supervised-installer/releases/latest/download/homeassistant-supervised.deb
sudo dpkg -i homeassistant-supervised.deb
# Sélectionner : generic-x86-64
```

Patienter plusieurs minutes le temps que le Supervisor télécharge les images
Docker (core, cli, dns, audio, multicast, observer). Vérifier l'avancement :

```bash
docker ps
# Attendre que le conteneur homeassistant soit UP
```

L'interface web est accessible sur `http://<IP>:8123` pour la configuration
initiale (création du compte admin, restauration d'un backup éventuel).

### 4. Résoudre les conflits DNS (si applicable)

`systemd-resolved` peut bloquer le port 53 si AdGuard est sur une autre machine.
Si le DNS ne fonctionne plus après l'installation :

```bash
sudo systemctl stop systemd-resolved
sudo systemctl disable systemd-resolved
# Vérifier que /etc/resolv.conf pointe vers le bon DNS (AdGuard)
```

## Notifications ntfy

Home Assistant envoie des notifications via un `rest_command` natif défini dans
`configuration.yaml` :

```yaml
rest_command:
  ntfy:
    url: https://ntfy.<CHANGE_ME_DOMAIN>/<CHANGE_ME_TOPIC>
    method: POST
    headers:
      Authorization: "Bearer <CHANGE_ME_TOKEN>"
      Title: "{{ title }}"
      Priority: "{{ priority | default('3') }}"
      Tags: "{{ tags | default('house') }}"
    payload: "{{ message }}"
```

> La valeur du header `Authorization` dans `secrets.yaml` doit être écrite
> **sans guillemets** supplémentaires pour éviter une erreur de parsing YAML.

Exemples d'automatisations envoyant des notifications :
- Démarrage / arrêt de Home Assistant.
- Mises à jour disponibles (core, OS, addons).
- Événements domotiques personnalisés.

## Sauvegarde

- **Backup HA intégré** : snapshots automatiques gérés par le Supervisor.
- **UrBackup** : le répertoire `/var/lib/homeassistant` est inclus dans les
  backups fichiers hebdomadaires du ThinkCentre vers le NAS — voir
  [`urbackup/`](../urbackup/).

## Sécurité

- L'accès externe (`ha.domain.fr`) passe par le certificat wildcard Let's
  Encrypt via NPM, avec HTTPS obligatoire.
- Le Supervisor et les addons sont des conteneurs Docker isolés, gérés
  automatiquement (pas de compose manuel à maintenir).
- Les secrets (tokens, mots de passe) sont dans `secrets.yaml`, jamais en dur
  dans `configuration.yaml`.

## Dépannage

| Symptôme | Cause probable | Solution |
|---|---|---|
| Supervisor unhealthy | Réseau Docker corrompu après reboot | `ha supervisor repair` ou redémarrer Docker |
| Addon ne démarre pas | Image Docker corrompue | `ha addons rebuild <slug>` |
| App mobile ne se connecte pas en externe | Certificat ou URL externe mal configuré | Vérifier `external_url` dans la config HA |
| ESPHome OTA échoue | Firewall bloque le port 6053 entre HA et l'ESP | Vérifier nftables / règles bridges Docker |

## Composants & versions

| Composant | Version |
|---|---|
| Home Assistant Supervised | dernière |
| ESPHome | 2026.6.5 |
| Mosquitto | 7.1.0 |
| go2rtc | 1.9.14 |
| Terminal & SSH | 10.3.0 |
| File editor | 6.0.0 |

## Licence

Fourni tel quel, à des fins d'exemple et de réutilisation. Adapter les valeurs de
configuration à son propre environnement avant tout déploiement.