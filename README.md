# Documentation homelab

> 🟢 Ce homelab est **100 % open source** — tous les logiciels et outils utilisés sont des projets libres et gratuits (FOSS).

<div align="center">
  <img src="https://img.shields.io/badge/Status-En%20construction-orange?logo=githubactions&logoColor=white" alt="Status">
  <img src="https://img.shields.io/github/last-commit/jbabin49/Homelab?logo=git&logoColor=white&label=Dernier%20commit" alt="Dernier commit">
  <br><br>
  <img src="https://img.shields.io/badge/Domotique-Home%20Assistant%20OS-41BDF5?logo=homeassistant&logoColor=white" alt="Domotique">
  <img src="https://img.shields.io/badge/Containers-Docker-2496ED?logo=docker&logoColor=white" alt="Containers">
  <img src="https://img.shields.io/badge/Virtualisation-Proxmox%20VE-E57000?logo=proxmox&logoColor=white" alt="Virtualisation">
  <img src="https://img.shields.io/badge/Monitoring-Prometheus-E6522C?logo=prometheus&logoColor=white" alt="Monitoring">
  <img src="https://img.shields.io/badge/Dashboards-Grafana-F46800?logo=grafana&logoColor=white" alt="Dashboards">
  <img src="https://img.shields.io/badge/DNS-AdGuard%20Home-68BC71?logo=adguard&logoColor=white" alt="DNS">
  <img src="https://img.shields.io/badge/Proxy-Nginx%20Proxy%20Manager-F15833?logo=nginxproxymanager&logoColor=white" alt="Proxy">
  <img src="https://img.shields.io/badge/Web%20server-Nginx-009639?logo=nginx&logoColor=white" alt="Web server">
  <img src="https://img.shields.io/badge/Auth-Authelia-113155?logo=authelia&logoColor=white" alt="Auth">
  <img src="https://img.shields.io/badge/VPN-Wireguard-88171A?logo=wireguard&logoColor=white" alt="VPN">
  <img src="https://img.shields.io/badge/Bastion-Apache%20Guacamole-578068?logo=apache&logoColor=white" alt="Bastion">
  <img src="https://img.shields.io/badge/CDN%2FTLS-Cloudflare-F38020?logo=cloudflare&logoColor=white" alt="Cloudflare">
  <img src="https://img.shields.io/badge/Media-Plex-E5A00D?logo=plex&logoColor=white" alt="Plex">
  <img src="https://img.shields.io/badge/OS-Linux-FCC624?logo=linux&logoColor=black" alt="Linux">
  <img src="https://img.shields.io/badge/FOSS-100%25%20Open%20Source-brightgreen?logo=opensourceinitiative&logoColor=white" alt="FOSS">
</div>

## 🧰 Matériel et services

### 🖥️ [![ThinkCentre M73](https://img.shields.io/badge/ThinkCentre%20M73-41BDF5?logo=lenovo&logoColor=white)](https://www.lenovo.com/)
* Home Assistant OS
* Prometheus et Grafana installés dans des conteneurs Docker pour monitorer les différents services et serveurs de mon homelab

### 💾 [![ThinkCentre M75e](https://img.shields.io/badge/ThinkCentre%20M75e-41BDF5?logo=lenovo&logoColor=white)](https://www.lenovo.com/)
* OpenMediaVault (OMV) pour gérer le stockage en réseau (NAS) avec deux disques Seagate Constellation ES.3 de 3To en RAID1 pour la redondance des données
* Plex Media Server (conteneur Docker) pour gérer et diffuser ma bibliothèque de médias sur mes différents appareils
* Btop (conteneur Docker) pour avoir un visuel rapide des ressources du NAS (CPU, RAM, Disque, Réseau)

### 🧩 [![Raspberry Pi](https://img.shields.io/badge/Raspberry%20Pi-A22082?logo=raspberrypi&logoColor=white)](https://www.raspberrypi.org/)
* Un Raspberry Pi3B avec Raspberry Pi OS Lite :
    - Adguard Home (paquet debian) pour le blocage de la publicité au niveau du réseau installé
    - Nginx serveur web (conteneur Docker) pour héberger un dashboard pour centraliser les accès à mes différentes applications et services
    - wg-easy pour le VPN WireGuard (conteneur Docker) pour accéder à mon homelab à distance de manière sécurisée
* Un deuxième Raspberry Pi3B avec Raspberry Pi OS Lite :
    - Nginx Proxy Manager (conteneur Docker) pour gérer les redirections de ports et les certificats SSL de mes différentes applications et services
    - Authelia (conteneur Docker) pour gérer l'authentification de mes différentes applications et services avec redis (conteneur Docker) pour stocker les sessions et les utilisateurs

### 🧪 [![Proxmox VE](https://img.shields.io/badge/Proxmox%20VE-FF0000?logo=proxmox&logoColor=white)](https://www.proxmox.com/en/proxmox-ve)
Pour faire de la virtualisation et héberger des machines virtuelles pour différents usages (serveur web, serveur de jeux, etc.)
#### ⚙️ Hardware
* AMD FX-6300 3.5GHz
* 16Go de RAM DDR3 1600MHz
* Port RJ45 10/100/1000Mbps de la CM
* 1 carte double RJ45 1000Mbps

### ☁️ [![OVH VPS](https://img.shields.io/badge/OVH-VPS-123F6D?logo=ovh&logoColor=white)](https://www.ovhcloud.com/)
Un VPS sous Debian sert de **bastion d'administration à distance** pour accéder à mon homelab depuis l'extérieur de façon sécurisée :
* Apache Guacamole (conteneurs Docker) pour l'accès web SSH / RDP / VNC à mes machines, sans client lourd
* Client WireGuard vers le wg-easy de la maison : le VPS rejoint le LAN sans ouvrir aucun port entrant côté maison
* Nginx reverse proxy derrière Cloudflare (Full strict + Authenticated Origin Pulls + Cloudflare Access)
* Stack Docker durcie (réseaux `internal`, secrets, `cap_drop`, `read_only`, images pinnées) et hardening de l'hôte (SSH par clé, UFW, Fail2ban)

## 🔐 Bastion / accès distant
La stack complète du bastion (Guacamole + WireGuard + Nginx/Cloudflare) est documentée ici :
- [Documentation et déploiement du bastion](https://github.com/jbabin49/Homelab/tree/main/bastion-vps)

## 📈 Monitoring
La stack Prometheus + VictoriaMetrics + Grafana est documentée ici:
- [Documentation de l'installation et de la configuration](https://github.com/jbabin49/Homelab/tree/main/prometheus-grafana)
- [La release prometheus-grafana-v1.0.0](https://github.com/jbabin49/Homelab/releases/tag/prometheus-grafana-release-v1.0.0)
