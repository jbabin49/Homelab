# Nginx Proxy Manager — Reverse proxy centralisé

Reverse proxy du homelab déployé sur le **ThinkCentre M73** (Debian 13 Trixie) :
[Nginx Proxy Manager](https://nginxproxymanager.com/) gère le routage, les
certificats SSL et la protection [Authelia](../authelia-npm/) de tous les services
internes (`*.home.lab`) et externes (`*.domain.fr`).

> Toutes les valeurs sensibles (domaines, IP, identifiants) sont des exemples
> fictifs. Remplacer les `<...>` avant de déployer.

## Fonctionnalités

- **Routage centralisé** de tous les services internes et exposés sur internet.
- **Certificat wildcard Let's Encrypt** `*.domain.fr` via challenge DNS
  Cloudflare (token API scopé `Zone:DNS:Edit`).
- **Certificat auto-signé wildcard** `*.home.lab` importé comme certificat custom.
- **Forward auth Authelia** sur chaque proxy host protégé (snippet
  `auth_request` fourni).
- **Port admin (81) bindé sur `127.0.0.1`** : inaccessible depuis le réseau,
  accessible via un proxy host protégé par Authelia ou en tunnel SSH de secours.
- **Réseau partagé `proxy_net`** : les backends Docker (Authelia, Zabbix Web,
  Grafana) sont joignables sans exposer de port sur l'hôte.

## Architecture

```
Internet ──► VPS bastion (WireGuard) ──► ThinkCentre
                                            │
               ┌────────────────────────────┤
               │        proxy_net           │
               │                            │
         NPM (:80/:443)              Authelia (:9091)
         admin 127.0.0.1:81          Zabbix Web (:8080)
                                     Grafana (:3000)
```

## Structure du dépôt

| Chemin | Rôle |
|---|---|
| [`docker-compose.yml`](docker-compose.yml) | NPM 2.15.1 |
| [`advanced-snippet.conf`](advanced-snippet.conf) | Snippet forward auth Authelia pour les proxy hosts |

> Les répertoires `data/`, `letsencrypt/` et `snippets/` ne sont **pas**
> versionnés : ils contiennent les certificats et la base NPM. Le
> [`.gitignore`](.gitignore) les exclut.

## Démarrage rapide

```bash
cd ~/docker/npm
docker compose up -d
docker compose logs -f npm   # attendre "Listening on port 80 443 81"
```

### Accès au panneau admin

Le port `81` est bindé sur `127.0.0.1` — deux méthodes d'accès :

- **Usage courant** : proxy host `npm.home.lab` protégé par Authelia (la
  dépendance circulaire NPM → Authelia → NPM est acceptée : si NPM tombe,
  l'accès d'urgence reste possible via le tunnel).
- **Secours** : tunnel SSH `ssh -L 8181:127.0.0.1:81 <user>@<IP> -N` puis
  ouvrir `http://localhost:8181`.

## Forward auth Authelia

Coller le contenu de [`advanced-snippet.conf`](advanced-snippet.conf) dans
l'onglet **Advanced** de chaque proxy host à protéger.

**Ne pas** l'appliquer sur `auth.home.lab` (le portail Authelia lui-même) :
cela créerait une boucle de redirection.

L'endpoint utilisé est `/api/authz/auth-request` avec les headers
`X-Original-URL` et `X-Original-Method` — c'est la méthode officielle Authelia
pour nginx (`auth_request`). L'endpoint `forward-auth` (Traefik/Caddy) renvoie
un `302` incompatible avec `auth_request` et produit une erreur.

## Proxy hosts configurés

| Domaine | Backend | Authelia | Certificat |
|---|---|---|---|
| `auth.home.lab` | authelia:9091 | Non (portail) | `*.home.lab` (auto-signé) |
| `npm.home.lab` | 127.0.0.1:81 | Oui | `*.home.lab` |
| `zabbix.home.lab` | zabbix-web:8080 | Oui | `*.home.lab` |
| `grafana.home.lab` | zabbix-grafana:3000 | Oui | `*.home.lab` |
| `urbackup.home.lab` | `192.168.1.10`:55414 | Oui | `*.home.lab` |
| `ha.domain.fr` | homeassistant:8123 | Non (auth native HA) | `*.domain.fr` (LE) |
| `plex.domain.fr` | `192.168.1.10`:32400 | Non (auth native Plex) | `*.domain.fr` (LE) |

## DNS

- **AdGuard Home** (RPi, `192.168.1.2`) : réécriture `*.home.lab` et
  `home.lab` → `192.168.1.5`.
- **Routeur** : DNS primaire → AdGuard, secondaire `1.1.1.1`, tertiaire `9.9.9.9`.
- **Cloudflare** : `*.domain.fr` → IP du VPS bastion (DNS only, pas de proxy
  orange pour les WebSockets ntfy).

## Sécurité

- Les données NPM (`data/`, `letsencrypt/`) ne doivent **jamais** être
  committées.
- `no-new-privileges` activé.
- Le port `81` n'est **jamais** exposé sur le réseau — uniquement en local.

## Dépannage

| Symptôme | Cause probable | Solution |
|---|---|---|
| Erreur **500** sur un proxy host | NPM ne joint pas le backend ou Authelia | `docker network inspect proxy_net` — vérifier que les conteneurs sont sur le même réseau |
| Erreur **400** | Headers manquants dans le snippet | Vérifier la présence de `X-Original-URL` et `X-Original-Method` |
| Erreur **302** / `auth request unexpected status: 302` | Mauvais endpoint Authelia | Remplacer `forward-auth` par `auth-request` dans le snippet |
| Boucle de redirection sur `auth.home.lab` | Snippet appliqué sur le proxy host Authelia | Retirer le bloc Advanced de `auth.home.lab` |
| Certificat LE échoue pour `*.domain.fr` | Plugin DNS OVH au lieu de Cloudflare | Le DNS `domain.fr` est géré par Cloudflare — utiliser le plugin Cloudflare |

## Composants & versions

| Composant | Version |
|---|---|
| Nginx Proxy Manager | 2.15.1 |

## Licence

Fourni tel quel, à des fins d'exemple et de réutilisation. Adapter les valeurs de
configuration à son propre environnement avant tout déploiement.