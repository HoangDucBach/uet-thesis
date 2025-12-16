# UET Thesis - Sui Blockchain Indexer

Infrastructure setup for Sui blockchain indexing and monitoring system.

## 📁 Project Structure

```
uet-thesis/
├── infrastructures/
│   ├── .env
│   ├── docker-compose.yml
│   ├── configs/
│   │   ├── postgres/postgresql.conf
│   │   ├── elasticsearch/elasticsearch.yml
│   │   ├── kibana/kibana.yml
│   │   ├── redis/redis.conf
│   │   ├── nginx/nginx.conf
│   │   └── prometheus/prometheus.yml
│   └── scripts/
│       ├── start.sh
│       ├── stop.sh
│       └── status.sh
└── sui-indexer/
```

## 🚀 Prerequisites

- Docker Engine 20.10+
- Docker Compose 2.0+
- At least 8GB RAM available
- At least 20GB disk space

## 📝 Quick Start

### 1. Start Infrastructure

```bash
cd infrastructures/
docker compose up -d
```

### 2. Verify Services

- **PostgreSQL**: localhost:5432
  - Database: `sui_indexer`
  - User: `postgres`
  - Password: `Admin2025@`

- **Elasticsearch**: http://localhost:9200
  - Cluster: `blockchain-monitor`
  - Security: Disabled (dev mode)

- **Kibana**: http://localhost:5601
  - Dashboard and visualization

- **Redis**: localhost:6379
  - Password: `Admin2025@`

### 3. Health Checks

```bash
# Check PostgreSQL
docker exec sui_postgres pg_isready -U postgres

# Check Elasticsearch
curl http://localhost:9200/_cluster/health

# Check Redis
docker exec sui_redis redis-cli -a Admin2025@ ping
```

## Services

- PostgreSQL: localhost:5432
- Elasticsearch: localhost:9200
- Kibana: localhost:5601
- Redis: localhost:6379
- Nginx: localhost:80
- Prometheus: localhost:9090

## Management

```bash
cd infrastructures/

docker compose down
docker compose down -v
docker compose restart <service>
docker compose logs -f <service>
```

## Troubleshooting

```bash
sudo sysctl -w vm.max_map_count=262144
docker compose logs <service>
docker stats
```
