# AdGuard Home — DNS filtré

Serveur DNS filtré du homelab, déployé sur un **Raspberry Pi 3B** (Debian 13
Trixie aarch64) : [AdGuard Home](https://adguard.com/fr/adguard-home/overview.html)
bloque les publicités et trackers au niveau DNS pour tout le réseau, et redirige
les domaines internes (`*.home.lab`) vers le ThinkCentre M73.

> Toutes les valeurs sensibles (domaines, IP, identifiants) sont des exemples
> fictifs. Remplacer les `<...>` avant de déployer.

## Fonctionnalités

- **Filtrage DNS réseau** : blocage publicitaire et trackers pour tous les
  appareils du LAN, sans configuration côté client.
- **Réécriture DNS interne** : `*.home.lab` et `home.lab` pointent vers le
  ThinkCentre M73 (reverse proxy NPM).
- **Alertes ntfy** : check horaire (service down, filtrage désactivé, taux de
  blocage anormal) + rapport quotidien 8h (stats, top domaines, top clients).
- **Mises à jour intégrées** : AdGuard Home gère ses propres mises à jour via
  son mécanisme intégré (pas de gestionnaire de paquets).

## Architecture

```
Routeur (DNS primaire → 192.168.1.2)
   │
   ▼
RPi AdGuard (192.168.1.2)
└── AdGuard Home (binaire standalone)
    ├── :53      DNS (UDP/TCP)
    ├── :80      Interface web admin
    ├── Filtrage (listes de blocage)
    └── Réécriture *.home.lab → 192.168.1.5
```

## Structure du dépôt

| Chemin | Rôle |
|---|---|
| [`AdGuardHome.yaml.example`](AdGuardHome.yaml.example) | Configuration AdGuard Home anonymisée |
| [`scripts/adguard-ntfy.sh`](scripts/adguard-ntfy.sh) | Script d'alertes et rapports ntfy |
| [`systemd/adguard-ntfy-check.service`](systemd/adguard-ntfy-check.service) | Service systemd — check horaire |
| [`systemd/adguard-ntfy-check.timer`](systemd/adguard-ntfy-check.timer) | Timer systemd — déclenchement horaire |
| [`systemd/adguard-ntfy-report.service`](systemd/adguard-ntfy-report.service) | Service systemd — rapport quotidien |
| [`systemd/adguard-ntfy-report.timer`](systemd/adguard-ntfy-report.timer) | Timer systemd — déclenchement quotidien 8h |

> Le fichier `AdGuardHome.yaml` contient le hash du mot de passe admin et ne
> doit **jamais** être committé tel quel — utiliser le `.example` comme modèle.

## Installation

AdGuard Home est installé en binaire standalone dans `/opt/AdGuardHome/` :

```bash
curl -s -S -L https://raw.githubusercontent.com/AdguardTeam/AdGuardHome/master/scripts/install.sh | sh -s -- -v
```

L'interface web est accessible sur le port `80` pour la configuration initiale
(choix des listes de filtrage, mot de passe admin, ports DNS).

## DNS — configuration réseau

| Équipement | Configuration |
|---|---|
| Routeur | DNS primaire → `192.168.1.2`, secondaire `1.1.1.1`, tertiaire `9.9.9.9` |
| AdGuard | Réécriture `*.home.lab` → `192.168.1.5` |
| AdGuard | Réécriture `home.lab` → `192.168.1.5` |
| Poste de travail | DNS primaire via DHCP (AdGuard), résolu `home.lab` via systemd-resolved |

## Alertes ntfy

Le script `/opt/scripts/adguard-ntfy.sh` interroge l'API REST AdGuard Home
(`/control/stats`, `/control/status`) avec Basic Auth et envoie des notifications
[ntfy](../ntfy/) :

| Timer systemd | Fréquence | Action |
|---|---|---|
| `adguard-ntfy-check.timer` | Horaire | Alerte si service down, filtrage désactivé, ou taux de blocage anormal (< 5% ou > 80%) |
| `adguard-ntfy-report.timer` | Quotidien 8h | Rapport : requêtes, taux de blocage, temps moyen, top 5 domaines / bloqués / clients |

AdGuard Home ne supporte qu'un seul compte admin — pas de comptes secondaires ni
d'API keys. Le script utilise le Basic Auth de ce compte unique.

### Déploiement des alertes ntfy

```bash
# Copier le script
sudo mkdir -p /opt/scripts
sudo cp scripts/adguard-ntfy.sh /opt/scripts/
sudo chmod +x /opt/scripts/adguard-ntfy.sh
# Renseigner NTFY_TOKEN, ADGUARD_USER, ADGUARD_PASS dans le script

# Copier les services et timers
sudo cp systemd/*.service systemd/*.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now adguard-ntfy-check.timer
sudo systemctl enable --now adguard-ntfy-report.timer

# Vérifier
systemctl list-timers | grep adguard
```

## Sécurité

- La config AdGuard Home (`/opt/AdGuardHome/AdGuardHome.yaml`) contient le hash
  du mot de passe admin — ne **pas** la committer telle quelle.
- L'interface web (port `80`) n'est pas protégée par Authelia — l'accès est
  restreint au LAN uniquement.
- Le script ntfy contient le token et le mot de passe admin AdGuard en clair —
  droits `700` recommandés.

## Composants & versions

| Composant | Version |
|---|---|
| Debian | 13 (Trixie) aarch64 |
| Kernel | 6.12 LTS |
| AdGuard Home | dernière (binaire standalone) |
| Zabbix Agent2 | 7.0 (systemd) |

## Licence

Fourni tel quel, à des fins d'exemple et de réutilisation. Adapter les valeurs de
configuration à son propre environnement avant tout déploiement.