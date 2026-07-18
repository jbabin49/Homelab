# wg-easy — Serveur WireGuard

Serveur VPN [WireGuard](https://www.wireguard.com/) du homelab, déployé via
[wg-easy](https://github.com/wg-easy/wg-easy) (conteneur Docker) sur un
**Raspberry Pi 3B** (Debian 13 Trixie aarch64). Le VPS bastion s'y connecte en
tant que client pour rejoindre le LAN sans ouvrir aucun port entrant côté maison.

> Toutes les valeurs sensibles (domaines, IP, identifiants) sont des exemples
> fictifs. Remplacer les `<...>` avant de déployer.

## Fonctionnalités

- **Serveur WireGuard** avec interface web de gestion des peers (ajout, QR code,
  activation/désactivation).
- **Tunnel sortant** : le VPS bastion est client WireGuard et atteint le LAN
  complet — aucun port entrant à ouvrir sur le routeur domestique.
- **Persistance** : les clés et la config des peers sont dans un volume Docker
  nommé, survivent aux recréations du conteneur.

## Architecture

```
VPS bastion (internet)
   │  WireGuard (client, sortant)
   │  :51820 UDP
   ▼
RPi AdGuard (192.168.1.2)
└── wg-easy (Docker)
    ├── :51820 UDP  (tunnel WireGuard)
    ├── :51821 TCP  (interface web admin)
    └── Volume : wg-easy_etc_wireguard (clés + peers)
            │
            ▼
        LAN domestique (192.168.1.0/24)
```

## Structure du dépôt

| Chemin | Rôle |
|---|---|
| [`docker-compose.yml`](docker-compose.yml) | wg-easy v15 |

> Le volume `wg-easy_etc_wireguard` contient les clés privées WireGuard et la
> config des peers — ne **jamais** le committer. Le sauvegarder séparément si
> besoin de reconstruire la machine.

## Déploiement

```bash
cd ~/docker/wg-easy
# Renseigner les <CHANGE_ME_*> dans docker-compose.yml
docker compose up -d
docker compose logs -f wg-easy   # attendre le démarrage
```

L'interface web de gestion des peers est accessible sur le port `51821`.

### Ajouter le VPS bastion comme client

1. Ouvrir l'interface web wg-easy sur `http://192.168.1.2:51821`.
2. Créer un nouveau peer (ex. `vps-bastion`).
3. Copier la configuration générée dans `/etc/wireguard/wg0.conf` sur le VPS.
4. Activer le tunnel côté VPS :

```bash
sudo systemctl enable --now wg-quick@wg0
```

## Sécurité

- Les clés WireGuard sont dans le volume Docker `wg-easy_etc_wireguard` — les
  sauvegarder séparément et ne **jamais** les committer.
- L'interface web (port `51821`) est protégée par mot de passe (variable
  `PASSWORD_HASH` dans le compose) — l'accès est restreint au LAN.
- Le port `51820/udp` est le seul port exposé sur internet (via le routeur) —
  le protocole WireGuard est chiffré et authentifié par clé.

## Dépannage

| Symptôme | Cause probable | Solution |
|---|---|---|
| VPS ne se connecte pas | Port `51820/udp` pas forwardé sur le routeur | Vérifier la règle NAT sur le routeur |
| Peers ne voient pas le LAN | `AllowedIPs` trop restrictif côté client | Vérifier que `AllowedIPs` inclut `192.168.1.0/24` |
| Interface web inaccessible | Mot de passe incorrect ou port bloqué | Vérifier `PASSWORD_HASH` et l'accès au port `51821` |

## Composants & versions

| Composant | Version |
|---|---|
| wg-easy | 15 |
| Debian (hôte) | 13 (Trixie) aarch64 |

## Licence

Fourni tel quel, à des fins d'exemple et de réutilisation. Adapter les valeurs de
configuration à son propre environnement avant tout déploiement.