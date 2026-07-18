# Monitoring — Zabbix + TimescaleDB + Grafana

Stack Docker prête à déployer pour superviser l'intégralité du homelab :
[Zabbix Server 7.0](https://www.zabbix.com/) collecte les métriques de tous les
équipements, [TimescaleDB](https://www.timescale.com/) (extension PostgreSQL)
stocke l'historique, et [Grafana](https://grafana.com/) fournit les tableaux de
bord. Un **Zabbix Agent2 conteneurisé** (privileged, pid:host) supervise la
machine hôte elle-même.

> Toutes les valeurs sensibles (domaines, IP, identifiants) sont des exemples
> fictifs. Remplacer les `<...>` avant de déployer.

## Fonctionnalités

- **Zabbix Server 7.0** (Alpine) avec frontend Nginx et agent2 intégrés dans le
  même compose.
- **TimescaleDB 2.18** sur PostgreSQL 16 : hypertables pour l'historique et les
  trends, rétention configurable.
- **Grafana 11.6** connecté en direct à la base PostgreSQL et via le plugin
  `alexanderzobnin-zabbix-app`.
- **Supervision SSL** : template custom avec trois seuils d'alerte (30 j Warning,
  15 j High, 2 j Disaster) sur tous les proxy hosts NPM.
- **Alertes ntfy** : webhook media type JavaScript avec priorité et tags
  dynamiques (problem / resolved).
- **Secrets Docker** : mots de passe PostgreSQL et Grafana stockés dans des
  fichiers, jamais en variable d'environnement en clair.

## Architecture

```
                  ┌──────────────────────────────────────────┐
                  │            zabbix_internal               │
                  │                                          │
                  │  TimescaleDB ◄── Zabbix Server (:10051)  │
                  │       │              │                    │
                  │       └──► Grafana   │                    │
                  │            (:3000)   │                    │
                  │                      │                    │
                  │         Zabbix Web (:8080)                │
                  │         Zabbix Agent2 (privileged)        │
                  └──────────────────────────────────────────┘
                             │              │
                        proxy_net      port 10051
                        (NPM)          (agents distants)
```

## Structure du dépôt

| Chemin | Rôle |
|---|---|
| [`docker-compose.yml`](docker-compose.yml) | Stack complète : Zabbix Server + Web + TimescaleDB + Grafana + Agent2 |
| [`secrets/db_password.txt.example`](secrets/db_password.txt.example) | Mot de passe PostgreSQL (exemple) |
| [`secrets/grafana_password.txt.example`](secrets/grafana_password.txt.example) | Mot de passe admin Grafana (exemple) |

> Le répertoire `secrets/` contient les mots de passe en clair et n'est **pas**
> versionné. Le [`.gitignore`](.gitignore) l'exclut.

## Démarrage rapide

```bash
cd ~/docker/zabbix

# 1. Générer les secrets
mkdir -p secrets && chmod 700 secrets
openssl rand -base64 32 | tr -d '\n' > secrets/db_password.txt
openssl rand -base64 32 | tr -d '\n' > secrets/grafana_password.txt
chmod 644 secrets/*.txt

# 2. Lancer la stack
docker compose up -d

# 3. Attendre l'initialisation du schéma
docker compose logs -f zabbix-server   # attendre "database is up to date"

# 4. Activer TimescaleDB
docker exec -it zabbix-server \
  cat /usr/share/doc/zabbix-server-postgresql/timescaledb.sql \
  | docker exec -i zabbix-postgres psql -U zabbix -d zabbix
docker compose restart zabbix-server
```

Zabbix Web écoute alors sur `proxy_net` au port `8080`, Grafana sur `3000` —
aucun des deux n'est exposé directement sur l'hôte. L'accès se fait
exclusivement via les proxy hosts NPM (`zabbix.home.lab`, `grafana.home.lab`),
protégés par [Authelia](../authelia-npm/).

## Agents Zabbix

| Hôte | IP | Mode | Installation |
|---|---|---|---|
| ThinkCentre M73 | localhost | Passif (conteneur privileged, pid:host) | Docker |
| NAS OMV | `192.168.1.10` | Passif | Paquet systemd |
| RPi AdGuard | `192.168.1.2` | Passif | Paquet systemd |
| VPS Bastion | `<IP_WG_VPS>` (WireGuard) | **Actif** | Paquet systemd |
| RPi 2 (Gitea) | `192.168.1.11` | Passif | Paquet systemd |

Le VPS est en mode **actif** car le serveur Zabbix (en conteneur) n'a pas d'IP
WireGuard et ne peut pas joindre le VPS directement — c'est l'agent qui pousse
ses données.

Pour les agents sur le NAS, les IP des bridges Docker du ThinkCentre doivent être
ajoutées dans la directive `Server=` car le serveur Zabbix sort via ces adresses
(les CIDR ne sont pas supportés — uniquement des IP explicites).

## Monitoring SSL

Un template custom supervise les certificats de tous les proxy hosts avec la clé
`web.certificate.get[{$SSL_HOST}]` (type **Zabbix Agent**, pas Simple Check — le
serveur Alpine ne supporte pas `web.certificate.get` en Simple Check).

| Seuil | Sévérité |
|---|---|
| < 30 jours | Warning |
| < 15 jours | High |
| < 2 jours | Disaster |

Le calcul des jours restants utilise le timestamp Unix `$.x509.not_after.timestamp`
(pas la date texte qui n'est pas parsable par `new Date()`). La macro `{$SSL_HOST}`
porte le domaine — ne pas utiliser `{HOST.CONN}`.

## Sécurité

- Ne **jamais** committer `secrets/` — le [`.gitignore`](.gitignore) l'exclut.
- Les mots de passe sont passés via `*_PASSWORD_FILE` (Docker secrets), jamais en
  variable d'environnement en clair.
- `no-new-privileges` activé sur tous les conteneurs sauf l'agent2 (qui nécessite
  `privileged` pour l'accès au filesystem et aux processus de l'hôte).
- Zabbix Web et Grafana sont sur `proxy_net` sans port exposé : l'accès passe
  obligatoirement par NPM + Authelia.

## Dépannage

| Symptôme | Cause probable | Solution |
|---|---|---|
| `relation "history" does not exist` | Script TimescaleDB lancé avant la fin de l'init | Attendre `database is up to date` dans les logs du server, puis relancer le script |
| Agent VPS unreachable | Mode passif au lieu d'actif | Configurer `StartAgents=0` et `ServerActive=` sur l'agent VPS |
| Item SSL `NOTSUPPORTED` | Type Simple Check sur serveur Alpine | Passer en type Zabbix Agent avec macro `{$SSL_HOST}` |
| JSONPath ne retourne rien | `$.result.*` au lieu de `$.x509.*` | Utiliser `$.x509.not_after.timestamp` |
| TimescaleDB non détecté dans System Information | Bug d'affichage frontend | Vérifier `SELECT * FROM _timescaledb_catalog.hypertable;` — les hypertables existent |

## Composants & versions

| Composant | Version |
|---|---|
| Zabbix Server / Web | alpine-7.0-latest |
| TimescaleDB | 2.18.0-pg16 |
| Grafana | 11.6.0 |
| Zabbix Agent2 | alpine-7.0-latest |
| Plugin Grafana Zabbix | alexanderzobnin-zabbix-app |

## Licence

Fourni tel quel, à des fins d'exemple et de réutilisation. Adapter les valeurs de
configuration à son propre environnement avant tout déploiement.