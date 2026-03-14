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

Contenu principal:
- `files/HA/docker-compose.yml`: stack Prometheus + VictoriaMetrics + Grafana
- `files/HA/prometheus.yml`: config de scraping
- `files/HA/grafana/provisioning/`: provisioning Grafana (datasources, alertes, etc.)
- `files/docker-daemon.json`: exemple d'activation des métriques Docker (`:9323`)
- `dashboards/*.json`: dashboards personnels
- `dashboards/*.example.json`: dashboards d'exemple anonymisés

#### Note
Les commandes peuvent être exécutées avec `docker compose` (CLI Docker) ou `docker-compose` (binaire séparé) selon votre environnement Home Assistant.

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

## 📊 Datasource Grafana
Dans Grafana, vous pouvez ajouter un datasource de type `VictoriaMetrics`.

Les dashboards du dossier `dashboards/` sont maintenant declares pour le plugin
`victoriametrics-metrics-datasource`.

Si Grafana tourne dans le meme `docker-compose`, n'utilisez pas `localhost` ni l'IP de la machine:
- URL VictoriaMetrics: `http://victoria-metrics:8428`
- URL Prometheus si besoin: `http://prometheus:9090`

Pourquoi:
- `localhost` depuis Grafana pointe vers le conteneur Grafana lui-meme.
- Le port `9090` correspond a Prometheus.
- Le port `8428` correspond a VictoriaMetrics.

Si vous configurez le datasource depuis un Grafana qui n'est pas dans ce reseau Docker, alors utilisez l'IP de Home Assistant:
- VictoriaMetrics: `http://IP_HA:8428`
- Prometheus: `http://IP_HA:9090`

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
4. Volume Docker externe cree pour la config Prometheus:
```bash
docker volume create monitoring_prometheus_config
```

## 🚀 Deploiement sur Home Assistant
```bash
mkdir -p /mnt/data/supervisor/monitoring
cd /mnt/data/supervisor/monitoring
```

Copier `docker-compose.yml`, `prometheus.yml` et le dossier `grafana/provisioning`.

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

## 🧩 Initialiser la config Prometheus dans le volume
Le service Prometheus monte un volume externe en lecture seule:
- volume: `monitoring_prometheus_config`
- chemin dans le conteneur: `/etc/prometheus`

Avant le premier démarrage, injecter `prometheus.yml` dans ce volume:
```bash
cd /mnt/data/supervisor/monitoring
cat prometheus.yml | docker run --rm -i \
  -v monitoring_prometheus_config:/cfg \
  alpine:3.20 sh -c 'cat > /cfg/prometheus.yml'
```

## ♻️ Mettre a jour la config Prometheus
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
```json
{
  "metrics-addr": "0.0.0.0:9323",
  "experimental": true
}
```

Exemple prêt à l'emploi dans ce dépôt:
- `files/docker-daemon.json`

Le port `9323` correspond aux metriques du daemon Docker (optionnel), pas a cAdvisor.

## 🚨 Alertes Grafana provisionnees
Le conteneur Grafana monte maintenant le dossier local `files/HA/grafana/provisioning`
vers `/etc/grafana/provisioning`.

Un squelette local d'alerting peut etre place dans:
- `files/HA/grafana/provisioning/alerting/`

Les fichiers YAML presents dans ce dossier seront charges par Grafana au demarrage.

Flux conseille:
1. editer les fichiers YAML dans `alerting/`
2. remplacer les placeholders (UID datasource, email, webhook, etc.)
3. redemarrer Grafana avec `docker compose restart grafana`

Bon a savoir:
- les dashboards JSON ne suffisent pas pour restaurer les alertes Grafana unifiees
- les regles, contact points et policies se gerent mieux via provisioning YAML
- si vous preferez, vous pouvez aussi creer les alertes dans l'UI puis les re-saisir ici pour les versionner ensuite

## 📦 Dashboards d'exemple
Les fichiers `dashboards/*.example.json` sont fournis pour partage/import sans exposer d'informations personnelles.

Points importants:
- datasource: `${DS_PROMETHEUS}`
- adresses/IP: anonymisées
- entités Home Assistant: remplacées par des variables (`$climate_entity`, `$switch_entity`, etc.)

## 🔎 URLs utiles
- Prometheus: `http://IP_HA:9090`
- Prometheus targets: `http://IP_HA:9090/targets`
- VictoriaMetrics UI: `http://IP_HA:8428/vmui/`
- Grafana: `http://IP_HA:3000`
