#!/bin/bash
# Authelia → ntfy — Surveillance des logs Docker
# Emplacement réel : /opt/scripts/authelia-ntfy.sh
# Déclenché par : authelia-ntfy.service (systemd)
#
# Détecte dans les logs du conteneur Authelia :
#   - Échecs d'authentification 1FA
#   - Échecs TOTP (2FA)
#   - Bannissements (regulation)
#   - Utilisateur introuvable
#   - Demandes de réinitialisation de mot de passe
#
# Prérequis : docker, curl, jq

NTFY_URL="https://ntfy.CHANGE_ME_DOMAIN/authelia"
NTFY_TOKEN="CHANGE_ME_TOKEN"
CONTAINER="authelia"

docker logs -f --since 1s "$CONTAINER" 2>&1 | while read -r line; do

    TITLE=""
    PRIORITY=3
    MESSAGE=""

    # Échec 1FA
    if echo "$line" | grep -qi "unsuccessful.*1FA"; then
        USER=$(echo "$line" | grep -oP '"username":"[^"]*"' | head -1)
        TITLE="🔐 Échec 1FA — Authelia"
        PRIORITY=4
        MESSAGE="**Détail :** Tentative de connexion échouée\n$USER"

    # Échec TOTP
    elif echo "$line" | grep -qi "second factor"; then
        TITLE="🔐 Échec TOTP — Authelia"
        PRIORITY=4
        MESSAGE="**Détail :** Échec de vérification du code TOTP"

    # Bannissement
    elif echo "$line" | grep -qi "ban\|regula"; then
        TITLE="⛔ Bannissement — Authelia"
        PRIORITY=5
        MESSAGE="**Détail :** IP bannie après trop de tentatives"

    # Utilisateur introuvable
    elif echo "$line" | grep -qi "user not found"; then
        TITLE="👤 Utilisateur inconnu — Authelia"
        PRIORITY=3
        MESSAGE="**Détail :** Tentative avec un utilisateur inexistant"

    # Reset mot de passe
    elif echo "$line" | grep -qi "password reset"; then
        TITLE="🔑 Reset mot de passe — Authelia"
        PRIORITY=3
        MESSAGE="**Détail :** Demande de réinitialisation de mot de passe"
    fi

    # Envoyer si un événement a été détecté
    if [ -n "$TITLE" ]; then
        printf "$MESSAGE" | curl -s \
            -H "Authorization: Bearer $NTFY_TOKEN" \
            -H "Title: $TITLE" \
            -H "Priority: $PRIORITY" \
            -H "Tags: lock" \
            -H "Markdown: yes" \
            -d @- \
            "$NTFY_URL"
    fi
done
