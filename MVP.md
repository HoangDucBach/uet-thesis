# MVP Setup - Infrastructure Only

## Services Running (MVP)
- PostgreSQL (blockchain_postgres)
- Elasticsearch Cluster:
  - es-master
  - es-data-1
  - es-data-2
  - es-lb (load balancer)
- Redis

## Disabled (for performance)
- Kibana
- Prometheus
- Nginx reverse proxy
- Filebeat

## Start Infrastructure

```bash
cd infrastructures
docker compose up -d
```

## Verify Services

```bash
docker compose ps

docker exec blockchain_postgres pg_isready -U postgres
curl http://localhost:9200/_cluster/health
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
