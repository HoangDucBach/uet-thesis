# 🧪 DeFi Attack Detection Testing Guide

## 📦 Quick Start

### 1. Generate Test Data (1500+ transactions)

```bash
cd /home/user/uet-thesis/scripts

# Generate realistic data
python3 generate_defi_data.py

# Output: defi_transactions_1500.json
```

**Data Distribution:**
- 60% Normal swaps (900 txs)
- 10% Flash loan attacks (150 txs)
- 8% Price manipulation (120 txs)
- 5% Sandwich attacks (75 txs = 25 sequences × 3)
- 15% Liquidity operations (225 txs)
- 2% Lending operations (30 txs)

**Features:**
- ✅ 90% realistic patterns (based on real DeFi behavior)
- ✅ 50+ unique addresses (MEV bots, normal users, LPs)
- ✅ Diverse pool interactions
- ✅ Realistic amounts and price impacts
- ✅ Time-series data (spread over hours)
- ✅ All contract IDs from your deployment

---

### 2. Insert into Elasticsearch

```bash
# Make script executable
chmod +x insert_to_elasticsearch.sh

# Start Elasticsearch (if not running)
docker run --name sui-elasticsearch \
  -e "discovery.type=single-node" \
  -e "xpack.security.enabled=false" \
  -p 9200:9200 \
  -d elasticsearch:8.11.0

# Wait 20 seconds for ES to start

# Insert data
./insert_to_elasticsearch.sh defi_transactions_1500.json
```

**Expected Output:**
```
✓ Connected to Elasticsearch
✓ Index created/updated
✓ Successfully inserted 1500 documents in 2500ms
✓ Index refreshed

📊 Index Statistics:
  Documents: 1,500
  Size: 2.34 MB

🎯 Attack Type Distribution:
  normal              : 1,095 transactions
  flash_loan          :   150 transactions
  price_manipulation  :   120 transactions
  sandwich            :    75 transactions
```

---

### 3. Start Kibana (Optional but Recommended)

```bash
docker run --name sui-kibana \
  --link sui-elasticsearch:elasticsearch \
  -e "ELASTICSEARCH_HOSTS=http://elasticsearch:9200" \
  -p 5601:5601 \
  -d kibana:8.11.0

# Wait 30-60 seconds, then open
open http://localhost:5601
```

**Setup in Kibana:**
1. Go to **Stack Management** → **Index Patterns**
2. Create pattern: `sui-transactions*`
3. Time field: `timestamp_ms`
4. Save

---

## 🔍 Testing Detection Algorithms

### A. Flash Loan Attack Detection

**Query: Find all flash loan attacks**

```bash
curl -X GET "localhost:9200/sui-transactions/_search" -H 'Content-Type: application/json' -d'
{
  "size": 100,
  "query": {
    "term": {
      "attack_type": "flash_loan"
    }
  }
}'
```

**Advanced: Find flash loans with 4+ swaps (circular trading)**

```bash
curl -X GET "localhost:9200/sui-transactions/_search" -H 'Content-Type: application/json' -d'
{
  "size": 50,
  "query": {
    "bool": {
      "must": [
        {"term": {"attack_type": "flash_loan"}},
        {
          "script": {
            "script": {
              "source": "doc[\"events.type\"].values.stream().filter(t -> t == \"SwapExecuted\").count() >= 4"
            }
          }
        }
      ]
    }
  }
}'
```

**Find flash loans with high price impact (>10%)**

```bash
curl -X GET "localhost:9200/sui-transactions/_search" -H 'Content-Type: application/json' -d'
{
  "size": 50,
  "query": {
    "bool": {
      "must": [
        {
          "nested": {
            "path": "events",
            "query": {
              "term": {"events.type": "FlashLoanTaken"}
            }
          }
        },
        {
          "nested": {
            "path": "events",
            "query": {
              "range": {
                "events.price_impact": {"gte": 1000}
              }
            }
          }
        }
      ]
    }
  },
  "_source": ["tx_digest", "sender", "events"]
}'
```

---

### B. Price Manipulation Detection

**Query: High price impact transactions (>15%)**

```bash
curl -X GET "localhost:9200/sui-transactions/_search" -H 'Content-Type: application/json' -d'
{
  "size": 100,
  "query": {
    "nested": {
      "path": "events",
      "query": {
        "bool": {
          "must": [
            {"term": {"events.type": "SwapExecuted"}},
            {"range": {"events.price_impact": {"gte": 1500}}}
          ]
        }
      }
    }
  },
  "sort": [
    {
      "events.price_impact": {
        "order": "desc",
        "nested": {
          "path": "events"
        }
      }
    }
  ]
}'
```

**Query: TWAP deviation detected**

```bash
curl -X GET "localhost:9200/sui-transactions/_search" -H 'Content-Type: application/json' -d'
{
  "size": 100,
  "query": {
    "nested": {
      "path": "events",
      "query": {
        "bool": {
          "must": [
            {"term": {"events.type": "PriceDeviationDetected"}},
            {"range": {"events.deviation_bps": {"gte": 1000}}}
          ]
        }
      }
    }
  }
}'
```

**Query: Large swaps (>30% of pool reserves)**

```bash
curl -X GET "localhost:9200/sui-transactions/_search" -H 'Content-Type: application/json' -d'
{
  "size": 100,
  "query": {
    "nested": {
      "path": "events",
      "query": {
        "script": {
          "script": {
            "source": """
              def event = params._source;
              if (event.type == \"SwapExecuted\" && event.reserve_a > 0) {
                double ratio = (double)event.amount_in / event.reserve_a;
                return ratio > 0.30;
              }
              return false;
            """
          }
        }
      }
    }
  }
}'
```

---

### C. Sandwich Attack Detection

**Query: Find sandwich attack patterns**

Since sandwich attacks involve 3 transactions (front-run → victim → back-run), we need to:

1. **Find back-run transactions (marked as sandwich)**

```bash
curl -X GET "localhost:9200/sui-transactions/_search" -H 'Content-Type: application/json' -d'
{
  "size": 100,
  "query": {
    "term": {"attack_type": "sandwich"}
  },
  "sort": [{"timestamp_ms": "asc"}]
}'
```

2. **Find transactions by MEV bot addresses**

```bash
curl -X GET "localhost:9200/sui-transactions/_search" -H 'Content-Type: application/json' -d'
{
  "size": 1000,
  "query": {
    "terms": {
      "sender": [
        "0x1a2b3c4d5e6f7890abcdef1234567890abcdef12",
        "0x9876543210fedcba0987654321fedcba09876543",
        "0xdeadbeefcafebabe1234567890abcdef12345678"
      ]
    }
  },
  "sort": [{"timestamp_ms": "asc"}]
}'
```

3. **Aggregation: Count transactions per sender**

```bash
curl -X GET "localhost:9200/sui-transactions/_search" -H 'Content-Type: application/json' -d'
{
  "size": 0,
  "aggs": {
    "senders": {
      "terms": {
        "field": "sender",
        "size": 50,
        "order": {"_count": "desc"}
      }
    }
  }
}'
```

---

### D. Multi-Signal Analysis

**Query: Transactions with multiple risk signals**

```bash
curl -X GET "localhost:9200/sui-transactions/_search" -H 'Content-Type: application/json' -d'
{
  "size": 100,
  "query": {
    "bool": {
      "must": [
        {
          "nested": {
            "path": "events",
            "query": {"term": {"events.type": "FlashLoanTaken"}}
          }
        },
        {
          "nested": {
            "path": "events",
            "query": {"range": {"events.price_impact": {"gte": 1000}}}
          }
        }
      ],
      "filter": {
        "script": {
          "script": {
            "source": "doc[\"events.type\"].values.stream().filter(t -> t == \"SwapExecuted\").count() >= 3"
          }
        }
      }
    }
  }
}'
```

---

## 📊 Kibana Visualizations

### 1. Attack Type Distribution (Pie Chart)

**Visualization Type:** Pie

**Metrics:**
- Count

**Buckets:**
- Terms: `attack_type.keyword`
- Missing bucket label: "normal"

---

### 2. Price Impact Over Time (Line Chart)

**Visualization Type:** Line

**Metrics:**
- Max `events.price_impact`

**Buckets:**
- X-axis: Date Histogram on `timestamp_ms` (interval: 1h)

---

### 3. Top MEV Addresses (Bar Chart)

**Visualization Type:** Bar

**Metrics:**
- Count

**Buckets:**
- X-axis: Terms `sender` (size: 10)

**Filter:**
- Add filter: `attack_type` exists

---

### 4. Flash Loan Volume (Metric)

**Visualization Type:** Metric

**Metrics:**
- Sum of `events.amount`

**Filter:**
- `events.type: FlashLoanTaken`

---

### 5. Real-time Attack Feed (Data Table)

**Columns:**
- `timestamp_ms`
- `tx_digest`
- `sender`
- `attack_type`
- `events.price_impact` (max)

**Sort:** `timestamp_ms` desc

**Filter:**
- `attack_type` exists

---

## 🧮 Detection Algorithm Testing

### Test Case 1: Flash Loan with Circular Trading

**Expected Pattern:**
1. FlashLoanTaken event
2. 3+ SwapExecuted events
3. Same sender across swaps
4. Token flow: A → B → C → A
5. FlashLoanRepaid event

**Test Query:**
```bash
# Find all transactions with this pattern
curl -X GET "localhost:9200/sui-transactions/_search" -H 'Content-Type: application/json' -d'
{
  "size": 50,
  "query": {
    "bool": {
      "must": [
        {
          "nested": {
            "path": "events",
            "query": {"terms": {"events.type": ["FlashLoanTaken", "FlashLoanRepaid"]}},
            "inner_hits": {}
          }
        }
      ]
    }
  }
}'
```

**Scoring:**
- Flash loan present: +30
- 3+ swaps: +20
- High price impact (>10%): +25
- Multiple pools: +15
- **Expected Score:** 70-100 (High/Critical)

---

### Test Case 2: Price Manipulation without Flash Loan

**Expected Pattern:**
1. SwapExecuted with price_impact > 15%
2. Swap amount > 20% of pool reserves
3. Optional: TWAP deviation > 10%

**Test Query:**
```bash
curl -X GET "localhost:9200/sui-transactions/_search" -H 'Content-Type: application/json' -d'
{
  "size": 50,
  "query": {
    "bool": {
      "must": [
        {"term": {"attack_type": "price_manipulation"}},
        {
          "nested": {
            "path": "events",
            "query": {
              "range": {"events.price_impact": {"gte": 1500}}
            }
          }
        }
      ],
      "must_not": [
        {
          "nested": {
            "path": "events",
            "query": {"term": {"events.type": "FlashLoanTaken"}}
          }
        }
      ]
    }
  }
}'
```

**Scoring:**
- Price impact > 15%: +30
- Swap ratio > 20%: +25
- TWAP deviation > 10%: +15
- Consecutive swaps: +10
- **Expected Score:** 60-80 (Medium/High)

---

### Test Case 3: Sandwich Attack

**Expected Pattern:**
1. Transaction 1: Attacker swap (front-run)
2. Transaction 2: Victim swap (different sender)
3. Transaction 3: Attacker swap opposite direction (back-run)
4. All within 5 checkpoints / 30 seconds

**Test Query:**
```bash
# Get transactions grouped by checkpoint
curl -X GET "localhost:9200/sui-transactions/_search" -H 'Content-Type: application/json' -d'
{
  "size": 0,
  "aggs": {
    "by_checkpoint": {
      "terms": {
        "field": "checkpoint",
        "size": 100
      },
      "aggs": {
        "senders": {
          "terms": {
            "field": "sender",
            "size": 10
          }
        }
      }
    }
  }
}'
```

**Scoring:**
- Pattern match (3 txs): +40
- Attacker profit calculated: +30
- Victim loss > 5%: +20
- Time proximity (<30s): +10
- **Expected Score:** 70-100 (High/Critical)

---

## 📈 Performance Metrics

### Query Performance

```bash
# Measure query time
time curl -X GET "localhost:9200/sui-transactions/_search" -H 'Content-Type: application/json' -d'
{
  "size": 1000,
  "query": {"match_all": {}}
}'
```

**Expected:**
- 1000 docs: < 50ms
- 10000 docs: < 200ms
- Aggregations: < 100ms

### Index Stats

```bash
curl -X GET "localhost:9200/sui-transactions/_stats?pretty"
```

---

## 🎯 Success Criteria

### Detection Accuracy

| Attack Type | Total Generated | Should Detect | Acceptable FP |
|-------------|----------------|---------------|---------------|
| Flash Loan | 150 | 140+ (93%) | < 10 normal txs |
| Price Manip | 120 | 110+ (92%) | < 15 normal txs |
| Sandwich | 75 | 65+ (87%) | < 5 normal txs |

### Query Response Time

- Simple queries: < 50ms
- Complex aggregations: < 200ms
- Nested queries: < 150ms

---

## 🐛 Troubleshooting

**"Too many buckets"**
```bash
# Increase bucket limit
curl -X PUT "localhost:9200/_cluster/settings" -H 'Content-Type: application/json' -d'
{
  "persistent": {
    "search.max_buckets": 50000
  }
}'
```

**"Nested object limit"**
```bash
# Increase nested object limit
curl -X PUT "localhost:9200/sui-transactions/_settings" -H 'Content-Type: application/json' -d'
{
  "index.mapping.nested_objects.limit": 10000
}
'
```

**Slow queries**
```bash
# Enable query profiling
curl -X GET "localhost:9200/sui-transactions/_search" -H 'Content-Type: application/json' -d'
{
  "profile": true,
  "query": {...}
}'
```

---

## 📚 Next Steps

1. ✅ Generate data: `python3 generate_defi_data.py`
2. ✅ Insert to ES: `./insert_to_elasticsearch.sh`
3. ✅ Open Kibana: http://localhost:5601
4. ✅ Create visualizations and dashboards
5. ✅ Test detection queries
6. ✅ Measure accuracy and performance
7. ✅ Document results for thesis

---

**Questions or issues?** Check the main SETUP_GUIDE.md or indexer logs.
