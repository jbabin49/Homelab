# Prometheus, VictoriaMetrics et Grafana sur Home Assistant

![Home Assistant](https://img.shields.io/badge/Home%20Assistant-10.0.0.15%3A8123-41BDF5?logo=homeassistant&logoColor=white)
![Prometheus](https://img.shields.io/badge/Prometheus-10.0.0.15%3A9090-E6522C?logo=prometheus&logoColor=white)
![Grafana](https://img.shields.io/badge/Grafana-10.0.0.15%3A3000-F46800?logo=grafana&logoColor=white)
![VictoriaMetrics](https://img.shields.io/badge/VictoriaMetrics-10.0.0.15%3A8428-00B894?logo=databricks&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-Compose-2496ED?logo=docker&logoColor=white)
![Status](https://img.shields.io/badge/Stack-Homelab-2EA44F)

Ce dossier contient une stack de monitoring pour Home Assistant:
- Prometheus pour le scraping
- VictoriaMetrics comme stockage long terme via `remote_write`
- Grafana pour la visualisation

#### Note : les commandes docker compose peuvent être éxécutées soit avec `docker compose` (Docker CLI) soit avec `docker-compose` (binaire séparé) selon la configuration de Home Assistant. Assurez-vous d'utiliser la bonne syntaxe pour votre environnement.

## 🏗️ Architecture
- Home Assistant expose ses metriques sur `/api/prometheus`.
- Prometheus scrape Home Assistant et les exporters distants.
- Prometheus envoie les series vers VictoriaMetrics (`/api/v1/write`).
- Grafana peut interroger Prometheus (temps court) ou VictoriaMetrics (temps long).

## 🌐 Services HA
Ports exposes:
- Prometheus: `9090`
- Grafana: `3000`
- VictoriaMetrics: `8428`

Fichier principal:
- `files/HA/docker-compose.yml`

Config Prometheus:
- `files/HA/prometheus.yml`

## ✅ Prerequis Home Assistant
1. Add-on SSH/Terminal installe.
2. Docker compose disponible sur HA.
3. Reseau Docker externe cree:
```bash
docker network create monitoring_net
```

## 🚀 Deploiement sur Home Assistant
```bash
mkdir -p /mnt/data/supervisor/monitoring
cd /mnt/data/supervisor/monitoring
```

Copier `docker-compose.yml`, `prometheus.yml` et `init-timescale.sql` si present.

Lancer la stack:
```bash
docker compose up -d
```

Verifier:
```bash
docker compose ps
docker compose logs --tail=100 prometheus
docker compose logs --tail=100 victoria-metrics
```

## 🔐 Auth Home Assistant (obligatoire)
Si `homeassistant` est `401 Unauthorized`, creer un Long-Lived Access Token dans Home Assistant puis renseigner:

```yaml
authorization:
  type: Bearer
  credentials: "<TOKEN>"
```

dans `files/HA/prometheus.yml` (job `homeassistant`).

## ♻️ Mettre a jour la config Prometheus dans le volume
La config est chargee depuis le volume Docker externe `monitoring_prometheus_config`.

```bash
cd /mnt/data/supervisor/monitoring
cat prometheus.yml | docker run --rm -i \
  -v monitoring_prometheus_config:/cfg \
  alpine:3.20 sh -c 'cat > /cfg/prometheus.yml'
```

Recharge Prometheus:
```bash
curl -X POST http://127.0.0.1:9090/-/reload
```
ou
```bash
docker compose restart prometheus
```

## 📡 Exporters distants
Exemple OMV (`files/OMV/docker-compose.yml`):
- node_exporter: `9100`
- cadvisor: `8080`

Dans Prometheus, la cible OMV doit pointer vers:
- `10.0.0.52:9100`
- `10.0.0.52:8080`

Pour pouvoir exporter les métriques du daemon Docker, il faut modifier le fichier `/etc/docker/daemon.json` et ajouter :
```bash
{
    metrics_addr:0.0.0.0:9323,
    experimental:true
}
```

Le port `9323` correspond aux metriques du daemon Docker (optionnel), pas a cAdvisor.

## 🔎 URLs utiles
- Prometheus: `http://IP_HA:9090`
- Prometheus targets: `http://IP_HA:9090/targets`
- VictoriaMetrics UI: `http://IP_HA:8428/vmui/`
- Grafana: `http://IP_HA:3000`
