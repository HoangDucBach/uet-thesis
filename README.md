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

<<<<<<< HEAD
## Quick Start
=======
## 📝 Quick Start
>>>>>>> 3650996487a4cc999ff62feaab1d1de5f19e85ec

### 1. Start Infrastructure

```bash
<<<<<<< HEAD
# Start all services
docker-compose up -d

# Check services status
docker-compose ps

# View logs
docker-compose logs -f
```

### 2. Verify Services
=======
cd infrastructures/
docker compose up -d
```

### 3. Verify Services
>>>>>>> 3650996487a4cc999ff62feaab1d1de5f19e85ec

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

<<<<<<< HEAD
## Configuration

All configurations are centralized in `.env` file at the root directory.

### Key Environment Variables

```bash
# Database
POSTGRES_DB=sui_indexer
POSTGRES_USER=postgres
POSTGRES_PASSWORD=Admin2025@
POSTGRES_PORT=5432

# Elasticsearch
ES_VERSION=8.15.0
ES_PORT=9200
ES_CLUSTER_NAME=blockchain-monitor

# Kibana
KIBANA_PORT=5601

# Redis
REDIS_PORT=6379
REDIS_PASSWORD=Admin2025@
```

## Management Commands

```bash
# Stop all services
docker-compose down

# Stop and remove volumes (clean slate)
docker-compose down -v

# Restart specific service
docker-compose restart postgres

# View service logs
docker-compose logs -f elasticsearch

# Scale services (if needed)
docker-compose up -d --scale redis=2
=======
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
>>>>>>> 3650996487a4cc999ff62feaab1d1de5f19e85ec
```

## Troubleshooting

<<<<<<< HEAD
### Elasticsearch fails to start

```bash
# Increase vm.max_map_count
sudo sysctl -w vm.max_map_count=262144

# Make it permanent
echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf
```

### PostgreSQL connection refused

```bash
# Check if container is running
docker-compose ps postgres

# Check logs
docker-compose logs postgres

# Reset database
docker-compose down -v
docker-compose up -d postgres
```

### Redis memory issues

```bash
# Check memory usage
docker stats sui_redis

# Adjust REDIS_MEMORY_LIMIT in .env file
```

## Network Architecture

```
┌─────────────────────────────────────────┐
│           sui_network (bridge)          │
├─────────────────────────────────────────┤
│                                         │
│  ┌──────────┐  ┌──────────────────┐   │
│  │PostgreSQL│  │  Elasticsearch   │   │
│  │  :5432   │  │      :9200       │   │
│  └──────────┘  └──────────────────┘   │
│                                         │
│  ┌──────────┐  ┌──────────────────┐   │
│  │  Redis   │  │     Kibana       │   │
│  │  :6379   │  │      :5601       │   │
│  └──────────┘  └──────────────────┘   │
│                                         │
└─────────────────────────────────────────┘
```

## Data Persistence

All data is persisted in Docker volumes:

- `sui_postgres_data` - PostgreSQL database
- `sui_elasticsearch_data` - Elasticsearch indices
- `sui_kibana_data` - Kibana configurations
- `sui_redis_data` - Redis persistence

## Next Steps

1. ✅ Infrastructure setup complete
2. Configure Sui indexer application
3. Set up monitoring dashboards in Kibana
4. Implement data ingestion pipelines
5. Configure backup strategies

## Support

For issues and questions:
- Check logs: `docker-compose logs`
- Verify configurations in `.env`
- Ensure system requirements are met
=======
```bash
sudo sysctl -w vm.max_map_count=262144
docker compose logs <service>
docker stats
```

>>>>>>> 3650996487a4cc999ff62feaab1d1de5f19e85ec
