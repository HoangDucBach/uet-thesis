#!/bin/bash
# Insert generated DeFi data into Elasticsearch for testing
# Usage: ./insert_to_elasticsearch.sh [json_file]

set -e

# Configuration
ES_URL="${ELASTICSEARCH_URL:-http://localhost:9200}"
ES_INDEX="${ELASTICSEARCH_INDEX:-sui-transactions}"
JSON_FILE="${1:-defi_transactions_1500.json}"

# Check if JSON file exists
if [ ! -f "$JSON_FILE" ]; then
    echo "Error: JSON file not found: $JSON_FILE"
    echo "Generate data first: python3 generate_defi_data.py"
    exit 1
fi

# Check Elasticsearch connection
if ! curl -s "$ES_URL" > /dev/null; then
    echo "Cannot connect to Elasticsearch at $ES_URL"
    echo "Make sure Elasticsearch is running:"
    echo "  docker run -p 9200:9200 -d elasticsearch:8.11.0"
    exit 1
fi

# Create index with proper mapping

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

# Batch size for bulk insert (to avoid 413 errors)
BATCH_SIZE=100

# Insert data in batches
python3 << PYTHON_SCRIPT
import json
import sys
import subprocess
import os

input_file = '$JSON_FILE'
index_name = '$ES_INDEX'
es_url = '$ES_URL'
batch_size = $BATCH_SIZE

with open(input_file, 'r') as f:
    transactions = json.load(f)

total = len(transactions)
total_inserted = 0
total_errors = 0
total_took = 0

print(f'Inserting {total} transactions in batches of {batch_size}...')

for i in range(0, total, batch_size):
    batch = transactions[i:i + batch_size]
    batch_num = (i // batch_size) + 1
    total_batches = (total + batch_size - 1) // batch_size
    
    # Create bulk format for this batch
    bulk_data = []
    for tx in batch:
        index_action = {'index': {'_index': index_name}}
        bulk_data.append(json.dumps(index_action))
        bulk_data.append(json.dumps(tx))
    
    bulk_content = '\n'.join(bulk_data) + '\n'
    
    # Write to temporary file
    import tempfile
    with tempfile.NamedTemporaryFile(mode='w', suffix='.ndjson', delete=False) as tmp_file:
        tmp_file.write(bulk_content)
        tmp_file_path = tmp_file.name
    
    try:
        # Perform bulk insert
        result = subprocess.run(
            ['curl', '-s', '-w', '\n%{http_code}', '-X', 'POST', f'{es_url}/{index_name}/_bulk',
             '-H', 'Content-Type: application/x-ndjson',
             '--data-binary', f'@{tmp_file_path}'],
            capture_output=True,
            text=True
        )
        
        # Extract HTTP code and response
        output_lines = result.stdout.strip().split('\n')
        http_code = output_lines[-1]
        response_body = '\n'.join(output_lines[:-1])
        
        if http_code != '200':
            print(f'  Batch {batch_num}/{total_batches}: HTTP {http_code}')
            if len(response_body) < 500:
                print(f'    Response: {response_body}')
            total_errors += len(batch)
        else:
            try:
                data = json.loads(response_body)
                errors = data.get('errors', False)
                took = data.get('took', 0)
                items = len(data.get('items', []))
                
                if errors:
                    error_count = sum(1 for item in data.get('items', []) 
                                    if 'error' in item.get('index', {}))
                    print(f'  Batch {batch_num}/{total_batches}: {items} docs, {error_count} errors ({took}ms)')
                    total_errors += error_count
                else:
                    print(f'  Batch {batch_num}/{total_batches}: {items} docs ({took}ms)')
                
                total_inserted += items
                total_took += took
            except json.JSONDecodeError as e:
                print(f'  Batch {batch_num}/{total_batches}: JSON parse error: {e}')
                total_errors += len(batch)
    finally:
        os.unlink(tmp_file_path)

print(f'\nSummary:')
print(f'  Total inserted: {total_inserted}/{total}')
print(f'  Errors: {total_errors}')
print(f'  Total time: {total_took}ms')

if total_errors > 0:
    sys.exit(1)
PYTHON_SCRIPT

INSERT_STATUS=$?

if [ $INSERT_STATUS -ne 0 ]; then
    echo "Some batches failed during bulk insert"
    exit 1
fi

# Refresh index
curl -s -X POST "$ES_URL/$ES_INDEX/_refresh" > /dev/null

# Get stats
echo "Index Statistics:"
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

# Count by attack type
echo "Attack Type Distribution:"
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
