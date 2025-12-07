#!/bin/bash
# Insert generated DeFi data into Elasticsearch for testing
# Usage: ./insert_to_elasticsearch.sh [json_file]

set -e

# Configuration
ES_URL="${ELASTICSEARCH_URL:-http://localhost:9200}"
ES_INDEX="${ELASTICSEARCH_INDEX:-sui-transactions}"
JSON_FILE="${1:-defi_transactions_1500.json}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Elasticsearch Data Insertion Script                  ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check if JSON file exists
if [ ! -f "$JSON_FILE" ]; then
    echo -e "${RED}❌ Error: JSON file not found: $JSON_FILE${NC}"
    echo "Generate data first: python3 generate_defi_data.py"
    exit 1
fi

# Check Elasticsearch connection
echo -e "${YELLOW}🔍 Checking Elasticsearch connection...${NC}"
if ! curl -s "$ES_URL" > /dev/null; then
    echo -e "${RED}❌ Cannot connect to Elasticsearch at $ES_URL${NC}"
    echo "Make sure Elasticsearch is running:"
    echo "  docker run -p 9200:9200 -d elasticsearch:8.11.0"
    exit 1
fi
echo -e "${GREEN}✓${NC} Connected to Elasticsearch"
echo ""

# Create index with proper mapping
echo -e "${YELLOW}📋 Creating index mapping...${NC}"

curl -X PUT "$ES_URL/$ES_INDEX" -H 'Content-Type: application/json' -d'
{
  "settings": {
    "number_of_shards": 1,
    "number_of_replicas": 0,
    "refresh_interval": "1s"
  },
  "mappings": {
    "properties": {
      "tx_digest": { "type": "keyword" },
      "checkpoint": { "type": "long" },
      "sender": { "type": "keyword" },
      "timestamp_ms": { "type": "date" },
      "execution_status": { "type": "keyword" },
      "package_id": { "type": "keyword" },
      "attack_type": { "type": "keyword" },
      "events": {
        "type": "nested",
        "properties": {
          "type": { "type": "keyword" },
          "pool_id": { "type": "keyword" },
          "sender": { "type": "keyword" },
          "borrower": { "type": "keyword" },
          "amount": { "type": "long" },
          "amount_in": { "type": "long" },
          "amount_out": { "type": "long" },
          "fee_amount": { "type": "long" },
          "reserve_a": { "type": "long" },
          "reserve_b": { "type": "long" },
          "price_impact": { "type": "long" },
          "twap_price": { "type": "long" },
          "spot_price": { "type": "long" },
          "deviation_bps": { "type": "long" },
          "timestamp": { "type": "date" }
        }
      }
    }
  }
}
' 2>/dev/null || echo "Index may already exist"

echo -e "${GREEN}✓${NC} Index created/updated"
echo ""

# Read JSON and insert with bulk API
echo -e "${YELLOW}📤 Inserting data...${NC}"

# Convert JSON array to bulk format
# Each document needs: {"index": {"_index": "index_name"}}
# Followed by: {document}

BULK_FILE="/tmp/bulk_insert_$$.ndjson"

# Parse JSON array and create bulk insert file
python3 << 'PYTHON_SCRIPT'
import json
import sys

input_file = sys.argv[1]
output_file = sys.argv[2]
index_name = sys.argv[3]

with open(input_file, 'r') as f:
    transactions = json.load(f)

with open(output_file, 'w') as out:
    for tx in transactions:
        # Index action
        index_action = {"index": {"_index": index_name}}
        out.write(json.dumps(index_action) + '\n')

        # Document
        out.write(json.dumps(tx) + '\n')

print(f"Created bulk file with {len(transactions)} transactions")
PYTHON_SCRIPT

python3 -c "
import json
import sys
input_file = '$JSON_FILE'
output_file = '$BULK_FILE'
index_name = '$ES_INDEX'

with open(input_file, 'r') as f:
    transactions = json.load(f)

with open(output_file, 'w') as out:
    for tx in transactions:
        index_action = {'index': {'_index': index_name}}
        out.write(json.dumps(index_action) + '\n')
        out.write(json.dumps(tx) + '\n')

print(f'Created bulk file with {len(transactions)} transactions')
"

# Bulk insert
echo ""
echo -e "${YELLOW}⏳ Performing bulk insert...${NC}"

RESPONSE=$(curl -s -X POST "$ES_URL/_bulk" \
  -H 'Content-Type: application/x-ndjson' \
  --data-binary "@$BULK_FILE")

# Check for errors
ERRORS=$(echo "$RESPONSE" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('errors', False))")
TOOK=$(echo "$RESPONSE" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('took', 0))")
ITEMS=$(echo "$RESPONSE" | python3 -c "import sys, json; data=json.load(sys.stdin); print(len(data.get('items', [])))")

if [ "$ERRORS" = "True" ]; then
    echo -e "${RED}❌ Some errors occurred during bulk insert${NC}"
    echo "$RESPONSE" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for item in data.get('items', []):
    if 'error' in item.get('index', {}):
        print(f\"Error: {item['index']['error']}\")
" | head -10
else
    echo -e "${GREEN}✓${NC} Successfully inserted ${ITEMS} documents in ${TOOK}ms"
fi

# Cleanup
rm -f "$BULK_FILE"

echo ""

# Refresh index
echo -e "${YELLOW}🔄 Refreshing index...${NC}"
curl -s -X POST "$ES_URL/$ES_INDEX/_refresh" > /dev/null
echo -e "${GREEN}✓${NC} Index refreshed"

echo ""

# Get stats
echo -e "${BLUE}📊 Index Statistics:${NC}"
curl -s -X GET "$ES_URL/$ES_INDEX/_stats" | python3 -c "
import sys, json
data = json.load(sys.stdin)
indices = data.get('indices', {})
for index_name, stats in indices.items():
    total = stats['total']
    print(f\"  Index: {index_name}\")
    print(f\"  Documents: {total['docs']['count']:,}\")
    print(f\"  Size: {total['store']['size_in_bytes'] / 1024 / 1024:.2f} MB\")
"

echo ""

# Count by attack type
echo -e "${BLUE}🎯 Attack Type Distribution:${NC}"
curl -s -X GET "$ES_URL/$ES_INDEX/_search" -H 'Content-Type: application/json' -d'
{
  "size": 0,
  "aggs": {
    "attack_types": {
      "terms": {
        "field": "attack_type",
        "size": 10,
        "missing": "normal"
      }
    }
  }
}
' | python3 -c "
import sys, json
data = json.load(sys.stdin)
buckets = data['aggregations']['attack_types']['buckets']
for bucket in buckets:
    print(f\"  {bucket['key']:20s}: {bucket['doc_count']:5d} transactions\")
"

echo ""

# Sample queries
echo -e "${BLUE}🔍 Sample Queries:${NC}"
echo ""
echo -e "${GREEN}1. Get all flash loan attacks:${NC}"
echo "curl -X GET \"$ES_URL/$ES_INDEX/_search\" -H 'Content-Type: application/json' -d'"
echo '{
  "query": {
    "term": {"attack_type": "flash_loan"}
  }
}'
echo "'"
echo ""

echo -e "${GREEN}2. Get transactions with high price impact (>20%):${NC}"
echo "curl -X GET \"$ES_URL/$ES_INDEX/_search\" -H 'Content-Type: application/json' -d'"
echo '{
  "query": {
    "nested": {
      "path": "events",
      "query": {
        "range": {
          "events.price_impact": {"gte": 2000}
        }
      }
    }
  }
}'
echo "'"
echo ""

echo -e "${GREEN}3. Get sandwich attacks:${NC}"
echo "curl -X GET \"$ES_URL/$ES_INDEX/_search?q=attack_type:sandwich\""
echo ""

echo -e "${GREEN}✅ Data insertion complete!${NC}"
echo ""
echo -e "${YELLOW}💡 Next steps:${NC}"
echo "  1. Open Kibana: http://localhost:5601"
echo "  2. Create index pattern: $ES_INDEX*"
echo "  3. Start building dashboards and visualizations"
echo "  4. Run detection queries to test your algorithms"
echo ""
