#!/bin/bash
# adguard-ntfy.sh — Check horaire + rapport quotidien AdGuard Home → ntfy
# Usage : adguard-ntfy.sh check | adguard-ntfy.sh report

NTFY_URL="https://ntfy.<CHANGE_ME_DOMAIN>/<CHANGE_ME_TOPIC>"
NTFY_TOKEN="<CHANGE_ME_TOKEN>"
ADGUARD_URL="http://127.0.0.1"
ADGUARD_USER="<CHANGE_ME_USER>"
ADGUARD_PASS="<CHANGE_ME_PASS>"

send_ntfy() {
    local priority="$1" title="$2" message="$3" tags="$4"
    curl -sf \
        -H "Authorization: Bearer ${NTFY_TOKEN}" \
        -H "Title: ${title}" \
        -H "Priority: ${priority}" \
        -H "Tags: ${tags}" \
        -d "${message}" \
        "${NTFY_URL}" > /dev/null 2>&1
}

api_get() {
    curl -sf -u "${ADGUARD_USER}:${ADGUARD_PASS}" "${ADGUARD_URL}${1}"
}

# ── CHECK (horaire) ──────────────────────────────────────────────
do_check() {
    # Vérifier que le service répond
    status_json=$(api_get "/control/status")
    if [ $? -ne 0 ] || [ -z "${status_json}" ]; then
        send_ntfy "5" "AdGuard — Service DOWN" \
            "Impossible de joindre l'API AdGuard Home sur ${ADGUARD_URL}" \
            "rotating_light,skull"
        exit 1
    fi

    # Vérifier que le filtrage est activé
    protection=$(echo "${status_json}" | python3 -c "import sys,json; print(json.load(sys.stdin).get('protection_enabled', False))" 2>/dev/null)
    if [ "${protection}" != "True" ]; then
        send_ntfy "5" "AdGuard — Filtrage DÉSACTIVÉ" \
            "La protection DNS est désactivée sur AdGuard Home !" \
            "warning,shield"
        exit 1
    fi

    # Vérifier le taux de blocage (alerte si < 5% ou > 80%)
    stats_json=$(api_get "/control/stats")
    if [ $? -eq 0 ] && [ -n "${stats_json}" ]; then
        read -r total blocked <<< $(echo "${stats_json}" | python3 -c "
import sys, json
d = json.load(sys.stdin)
t = d.get('num_dns_queries', 0)
b = d.get('num_blocked_filtering', 0)
print(t, b)
" 2>/dev/null)

        if [ "${total}" -gt 100 ] 2>/dev/null; then
            pct=$((blocked * 100 / total))
            if [ "${pct}" -lt 5 ]; then
                send_ntfy "4" "AdGuard — Taux de blocage anormalement bas" \
                    "Seulement ${pct}% de requêtes bloquées (${blocked}/${total}). Vérifier les listes de filtrage." \
                    "warning,mag"
            elif [ "${pct}" -gt 80 ]; then
                send_ntfy "4" "AdGuard — Taux de blocage anormalement haut" \
                    "${pct}% de requêtes bloquées (${blocked}/${total}). Possible faux positifs." \
                    "warning,mag"
            fi
        fi
    fi
}

# ── REPORT (quotidien 8h) ───────────────────────────────────────
do_report() {
    stats_json=$(api_get "/control/stats")
    if [ $? -ne 0 ] || [ -z "${stats_json}" ]; then
        send_ntfy "3" "AdGuard — Rapport impossible" \
            "Impossible de récupérer les statistiques." \
            "x,chart_with_downwards_trend"
        exit 1
    fi

    report=$(echo "${stats_json}" | python3 -c "
import sys, json

d = json.load(sys.stdin)
total = d.get('num_dns_queries', 0)
blocked = d.get('num_blocked_filtering', 0)
malware = d.get('num_replaced_safebrowsing', 0)
parental = d.get('num_replaced_parental', 0)
avg_ms = d.get('avg_processing_time', 0)

pct = (blocked * 100 // total) if total > 0 else 0
avg_display = f'{avg_ms * 1000:.1f}' if isinstance(avg_ms, float) else avg_ms

lines = []
lines.append(f'Requêtes : {total:,}')
lines.append(f'Bloquées : {blocked:,} ({pct}%)')
if malware > 0:
    lines.append(f'Malware bloqué : {malware}')
if parental > 0:
    lines.append(f'Contrôle parental : {parental}')
lines.append(f'Temps moyen : {avg_display} ms')
lines.append('')

# Top domaines requêtés
top = d.get('top_queried_domains', [])
if top:
    lines.append('Top domaines :')
    for i, entry in enumerate(top[:5], 1):
        for domain, count in entry.items():
            lines.append(f'  {i}. {domain} ({count:,})')

# Top domaines bloqués
top_blocked = d.get('top_blocked_domains', [])
if top_blocked:
    lines.append('')
    lines.append('Top bloqués :')
    for i, entry in enumerate(top_blocked[:5], 1):
        for domain, count in entry.items():
            lines.append(f'  {i}. {domain} ({count:,})')

# Top clients
top_clients = d.get('top_clients', [])
if top_clients:
    lines.append('')
    lines.append('Top clients :')
    for i, entry in enumerate(top_clients[:5], 1):
        for client, count in entry.items():
            lines.append(f'  {i}. {client} ({count:,})')

print('\n'.join(lines))
" 2>/dev/null)

    send_ntfy "2" "AdGuard — Rapport quotidien" "${report}" "bar_chart,shield"
}

# ── MAIN ─────────────────────────────────────────────────────────
case "${1}" in
    check)  do_check ;;
    report) do_report ;;
    *)      echo "Usage: $0 {check|report}" >&2; exit 1 ;;
esac