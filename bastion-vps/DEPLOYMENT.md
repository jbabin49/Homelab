# Guide de déploiement — Bastion VPS

Guide pas-à-pas pour déployer le bastion sur un VPS Debian 12/13.
Toutes les valeurs entre `<...>` sont à remplacer. Les domaines, IP et noms
d'utilisateur donnés en exemple (`bastion.example.com`, `admin`, `10.0.0.0/24`, …)
sont fictifs.

## Contexte

- **VPS** : 2 vCores / 4 Go RAM / 40 Go NVMe suffisent — Debian 12 ou 13.
- **Objectif** : bastion d'administration à distance d'une infra sur un site distant.
- **Services** : WireGuard (tunnel), Guacamole (SSH + RDP + web), Nginx (reverse proxy HTTPS).
- **Accès** : SSH direct au VPS + interface web Guacamole pour tout le reste.

## Architecture réseau

```
Internet
    │
    ├── SSH (port custom, ex: 2222) ──► VPS directement
    │
    └── HTTPS (443) ──► Cloudflare ──► Nginx ──► Guacamole (localhost:8080)
                                                     │
                                                     │ Le VPS est CLIENT d'un WireGuard distant
                                                     │ Il compose vers le site distant (IP fixe)
                                                     │ sur UDP 51820. subnet: 172.25.1.0/24
                                                     ▼
                                        ┌──────────────────────────┐
                                        │  Site distant — LAN 10.0.0.0/24 │
                                        │                          │
                                        │ Serveur WireGuard        │
                                        │   (NAT -> LAN)           │
                                        │ Postes RDP/SSH           │
                                        │ NAS / services web       │
                                        └──────────────────────────┘
```

---

## Étape 1 — Hardening initial du VPS

### 1.1 Première connexion et mise à jour

```bash
ssh root@<IP_VPS>
apt update && apt full-upgrade -y
reboot   # si nouveau kernel
```

### 1.2 Créer un utilisateur admin

```bash
adduser <admin>
usermod -aG sudo <admin>
```

### 1.3 Authentification SSH par clé

Depuis la machine locale :

```bash
ssh-keygen -t ed25519 -C "<admin>@vps" -f ~/.ssh/vps-bastion
ssh-copy-id -i ~/.ssh/vps-bastion.pub <admin>@<IP_VPS>
ssh -i ~/.ssh/vps-bastion <admin>@<IP_VPS>
```

Client SSH local (`~/.ssh/config`) :

```
Host bastion
    HostName <IP_VPS>
    User <admin>
    Port 2222
    IdentityFile ~/.ssh/vps-bastion
```

### 1.4 Durcir la configuration SSH

Éditer `/etc/ssh/sshd_config` :

```
Port 2222
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
AuthenticationMethods publickey
MaxAuthTries 3
ClientAliveInterval 300
ClientAliveCountMax 2
AllowUsers <admin>
X11Forwarding no
```

```bash
sshd -t                          # valider avant de redémarrer (évite le verrouillage)
sudo systemctl restart sshd
# IMPORTANT : tester la connexion dans un AUTRE terminal avant de fermer la session.
```

### 1.5 Firewall UFW

```bash
sudo apt install ufw -y
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 2222/tcp comment "SSH custom"
# 443 non ouvert à tous : restreint aux IP Cloudflare en §4.7.
# Pas de règle 51820/udp : le VPS est CLIENT WireGuard (sortant).
sudo ufw enable
sudo ufw status verbose
```

### 1.6 Fail2ban

```bash
sudo apt install fail2ban -y
```

`/etc/fail2ban/jail.local` :

```ini
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 3
banaction = ufw

[sshd]
enabled = true
port = 2222
```

```bash
sudo systemctl enable --now fail2ban
sudo fail2ban-client status sshd
```

### 1.7 Mises à jour automatiques

```bash
sudo apt install unattended-upgrades -y
sudo dpkg-reconfigure -plow unattended-upgrades
```

Le fichier [`50unattended-upgrades`](50unattended-upgrades) de ce dépôt peut être
copié en `/etc/apt/apt.conf.d/50unattended-upgrades` (correctifs de sécurité,
reboot automatique à 4h).

---

## Étape 2 — Tunnel WireGuard : le VPS comme client

Le site distant expose un serveur WireGuard (ex. wg-easy). Le VPS est ajouté comme
**client** : rien à configurer côté serveur hormis créer le client. Le serveur fait
déjà le NAT vers son LAN → pas de route statique ni de forwarding à activer sur le VPS.

### 2.1 Créer le client côté serveur WireGuard

1. Créer un client (ex. `vps-bastion`).
2. Fixer `AllowedIPs = 10.0.0.0/24` (le LAN distant ; resserrable en /32 par cible).
3. Vérifier que l'`Endpoint` est l'IP publique fixe du site (port `51820`).

### 2.2 Installer les outils WireGuard sur le VPS

```bash
sudo apt install wireguard-tools -y
```

### 2.3 Poser la config

Copier [`wg0.example.conf`](wg0.example.conf) en `/etc/wireguard/wg0.conf`,
compléter les valeurs `<...>`, puis :

```bash
sudo chmod 600 /etc/wireguard/wg0.conf
```

> Deux corrections systématiques par rapport à une config brute : supprimer toute
> ligne `DNS = ...` et passer `PersistentKeepalive` à `25`.

### 2.4 Monter le tunnel

```bash
sudo systemctl enable --now wg-quick@wg0
sudo wg show          # "latest handshake" récent + trafic = OK
```

### 2.5 Pas de forwarding IP requis

Guacamole tourne sur le VPS et initie lui-même ses connexions : c'est du trafic
sortant, pas du routage pour un tiers → `net.ipv4.ip_forward` n'est pas requis.
Docker NAT le trafic des conteneurs sortant par `wg0`.

### 2.6 Tester la traversée

```bash
ping -c3 <IP_PASSERELLE_LAN>      # ex. la passerelle du tunnel
ping -c3 <IP_CIBLE_LAN>
```

---

## Étape 3 — Guacamole sur le VPS (Docker)

### 3.1 Installer Docker

```bash
sudo apt install ca-certificates curl gnupg -y
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list
sudo apt update
sudo apt install docker-ce docker-ce-cli containerd.io docker-compose-plugin -y
sudo usermod -aG docker <admin>
```

### 3.2 Le fichier compose (version durcie)

Copier ce dépôt en `/opt/guacamole/` (fichier [`compose.yml`](compose.yml)).
Durcissements appliqués :

- **Segmentation réseau** : `backend` en `internal: true` (Postgres ↔ Guacamole,
  aucune sortie Internet pour la DB), séparé de `guacd-net` (egress vers le LAN via `wg0`).
- **Secret Docker** pour le mot de passe DB (via `*_PASSWORD_FILE`), jamais en clair.
- `no-new-privileges:true` + `cap_drop: ALL` (capabilities minimales réajoutées pour Postgres).
- `read_only: true` + `tmpfs` sur Postgres et guacd.
- **Versions d'images pinnées** — l'image `guacamole` et `initdb.sh` doivent avoir la **même version**.
- Limites `mem_limit` / `pids_limit`, logs plafonnés, port lié à `127.0.0.1`.

### 3.3 Secrets, base de données et lancement

```bash
cd /opt/guacamole
sudo mkdir -p secrets initdb db-data
sudo chmod 700 secrets

# Mot de passe DB fort dans le secret (jamais dans le compose), sans newline finale.
openssl rand -base64 32 | tr -d '\n' | sudo tee secrets/db_password.txt > /dev/null
sudo chmod 644 secrets/db_password.txt         # voir note ci-dessous
sudo xxd secrets/db_password.txt | tail -1     # ne doit pas se terminer par 0a

# Script d'init SQL — MÊME VERSION que l'image guacamole du compose
docker run --rm guacamole/guacamole:1.5.5 /opt/guacamole/bin/initdb.sh --postgresql \
  | sudo tee initdb/init.sql > /dev/null

# Construire l'extension de thème (crée guacamole-home/extensions/dark-theme.jar,
# monté par le compose sur /etc/guacamole). Voir theme/README.md pour personnaliser.
( cd theme && ./build.sh )

docker compose up -d
docker compose ps
docker compose logs -f guacamole   # attendre "Server startup"
```

> **Permissions du secret** : l'image guacamole tourne en utilisateur NON-root et lit
> le secret bind-monté en gardant les perms de l'hôte ; un `600 root:root` donnerait
> "Permission denied" côté guacamole (postgres, lui, lit en root avant de droper).
> Alternative stricte : `sudo chown 1000:1000 secrets/db_password.txt && sudo chmod 400`
> (1000 = UID de l'utilisateur du conteneur guacamole, à confirmer via `docker compose exec guacamole id`).

### 3.4 Premier accès (test local)

```bash
curl -s http://localhost:8080/guacamole/ | head -5
```

Identifiants par défaut : `guacadmin` / `guacadmin` — **à changer immédiatement**.

---

## Étape 4 — Nginx reverse proxy + HTTPS (derrière Cloudflare)

Architecture : Navigateur → HTTPS → **Cloudflare** (proxy orange, Full strict) → VPS
avec un **certificat Origin Cloudflare**. Pas de Let's Encrypt sur le VPS ; l'IP
d'origine est masquée par Cloudflare.

### 4.1 Installer Nginx

```bash
sudo apt install nginx -y
```

### 4.2 Côté Cloudflare (dashboard)

1. **DNS** : `A bastion → <IP_VPS>`, **Proxy activé (orange)**.
2. **SSL/TLS → Overview** : mode **Full (strict)**.
3. **SSL/TLS → Edge Certificates** : activer **Always Use HTTPS**.

### 4.3 Certificat Origin Cloudflare (sur le VPS)

**SSL/TLS → Origin Server → Create Certificate** (RSA 2048, validité 15 ans). Copier :

```bash
sudo mkdir -p /etc/ssl/cloudflare
sudo tee /etc/ssl/cloudflare/bastion.pem > /dev/null   # coller le certificat, Ctrl-D
sudo tee /etc/ssl/cloudflare/bastion.key > /dev/null   # coller la clé privée, Ctrl-D
sudo chmod 600 /etc/ssl/cloudflare/bastion.key
sudo chmod 644 /etc/ssl/cloudflare/bastion.pem
```

### 4.4 Restaurer l'IP réelle des visiteurs

```bash
{
  echo "# Cloudflare real IP - généré $(date -I)"
  for ip in $(curl -s https://www.cloudflare.com/ips-v4) $(curl -s https://www.cloudflare.com/ips-v6); do
    echo "set_real_ip_from $ip;"
  done
  echo "real_ip_header CF-Connecting-IP;"
} | sudo tee /etc/nginx/conf.d/cloudflare-realip.conf > /dev/null
```

### 4.5 Authenticated Origin Pulls (mTLS Cloudflare → origin)

Le VPS n'accepte que les connexions présentant le certificat client Cloudflare
(`ssl_verify_client on` dans [`nginx-bastion.conf`](nginx-bastion.conf)).

```bash
sudo curl -so /etc/ssl/cloudflare/origin-pull-ca.pem \
  https://developers.cloudflare.com/ssl/static/authenticated_origin_pull_ca.pem
```

Puis côté Cloudflare : **SSL/TLS → Origin Server → Authenticated Origin Pulls** → activer.

### 4.6 Déployer Nginx

```bash
# Map WebSocket (contexte http) requise par Guacamole
sudo tee /etc/nginx/conf.d/websocket.conf > /dev/null <<'EOF'
map $http_upgrade $connection_upgrade {
    default upgrade;
    ''      close;
}
EOF

# Adapter server_name / chemins de cert dans nginx-bastion.conf au préalable
sudo cp nginx-bastion.conf /etc/nginx/sites-available/guacamole
sudo ln -s /etc/nginx/sites-available/guacamole /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl reload nginx
```

### 4.7 Pare-feu : n'accepter le 443 que depuis Cloudflare

```bash
sudo ufw delete allow 443/tcp 2>/dev/null
for ip in $(curl -s https://www.cloudflare.com/ips-v4) $(curl -s https://www.cloudflare.com/ips-v6); do
  sudo ufw allow from "$ip" to any port 443 proto tcp comment "Cloudflare"
done
sudo ufw status | grep 443
```

### 4.8 Vérifier de bout en bout

```bash
curl -sI https://bastion.example.com/ | grep -iE "^(HTTP|strict-transport)"
```

> ⚠️ **Avant d'exposer le service**, changer le mot de passe `guacadmin` (ou créer
> un compte et supprimer `guacadmin`) : dès que Cloudflare route vers l'origin,
> l'interface est joignable avec les identifiants par défaut publics.

### 4.9 Cloudflare Access — authentification devant Guacamole

Sur le plan gratuit, le Bot Fight Mode est zone-wide et casse les WebSockets de
Guacamole. Cloudflare Access résout les deux problèmes : les requêtes authentifiées
par Access **bypassent le Bot Fight Mode**, et Access ajoute une **couche
d'authentification** (login) **devant** le VPS.

**Prérequis** : méthode de login **One-time PIN** (code par email), native dans Zero Trust.

1. **Access → Applications → Add an application → Self-hosted**.
2. **Application domain** : `bastion.example.com`.
3. **Session duration** : au choix (ex. 24h).
4. **Add policy** : *Action* **Allow**, *Include* **Emails** = `<votre-email>`.
5. Créer. Une page de login Access se place devant le hostname.

Une fois Access en place, réactiver le Bot Fight Mode zone-wide sans risque.

Sécurité en couches : **Access (OTP email) → Guacamole (login) → TOTP (§6.2)**.

---

## Étape 5 — Préparer les cibles

### 5.1 RDP vers un poste Linux

xrdp (protocole RDP natif, recommandé pour Guacamole) :

```bash
# ex. sur une distro basée Arch
sudo pacman -S xrdp xorgxrdp
sudo systemctl enable --now xrdp
# KDE Plasma peut nécessiter un ~/.xsession : echo "startplasma-x11" > ~/.xsession
```

Alternative : VNC (Krfb, x11vnc…) et une connexion VNC dans Guacamole.

### 5.2 SSH sur les autres machines

S'assurer que le serveur SSH tourne sur chaque cible (`sudo systemctl enable --now sshd`).

### 5.3 Configurer les connexions dans Guacamole

Dans *Administration > Connexions*, créer les entrées vers les IP du LAN distant
(RDP `3389`, SSH `22`) — toutes joignables via le tunnel WireGuard. Pour les
interfaces web (dashboards internes), utiliser le **port forwarding SSH** de Guacamole
ou un tunnel SOCKS via une connexion SSH.

---

## Étape 6 — Sécurité finale

### 6.1 Checklist

- [ ] Mot de passe `guacadmin` changé (ou compte supprimé et remplacé)
- [ ] `/etc/wireguard/wg0.conf` en 600, sans ligne `DNS`, `PersistentKeepalive = 25`
- [ ] Client WireGuard avec `AllowedIPs` restreint au LAN (voire /32 par cible)
- [ ] UI du serveur WireGuard NON exposée à Internet
- [ ] Fail2ban actif (IP fixe d'admin dans `ignoreip` si souhaité)
- [ ] UFW : 2222/tcp ouvert ; 443/tcp restreint aux plages IP Cloudflare
- [ ] SSH : auth par clé uniquement, root désactivé
- [ ] Docker écoute uniquement sur 127.0.0.1 ; secret DB hors compose
- [ ] HTTPS : Cloudflare Full strict + cert Origin + Authenticated Origin Pulls
- [ ] Cloudflare Access (OTP email) actif ; Bot Fight Mode réactivé zone-wide
- [ ] Mises à jour automatiques activées

### 6.2 TOTP (2FA) sur Guacamole

Le [`compose.yml`](compose.yml) active déjà l'extension TOTP via les variables
`TOTP_ENABLED` / `TOTP_ISSUER`. Au prochain login, chaque utilisateur voit un QR
code à scanner (Aegis, Google Authenticator…), puis confirme avec un code à 6 chiffres.
**Tous les comptes** doivent s'enrôler.

**Récupération** (appareil perdu) — réinitialiser l'enrôlement via la base :

```bash
cd /opt/guacamole
docker compose exec guacamole-db psql -U guacamole -d guacamole_db \
  -c "DELETE FROM guacamole_user_attribute WHERE attribute_name LIKE 'guac-totp%';"
```

> Filet de sécurité : Cloudflare Access étant devant, même bloqué sur le TOTP
> Guacamole, l'accès SSH au VPS (port 2222) reste disponible pour lancer ce reset.

### 6.3 Snapshot

Une fois tout validé, créer un snapshot de la VM chez l'hébergeur.

---

## Résumé des ports

| Port  | Protocole | Service                         | Exposé à                              |
|-------|-----------|---------------------------------|---------------------------------------|
| 2222  | TCP       | SSH                             | Internet                              |
| 443   | TCP       | HTTPS (Nginx → Guacamole)       | **Cloudflare uniquement** (UFW filtré)|
| 8080  | TCP       | Guacamole (Tomcat)              | localhost uniquement                  |
| 51820 | UDP       | WireGuard (VPS client, sortant) | — (aucune ouverture entrante)         |

## Fichiers importants sur le VPS

```
/etc/ssh/sshd_config                   # Config SSH
/etc/wireguard/wg0.conf                # Config WireGuard client
/etc/nginx/sites-available/guacamole   # Reverse proxy
/opt/guacamole/compose.yml             # Stack Guacamole
/etc/fail2ban/jail.local               # Config Fail2ban
```
