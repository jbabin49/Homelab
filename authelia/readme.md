# Authelia — Authentification centralisée

Stack Docker prête à déployer pour ajouter une **authentification 2FA (TOTP)**
devant tous les services internes du homelab : [Authelia](https://www.authelia.com/)
gère l'identification, Redis stocke les sessions, et
[Nginx Proxy Manager](../nginx-proxy-manager/) redirige les utilisateurs non
authentifiés vers le portail de connexion.

> Toutes les valeurs sensibles (domaines, IP, identifiants) sont des exemples
> fictifs. Remplacer les `<...>` avant de déployer.

## Fonctionnalités

- **Authentification 2FA TOTP** pour tous les services exposés via NPM.
- **Backend utilisateurs local** (fichier YAML, hash argon2id) — pas de
  dépendance LDAP/AD.
- **Sessions Redis** isolées sur un réseau Docker interne (`authelia_internal`).
- **Réseau partagé `proxy_net`** : Authelia est joignable par NPM sans exposer
  de port sur l'hôte.
- **Notifications SMTP** (Brevo) pour la réinitialisation de mot de passe et
  l'enregistrement TOTP.
- **Surveillance temps réel** : un script bash taile les logs Docker et envoie
  des alertes [ntfy](../ntfy/) sur les échecs 1FA/TOTP, bannissements,
  utilisateurs inconnus et tentatives de reset.

## Architecture

```
         ┌──────────────────────────────────────┐
         │          proxy_net (externe)          │
         │                                       │
  NPM ◄──┤  Authelia (:9091)                    │
  (auth   │      │                               │
  request)│      │ authelia_internal              │
         │      └──► Redis (:6379)               │
         └──────────────────────────────────────┘
```

NPM interroge Authelia via l'endpoint `/api/authz/auth-request` (directive
nginx `auth_request`). Le snippet à coller dans chaque proxy host protégé se
trouve dans [`nginx-proxy-manager/advanced-snippet.conf`](../nginx-proxy-manager/advanced-snippet.conf).

## Structure du dépôt

| Chemin | Rôle |
|---|---|
| [`docker-compose.yml`](docker-compose.yml) | Authelia 4.39.20 + Redis 7.2-alpine |
| [`config/configuration.yml.example`](config/configuration.yml.example) | Configuration Authelia anonymisée |
| [`config/users_database.yml.example`](config/users_database.yml.example) | Base utilisateurs (exemple avec instructions hash) |

> Les fichiers `configuration.yml`, `users_database.yml` et `db.sqlite3` ne sont
> **pas** versionnés : ils contiennent des secrets. Le [`.gitignore`](.gitignore)
> les exclut.

## Démarrage rapide

```bash
# 0. Créer le réseau partagé (une seule fois, avant tout docker compose up)
docker network create proxy_net

# 1. Copier et renseigner les fichiers de configuration
cd ~/docker/authelia
cp config/configuration.yml.example config/configuration.yml
cp config/users_database.yml.example config/users_database.yml
# Éditer les deux fichiers : secrets, domaine, SMTP, etc.

# 2. Générer un hash argon2id pour l'utilisateur
docker run --rm authelia/authelia:4.39.20 \
  authelia crypto hash generate argon2 --password '<MOT_DE_PASSE>'
# Coller le hash dans users_database.yml

# 3. Lancer
docker compose up -d
docker compose logs -f authelia   # attendre "Listening for connections"
```

Authelia écoute alors sur le réseau Docker `proxy_net` au port `9091` —
elle n'est **jamais** exposée directement sur l'hôte. L'accès se fait
exclusivement via le proxy host `auth.home.lab` dans NPM.

## Alertes ntfy

Le service systemd `authelia-ntfy.service` exécute un script bash qui surveille
les logs Docker Authelia en temps réel (`docker logs -f`) et envoie des
notifications [ntfy](../ntfy/) sur :

- Échecs d'authentification 1FA / TOTP.
- Bannissements (regulation).
- Tentatives de réinitialisation de mot de passe.
- Noms d'utilisateur inconnus.

## Sécurité

- Ne **jamais** committer les fichiers de configuration renseignés — utiliser
  les `.example` comme modèles.
- Le réseau `proxy_net` est déclaré `external` : le créer manuellement avant
  le premier `docker compose up`.
- Redis est isolé sur `authelia_internal`, inaccessible depuis l'extérieur.
- `no-new-privileges` activé sur les deux conteneurs.

## Dépannage

| Symptôme | Cause probable | Solution |
|---|---|---|
| Authelia redémarre en boucle | Config YAML invalide ou Redis inaccessible | `docker compose logs authelia` — vérifier la syntaxe et le hostname Redis (`authelia-redis`) |
| `Can't handle RDB format version` | Volume Redis créé par une version incompatible (ex. 8.x → 7.2) | `docker compose down -v` puis relancer (perte des sessions actives uniquement) |
| Erreur **400** sur les proxy hosts | Mauvais endpoint Authelia | Utiliser `/api/authz/auth-request` (pas `forward-auth`, réservé à Traefik/Caddy) |
| Mails en spam | Réputation IP SMTP mutualisée (Brevo) | Vérifier SPF, DKIM et DMARC ; tester un autre provider si besoin |

## Composants & versions

| Composant | Version |
|---|---|
| Authelia | 4.39.20 |
| Redis | 7.2-alpine |

## Licence

Fourni tel quel, à des fins d'exemple et de réutilisation. Adapter les valeurs de
configuration à son propre environnement avant tout déploiement.