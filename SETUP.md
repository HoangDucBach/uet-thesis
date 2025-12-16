# Platform Setup Guide

## Step 1: Start Infrastructure

```bash
cd infrastructures
docker compose up -d
```

Wait for services to be healthy:
```bash
docker compose ps
```

Check logs if needed:
```bash
docker compose logs -f postgres
docker compose logs -f elasticsearch
```

## Step 2: Verify Services

PostgreSQL:
```bash
docker exec blockchain_postgres pg_isready -U postgres
```

Elasticsearch cluster:
```bash
curl http://localhost:9200/_cluster/health
```

Redis:
```bash
docker exec blockchain_redis redis-cli -a Admin2025@ ping
```

Kibana (wait 1-2 minutes for startup):
```bash
curl -I http://localhost:5601/api/status
```

Logstash:
```bash
curl http://localhost:9600/_node/stats
```

## Step 3: Build Sui Indexer

```bash
cd sui-indexer
cargo build --release
```

## Step 4: Run Indexer

```bash
export DATABASE_URL="postgres://postgres:Admin2025@@localhost:5432/sui_indexer"

cargo run --release -- \
  --remote-store-url https://checkpoints.testnet.sui.io \
  --last-checkpoint 1000
```

## Step 5: Verify Data

Check PostgreSQL:
```bash
docker exec -it blockchain_postgres psql -U postgres -d sui_indexer -c "SELECT COUNT(*) FROM transactions;"
docker exec -it blockchain_postgres psql -U postgres -d sui_indexer -c "SELECT tx_digest, execution_status, gas_used FROM transactions LIMIT 5;"
```

## Step 6: Monitor

Kibana dashboard (Elasticsearch data visualization):
```bash
open http://localhost:5601
```

Logstash monitoring:
```bash
curl http://localhost:9600/_node/stats | jq
```

PostgreSQL queries:
```bash
docker exec -it blockchain_postgres psql -U postgres -d sui_indexer
```

Example queries:
```sql
SELECT execution_status, COUNT(*) FROM transactions GROUP BY execution_status;
SELECT AVG(gas_used) FROM transactions WHERE gas_used IS NOT NULL;
SELECT sender, COUNT(*) as tx_count FROM transactions WHERE sender IS NOT NULL GROUP BY sender ORDER BY tx_count DESC LIMIT 10;
```

## Troubleshooting

Stop all:
```bash
cd infrastructures
docker compose down
```

Clean restart:
```bash
docker compose down -v
docker compose up -d
```

Check indexer logs:
```bash
cd sui-indexer
RUST_LOG=debug cargo run --release
```
