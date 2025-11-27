# UET Thesis - Sui Blockchain Indexer

Infrastructure setup for Sui blockchain indexing and monitoring system.

## 📁 Project Structure

```
uet-thesis/
├── infrastructures/          # Infrastructure setup
│   ├── .env                 # Environment configuration (main)
│   ├── .env.example         # Environment template
│   ├── .env.backup          # Backup of original env
│   ├── docker-compose.yml   # Main compose file
│   ├── configs/             # Service-specific configs
│   │   ├── elasticsearch/   # Elasticsearch config
│   │   │   ├── .env        # ES-specific variables
│   │   │   └── elasticsearch.yml
│   │   └── kibana/         # Kibana config
│   │       ├── .env        # Kibana-specific variables
│   │       └── kibana.yml
│   └── scripts/            # Management scripts
│       ├── start.sh        # Start all services
│       ├── stop.sh         # Stop all services
│       └── status.sh       # Check service status
└── sui-indexer/            # Indexer application
```

## 🚀 Prerequisites

- Docker Engine 20.10+
- Docker Compose 2.0+
- At least 8GB RAM available
- At least 20GB disk space

## 📝 Quick Start

### 1. Configure Environment

```bash
cd infrastructures/

# Copy environment template
cp .env.example .env

# Edit configuration if needed
nano .env
```

### 2. Start Infrastructure

```bash
# Start all services using script
./infrastructures/scripts/start.sh

# Or use docker compose directly
cd infrastructures/
docker compose up -d
```

### 3. Verify Services

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

### 4. Check Status

```bash
# Check all services
./infrastructures/scripts/status.sh
```

### 5. Health Checks

```bash
# Check PostgreSQL
docker exec sui_postgres pg_isready -U postgres

# Check Elasticsearch
curl http://localhost:9200/_cluster/health

# Check Redis
docker exec sui_redis redis-cli -a Admin2025@ ping
```

## ⚙️ Configuration

### Main Configuration File

All main configurations are in `infrastructures/.env`:

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

# Sui Node
SUI_REMOTE_STORE_URL=https://checkpoints.testnet.sui.io
SUI_FULLNODE_URL=https://fullnode.testnet.sui.io:443
```

### Service-Specific Configs

Additional service-specific configurations can be added to:
- `infrastructures/configs/elasticsearch/.env`
- `infrastructures/configs/kibana/.env`

These files are loaded in addition to the main `.env` file.

## 🛠️ Management Commands

```bash
# Stop services (keep data)
./infrastructures/scripts/stop.sh

# Or use docker compose
cd infrastructures/
docker compose down

# Stop and remove all data
docker compose down -v

# Restart specific service
docker compose restart postgres

# View service logs
docker compose logs -f elasticsearch
```

## Troubleshooting

### Elasticsearch fails to start

```bash
# Increase vm.max_map_count
sudo sysctl -w vm.max_map_count=262144

# Make it permanent
echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf
```

### PostgreSQL connection refused

```bash
# Check logs
cd infrastructures/
docker compose logs postgres

# Reset database
docker compose down -v
docker compose up -d postgres
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

### Backup Data

```bash
# Backup PostgreSQL
docker exec sui_postgres pg_dump -U postgres sui_indexer > backup.sql

# List volumes
docker volume ls | grep sui_
```

## 🔐 Security Notes

⚠️ **Development Mode**: Current setup is optimized for development with security features disabled:

- Elasticsearch security (X-Pack) is disabled
- Simple passwords used
- No SSL/TLS encryption

For production, enable security features in `infrastructures/.env`:
```bash
XPACK_SECURITY_ENABLED=true
XPACK_SSL_ENABLED=true
```

## 📚 Next Steps

1. ✅ Infrastructure setup complete
2. Configure Sui indexer application
3. Set up monitoring dashboards in Kibana
4. Implement data ingestion pipelines
5. Configure backup strategies
6. Enable security features for production

## 🤝 Support

For issues and questions:
- Check logs: `docker compose logs -f [service_name]`
- Verify configurations in `infrastructures/.env`
- Ensure system requirements are met
- Check health status: `./infrastructures/scripts/status.sh`

## 📖 Additional Resources

- [Sui Documentation](https://docs.sui.io/)
- [Elasticsearch Guide](https://www.elastic.co/guide/en/elasticsearch/reference/current/index.html)
- [Docker Compose Reference](https://docs.docker.com/compose/)
