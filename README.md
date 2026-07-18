# Documentation homelab

> 🟢 Ce homelab est **100 % open source** - tous les logiciels et outils utilisés sont des projets libres et gratuits (FOSS).

<div align="center">
  <img src="https://img.shields.io/badge/Status-En%20construction-orange?logo=githubactions&logoColor=white" alt="Status">
  <img src="https://img.shields.io/github/last-commit/jbabin49/Homelab?logo=git&logoColor=white&label=Dernier%20commit" alt="Dernier commit">
  <br><br>
  <img src="https://img.shields.io/badge/Domotique-Home%20Assistant-41BDF5?logo=homeassistant&logoColor=white" alt="Domotique">
  <img src="https://img.shields.io/badge/Containers-Docker-2496ED?logo=docker&logoColor=white" alt="Containers">
  <img src="https://img.shields.io/badge/NAS-OpenMediaVault-5DA1D9?logo=openmediavault&logoColor=white" alt="NAS">
  <img src="https://img.shields.io/badge/Monitoring-Zabbix-D40000?logo=zabbix&logoColor=white" alt="Monitoring">
  <img src="https://img.shields.io/badge/Dashboards-Grafana-F46800?logo=grafana&logoColor=white" alt="Dashboards">
  <img src="https://img.shields.io/badge/TSDB-TimescaleDB-FDB515?logo=timescale&logoColor=black" alt="TSDB">
  <img src="https://img.shields.io/badge/DNS-AdGuard%20Home-68BC71?logo=adguard&logoColor=white" alt="DNS">
  <img src="https://img.shields.io/badge/Proxy-Nginx%20Proxy%20Manager-F15833?logo=nginxproxymanager&logoColor=white" alt="Proxy">
  <img src="https://img.shields.io/badge/Auth-Authelia-113155?logo=authelia&logoColor=white" alt="Auth">
  <img src="https://img.shields.io/badge/VPN-WireGuard-88171A?logo=wireguard&logoColor=white" alt="VPN">
  <img src="https://img.shields.io/badge/Bastion-Apache%20Guacamole-578068?logo=apache&logoColor=white" alt="Bastion">
  <img src="https://img.shields.io/badge/Git-Gitea-609926?logo=gitea&logoColor=white" alt="Git">
  <img src="https://img.shields.io/badge/Backups-UrBackup-1D3C6E?logo=databricks&logoColor=white" alt="Backups">
  <img src="https://img.shields.io/badge/Notifications-ntfy-317F6F?logo=ntfy&logoColor=white" alt="Notifications">
  <img src="https://img.shields.io/badge/CDN%2FTLS-Cloudflare-F38020?logo=cloudflare&logoColor=white" alt="Cloudflare">
  <img src="https://img.shields.io/badge/Media-Plex-E5A00D?logo=plex&logoColor=white" alt="Plex">
  <img src="https://img.shields.io/badge/OS-Linux-FCC624?logo=linux&logoColor=black" alt="Linux">
  <img src="https://img.shields.io/badge/FOSS-100%25%20Open%20Source-brightgreen?logo=opensourceinitiative&logoColor=white" alt="FOSS">
</div>

## 📋 Vue d'ensemble

Homelab auto-hébergé articulé autour d'un serveur principal, d'un NAS, de deux
Raspberry Pi et d'un VPS bastion. Tous les services sont conteneurisés (Docker)
ou déployés en binaires/systemd, supervisés par Zabbix et accessibles à distance
via un tunnel WireGuard sans ouvrir le moindre port entrant côté maison.

- **Réseau interne** : domaines `*.home.lab` résolus par AdGuard Home et routés
  par Nginx Proxy Manager (TLS auto-signé), protégés par Authelia (2FA TOTP).
- **Exposition internet** : domaines `*.domain.fr` en Let's Encrypt (challenge
  DNS Cloudflare), point d'entrée unique via le VPS bastion + Cloudflare.
- **Accès distant** : Apache Guacamole (SSH / RDP / VNC dans le navigateur) sur
  le bastion, relié au LAN par WireGuard.

## 🗺️ Architecture

<div align="center">
  <img src=".github/images/schema_architecture.png" alt="Schéma d'architecture du homelab" width="100%">
</div>

## 🧰 Matériel et services

### 🖥️ [![ThinkCentre M73](https://img.shields.io/badge/ThinkCentre%20M73-41BDF5?logo=lenovo&logoColor=white)](https://www.lenovo.com/) - Serveur principal

AMD Athlon II X4 640 · 8 Go DDR3 · 465 Go · **Debian 13 (Trixie)**

Serveur central du homelab, hébergeant Home Assistant Supervised et quatre
stacks Docker indépendantes :

* **[Home Assistant Supervised](homeassistant/)** pour la domotique (addons :
  ESPHome, Mosquitto, go2rtc, SSH, HACS) — accès via `ha.domain.fr`
* **[Authelia](authelia/) + Redis** — authentification centralisée 2FA TOTP
* **[Nginx Proxy Manager](nginx-proxy-manager/)** — reverse proxy centralisé
  (`*.home.lab` auto-signé, `*.domain.fr` Let's Encrypt via Cloudflare DNS)
* **[Zabbix Server 7.0 + TimescaleDB + Grafana](monitoring/)** — supervision de
  l'ensemble du homelab (5 agents, monitoring SSL, alertes ntfy)
* **[Ntfy](ntfy/)** — notifications push self-hosted, exposé via le VPS bastion

Hardening : nftables (policy drop), SSH clé ed25519 uniquement, Fail2ban,
unattended-upgrades, journald limité, docker prune hebdomadaire.

### 💾 [![ThinkCentre M75e](https://img.shields.io/badge/ThinkCentre%20M75e-41BDF5?logo=lenovo&logoColor=white)](https://www.lenovo.com/) - NAS

2 × disques en RAID 1 (md0, ext4, ~2.2 To) · **OpenMediaVault 8.5.1 (Synchrony)**
sur Debian 13

* **[UrBackup Server](urbackup/)** (conteneur Docker) — backups centralisés
  fichiers et images disque du ThinkCentre et du poste de travail
* **Plex Media Server** (conteneur Docker) — diffusion de médias
* **Zabbix Agent2** (systemd) — supervision par le serveur Zabbix

### 🧩 [![Raspberry Pi](https://img.shields.io/badge/Raspberry%20Pi-A22082?logo=raspberrypi&logoColor=white)](https://www.raspberrypi.org/)

**RPi 3B - AdGuard & WireGuard** · Debian 13 (Trixie) aarch64

* **[AdGuard Home](adguard-home/)** (binaire standalone) — DNS filtré pour tout
  le réseau, réécriture `*.home.lab` vers le ThinkCentre, alertes et rapports
  quotidiens via [ntfy](ntfy/)
* **[wg-easy](wgeasy/)** (conteneur Docker) — serveur WireGuard avec interface
  web, utilisé par le VPS bastion pour rejoindre le LAN
* **Zabbix Agent2** (systemd) — supervision par le serveur Zabbix

**RPi 3B - [Gitea](gitea/)** · Raspberry Pi OS Lite (Trixie 32-bit)

* **Gitea 1.26.4** (binaire standalone) — hébergement Git self-hosted avec wiki
  Markdown, données stockées sur le NAS via NFS
* **Zabbix Agent2** (systemd) — supervision par le serveur Zabbix

### ☁️ [![OVH VPS](https://img.shields.io/badge/OVH-VPS-123F6D?logo=ovh&logoColor=white)](https://www.ovhcloud.com/) - [Bastion](bastion-vps/)

VPS Debian 13 servant de **bastion d'administration à distance** et de point
d'entrée internet pour les services exposés :

* **Apache Guacamole** (conteneurs Docker) — accès web SSH / RDP / VNC, sans
  client lourd
* **Client WireGuard** vers le wg-easy du RPi : le VPS rejoint le LAN sans
  ouvrir aucun port entrant côté maison
* **Nginx reverse proxy** pour Guacamole et [ntfy](ntfy/) — TLS via Cloudflare
  (Full strict + Authenticated Origin Pulls + Cloudflare Access) et Let's Encrypt
* Stack Docker durcie (réseaux `internal`, secrets, `cap_drop`, `read_only`,
  images pinnées) et hardening de l'hôte (SSH par clé, UFW, Fail2ban)

## 📦 Stacks documentées

| Stack | Hôte | Description |
|-------|------|-------------|
| [Home Assistant](homeassistant/) | ThinkCentre M73 | Domotique (Supervised) + addons ESPHome, Mosquitto, go2rtc |
| [Authelia](authelia/) | ThinkCentre M73 | Authentification centralisée 2FA (TOTP) + Redis |
| [Nginx Proxy Manager](nginx-proxy-manager/) | ThinkCentre M73 | Reverse proxy, TLS interne et Let's Encrypt |
| [Monitoring](monitoring/) | ThinkCentre M73 | Zabbix Server 7.0 + TimescaleDB + Grafana |
| [Ntfy](ntfy/) | ThinkCentre M73 | Notifications push self-hosted |
| [UrBackup](urbackup/) | NAS OMV | Backups centralisés fichiers + images disque |
| [AdGuard Home](adguard-home/) | RPi 3B | DNS filtré réseau + réécriture `*.home.lab` |
| [wg-easy](wgeasy/) | RPi 3B | Serveur WireGuard (interface web) |
| [Gitea](gitea/) | RPi 3B | Hébergement Git self-hosted + wiki |
| [Bastion VPS](bastion-vps/) | OVH VPS | Apache Guacamole durci + Cloudflare |

## 🔐 Bastion / accès distant

La stack complète du bastion (Guacamole + WireGuard + Nginx/Cloudflare) est
documentée dans [bastion-vps/](bastion-vps/).

## Licence

Ce projet est distribué sous licence [GPL-3.0](./LICENSE).