# Ntfy — Notifications push self-hosted

Serveur de notifications push déployé sur le **ThinkCentre M73** (Debian 13
Trixie) et exposé sur internet via le **VPS bastion** :
[ntfy](https://ntfy.sh/) reçoit les alertes de tous les services du homelab et les
pousse vers les appareils mobiles et le bureau, à travers un tunnel WireGuard,
un reverse proxy Nginx et un certificat Let's Encrypt.

> Toutes les valeurs sensibles (domaines, IP, identifiants) sont des exemples
> fictifs. Remplacer les `<...>` avant de déployer.

## Fonctionnalités

- **Notifications push unifiées** pour tous les services du homelab.
- **Authentification deny-all** : chaque service dispose de son propre
  utilisateur et token ntfy pour le cloisonnement.
- **Exposition internet sécurisée** via le VPS bastion (Nginx + Let's Encrypt +
  WireGuard) — le DNS doit être en mode **DNS only** sur Cloudflare (pas de
  proxy orange, nécessaire pour les WebSockets push).
- **Conteneur durci** : `no-new-privileges`, limites mémoire (256 Mo) et CPU
  (0.5 cœur).

## Architecture

```
Appareils (mobile, bureau)
   │  HTTPS / WebSocket
   ▼
VPS bastion : Nginx (443, Let's Encrypt)
   │  WireGuard
   ▼
ThinkCentre M73 : ntfy (:8090 → :80 conteneur)
```

## Structure du dépôt

| Chemin | Rôle |
|---|---|
| [`docker-compose.yml`](docker-compose.yml) | Ntfy v2.11.0 |
| [`config/server.yml.example`](config/server.yml.example) | Configuration serveur anonymisée |

> Les fichiers `config/server.yml`, `data/` et `cache/` ne sont **pas**
> versionnés. Le [`.gitignore`](.gitignore) les exclut.

## Démarrage rapide

### Sur le ThinkCentre

```bash
cd ~/docker/ntfy
mkdir -p config data cache
cp config/server.yml.example config/server.yml
# Éditer server.yml : renseigner le base-url

# Lancer
docker compose up -d
docker compose logs -f ntfy   # attendre "Listening on :80"
```

### Créer l'admin et les tokens

```bash
docker exec -it ntfy ntfy user add --role=admin <admin>
docker exec -it ntfy ntfy token add <admin>
```

### Utilisateurs par service

Un utilisateur et un token par service pour le cloisonnement des droits :

| Utilisateur | Service | Topic |
|---|---|---|
| `zabbix` | Alertes monitoring | `zabbix` |
| `urbackup` | Notifications backup | `urbackup` |
| `homeassistant` | Événements domotique | `homeassistant` |
| `authelia` | Alertes sécurité auth | `authelia` |
| `bastion` | Alertes VPS | `bastion` |
| `adguard` | Checks et rapports DNS | `adguard` |
| `omv` | Alertes NAS | `omv` |

```bash
# Pour chaque service :
docker exec -it ntfy ntfy user add <service>
docker exec -it ntfy ntfy access <service> <topic> rw
docker exec -it ntfy ntfy token add <service>
```

### Sur le VPS bastion

Le vhost Nginx pour le reverse proxy ntfy se trouve dans
[`bastion-vps/nginx-ntfy.conf`](../bastion-vps/nginx-ntfy.conf). Le déployer :

```bash
sudo cp nginx-ntfy.conf /etc/nginx/sites-available/ntfy
sudo ln -s /etc/nginx/sites-available/ntfy /etc/nginx/sites-enabled/
sudo certbot --nginx -d ntfy.<domaine>
sudo nginx -t && sudo systemctl reload nginx
```

## Intégrations

| Service | Méthode | Déclencheur |
|---|---|---|
| Zabbix | Webhook media type (JavaScript, priorité dynamique) | Problem / Resolved |
| UrBackup | 4 scripts shell post-backup dans `/var/urbackup/` | Chaque backup réussi |
| Home Assistant | `rest_command` natif + automatisations YAML | Démarrage, arrêt, mises à jour |
| Authelia | Script bash + service systemd (tail logs Docker) | Échecs auth, bannissements |
| AdGuard | Script bash + 2 timers systemd | Check horaire + rapport quotidien 8h |

### Notes d'intégration

- **UrBackup** : le binaire `curl` doit être monté en read-only dans le
  conteneur (`/usr/bin/curl:/usr/bin/curl:ro`). Le système d'alertes Lua natif
  d'UrBackup ne se déclenche que sur les échecs — les scripts post-backup sont
  la bonne approche pour les succès.
- **AdGuard** : pas d'API keys ni de comptes secondaires — le script utilise le
  Basic Auth du compte admin unique.
- **Home Assistant** : la valeur du header `Authorization` dans `secrets.yaml`
  doit être écrite **sans guillemets** pour éviter une erreur de parsing.

## Sécurité

- Ne **jamais** committer `config/server.yml` (contient les tokens en base) ni
  `data/` (contient la base utilisateurs).
- `auth-default-access: deny-all` : aucun accès anonyme.
- `behind-proxy: true` : ntfy fait confiance aux headers `X-Forwarded-For` du
  reverse proxy Nginx.

## Composants & versions

| Composant | Version |
|---|---|
| Ntfy | v2.11.0 |

## Licence

Fourni tel quel, à des fins d'exemple et de réutilisation. Adapter les valeurs de
configuration à son propre environnement avant tout déploiement.