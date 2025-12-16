# MVP Setup - 3GB RAM Environment

## Services Running (Core MVP)
- PostgreSQL (blockchain_postgres) - ~512MB
- Elasticsearch Cluster:
  - es-master (256MB heap, 512MB total)
  - es-data-1 (768MB heap, 1.5GB total)
  - es-lb (load balancer)
- Redis (~256-512MB)

**Total RAM usage: ~2.5-3GB**

## Disabled (due to 3GB RAM constraint)
- es-data-2 (can be enabled for production with more RAM)
- Kibana (uncomment in docker-compose.yml when needed for visualization)
- Logstash (uncomment in docker-compose.yml when needed)
- Prometheus (monitoring - for production)
- Nginx reverse proxy (for production)
- Filebeat (log shipping - for production)

## Re-enabling Services
To enable Kibana/Logstash when you have more RAM available:
1. Uncomment the service in `docker-compose.yml`
2. Run `docker compose up -d kibana` or `docker compose up -d logstash`

## Start Infrastructure

```bash
cd infrastructures
docker compose up -d
```

## Verify Services

```bash
docker compose ps

# PostgreSQL
docker exec blockchain_postgres pg_isready -U postgres

# Elasticsearch cluster (should show 2 nodes: master + data-1)
curl http://localhost:9200/_cluster/health?pretty
# Expected: "status": "green" or "yellow", "number_of_nodes": 2

# Redis
docker exec blockchain_redis redis-cli -a Admin2025@ ping
```

## Run Indexer

```bash
cd sui-indexer

export DATABASE_URL="postgres://postgres:Admin2025@@localhost:5432/sui_indexer"

cargo run --release -- \
  --remote-store-url https://checkpoints.testnet.sui.io \
  --last-checkpoint 100
```

## Check Data

```bash
docker exec -it blockchain_postgres psql -U postgres -d sui_indexer

SELECT COUNT(*) FROM transactions;
SELECT tx_digest, execution_status, gas_used FROM transactions LIMIT 5;
```

## Stop

```bash
cd infrastructures
docker compose down
```
