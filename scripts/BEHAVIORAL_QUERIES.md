# 🔍 Behavioral Pattern Detection Queries for Elasticsearch

**⚠️ IMPORTANT:** These queries detect behavioral patterns from NORMAL-looking transaction data. There are NO explicit behavior tags - patterns must be discovered through time-series analysis, address relationships, amount patterns, and frequency analysis.

## Data Structure Reference

```json
{
  "tx_digest": "abc123...",
  "checkpoint_sequence_number": 1000000,
  "timestamp_ms": "2024-12-07T10:00:00Z",
  "sender": "0x1a2b...",
  "execution_status": "success",
  "kind": "ProgrammableTransaction",

  "gas": {
    "owner": "0x1a2b...",
    "budget": 10000000,
    "price": 1000,
    "used": 1500000
  },

  "move_calls": [
    {
      "package": "0x0a78ed...",
      "module": "simple_dex",
      "function": "swap_a_to_b",
      "full_name": "0x0a78ed...::simple_dex::swap_a_to_b"
    }
  ],

  "events": [
    {
      "type": "0x0a78ed...::simple_dex::SwapExecuted<...>",
      "package": "0x0a78ed...",
      "module": "simple_dex",
      "sender": "0x1a2b...",
      "event_data": {
        "pool_id": "0xcd7c37...",
        "sender": "0x1a2b...",
        "token_in": true,
        "amount_in": 10000000000,
        "amount_out": 9970000000,
        "fee_amount": 30000000,
        "reserve_a": 5000000000,
        "reserve_b": 5000000000,
        "price_impact": 50
      }
    }
  ],

  "packages": ["0x0a78ed..."],
  "modules": ["simple_dex"],
  "functions": ["swap_a_to_b"]
}
```

**NOTE:** `event_data` field requires extending the indexer to parse event BCS data. Current indexer only has `type`, `package`, `module`, `sender`.

---

## 1. WASH TRADING DETECTION

### Query 1.1: Find Address Pairs with High Swap Frequency (30min window)

**Pattern:** Two addresses trading back-and-forth to create fake volume.
**Indicators:** >10 swaps, same pool, similar amounts, low price impact

```bash
# Step 1: Find all swaps in last 30 minutes with swap events
curl -X POST "localhost:9200/sui-transactions/_search?pretty" -H 'Content-Type: application/json' -d'
{
  "size": 1000,
  "query": {
    "bool": {
      "must": [
        {"term": {"modules": "simple_dex"}},
        {"term": {"functions": {"value": "swap_a_to_b", "boost": 1}}},
        {"range": {"timestamp_ms": {"gte": "now-30m"}}}
      ]
    }
  },
  "_source": ["tx_digest", "sender", "timestamp_ms", "events.event_data.pool_id", "events.event_data.amount_in", "events.event_data.price_impact"]
}
'
```

### Query 1.2: Aggregate by Pool and Find High-Frequency Address Pairs

```bash
curl -X POST "localhost:9200/sui-transactions/_search?pretty" -H 'Content-Type: application/json' -d'
{
  "size": 0,
  "query": {
    "bool": {
      "must": [
        {"term": {"modules": "simple_dex"}},
        {"range": {"timestamp_ms": {"gte": "now-30m"}}}
      ]
    }
  },
  "aggs": {
    "by_pool": {
      "terms": {"field": "events.event_data.pool_id.keyword", "size": 20},
      "aggs": {
        "by_sender": {
          "terms": {"field": "sender.keyword", "min_doc_count": 5, "size": 100},
          "aggs": {
            "tx_count": {"value_count": {"field": "tx_digest.keyword"}},
            "avg_price_impact": {
              "avg": {"field": "events.event_data.price_impact"}
            },
            "avg_amount": {
              "avg": {"field": "events.event_data.amount_in"}
            },
            "time_range": {
              "stats": {"field": "timestamp_ms"}
            }
          }
        }
      }
    }
  }
}
'
```

**Alert Rule:**
- If address pair (A, B) both trade same pool
- tx_count > 10 in 30min window
- avg_price_impact < 100 (less than 1%)
- avg_amount variance < 10%
- **=> HIGH CONFIDENCE wash trading**

### Query 1.3: Detect Alternating Pattern Between Two Addresses

Use Python/Logstash to post-process and find alternating address patterns in transaction sequences.

---

## 2. MONEY LAUNDERING DETECTION

### Query 2.1: Find Long Chains of Sequential Swaps

**Pattern:** Funds moving through many addresses (layering)
**Indicators:** >5 unique addresses, sequential timing (2-5min apart), possibly small amounts (structuring)

```bash
# Find all swaps ordered by time
curl -X POST "localhost:9200/sui-transactions/_search?pretty" -H 'Content-Type: application/json' -d'
{
  "size": 1000,
  "query": {
    "bool": {
      "must": [
        {"term": {"modules": "simple_dex"}},
        {"range": {"timestamp_ms": {"gte": "now-1h"}}}
      ]
    }
  },
  "sort": [{"timestamp_ms": "asc"}],
  "_source": ["tx_digest", "sender", "timestamp_ms", "events.event_data.amount_in", "events.event_data.amount_out", "events.event_data.pool_id"]
}
'
```

### Query 2.2: Detect Structuring (Multiple Small Amounts < 10M from Same Address)

```bash
curl -X POST "localhost:9200/sui-transactions/_search?pretty" -H 'Content-Type: application/json' -d'
{
  "size": 0,
  "query": {
    "bool": {
      "must": [
        {"term": {"modules": "simple_dex"}},
        {"range": {"events.event_data.amount_in": {"lte": 10000000000}}},
        {"range": {"timestamp_ms": {"gte": "now-1h"}}}
      ]
    }
  },
  "aggs": {
    "by_sender": {
      "terms": {"field": "sender.keyword", "min_doc_count": 3, "size": 100},
      "aggs": {
        "small_tx_count": {"value_count": {"field": "tx_digest.keyword"}},
        "total_amount": {"sum": {"field": "events.event_data.amount_in"}},
        "avg_amount": {"avg": {"field": "events.event_data.amount_in"}},
        "unique_pools": {"cardinality": {"field": "events.event_data.pool_id.keyword"}}
      }
    }
  }
}
'
```

**Alert Rule:**
- small_tx_count >= 3 in 1 hour
- All amounts < 10M units
- unique_pools > 1 (using different pools to obscure)
- **=> MEDIUM CONFIDENCE structuring for money laundering**

### Query 2.3: Graph Analysis - Find Address Chains

Use Graph API or Painless script to detect chains:

```bash
curl -X POST "localhost:9200/_xpack/graph/_explore?pretty" -H 'Content-Type: application/json' -d'
{
  "query": {
    "bool": {
      "must": [
        {"term": {"modules": "simple_dex"}},
        {"range": {"timestamp_ms": {"gte": "now-2h"}}}
      ]
    }
  },
  "vertices": [
    {
      "field": "sender.keyword",
      "size": 100,
      "min_doc_count": 2
    }
  ],
  "connections": {
    "vertices": [
      {"field": "sender.keyword"}
    ]
  }
}
'
```

Analyze the graph to find chains of length >5 within 40 minutes.

---

## 3. CIRCULAR FUND FLOW DETECTION

### Query 3.1: Detect Cycles in Address Transaction Graph

**Pattern:** A → B → C → D → A (funds returning to origin)
**Indicators:** 4-6 addresses, quick succession (1-2min apart), similar amounts

```bash
# Get all swaps in time window
curl -X POST "localhost:9200/sui-transactions/_search?pretty" -H 'Content-Type: application/json' -d'
{
  "size": 500,
  "query": {
    "bool": {
      "must": [
        {"term": {"modules": "simple_dex"}},
        {"range": {"timestamp_ms": {"gte": "now-30m"}}}
      ]
    }
  },
  "sort": [{"timestamp_ms": "asc"}],
  "_source": ["tx_digest", "sender", "timestamp_ms", "events.event_data.amount_in", "events.event_data.amount_out"]
}
'
```

**Post-processing:** Build directed graph and find cycles using DFS/BFS.

### Query 3.2: Find Addresses Involved in Multiple Rapid Swaps

```bash
curl -X POST "localhost:9200/sui-transactions/_search?pretty" -H 'Content-Type: application/json' -d'
{
  "size": 0,
  "query": {
    "bool": {
      "must": [
        {"term": {"modules": "simple_dex"}},
        {"range": {"timestamp_ms": {"gte": "now-15m"}}}
      ]
    }
  },
  "aggs": {
    "by_sender": {
      "terms": {"field": "sender.keyword", "size": 200},
      "aggs": {
        "tx_count": {"value_count": {"field": "tx_digest.keyword"}},
        "time_span_ms": {
          "bucket_script": {
            "buckets_path": {
              "max_ts": "time_stats.max",
              "min_ts": "time_stats.min"
            },
            "script": "params.max_ts - params.min_ts"
          }
        },
        "time_stats": {"stats": {"field": "timestamp_ms"}}
      }
    }
  }
}
'
```

**Alert Rule:**
- tx_count >= 3
- time_span < 600000ms (10 minutes)
- Check if these addresses form a cycle
- **=> MEDIUM CONFIDENCE circular flow**

---

## 4. HIGH-FREQUENCY TRADING (HFT) MANIPULATION

### Query 4.1: Detect Burst of Trades from Single Address

**Pattern:** Single address, 20-50 txs in 2-3 minutes, same pool
**Indicators:** High frequency, alternating directions, price manipulation intent

```bash
curl -X POST "localhost:9200/sui-transactions/_search?pretty" -H 'Content-Type: application/json' -d'
{
  "size": 0,
  "query": {
    "bool": {
      "must": [
        {"term": {"modules": "simple_dex"}},
        {"range": {"timestamp_ms": {"gte": "now-5m"}}}
      ]
    }
  },
  "aggs": {
    "by_sender": {
      "terms": {"field": "sender.keyword", "min_doc_count": 15, "size": 50},
      "aggs": {
        "tx_count": {"value_count": {"field": "tx_digest.keyword"}},
        "by_pool": {
          "terms": {"field": "events.event_data.pool_id.keyword", "size": 5}
        },
        "time_stats": {"stats": {"field": "timestamp_ms"}},
        "tx_per_minute": {
          "bucket_script": {
            "buckets_path": {
              "count": "_count",
              "time_span": "time_stats.max - time_stats.min"
            },
            "script": "params.count / ((params.time_span / 1000.0) / 60.0 + 0.001)"
          }
        }
      }
    }
  }
}
'
```

**Alert Rule:**
- tx_count >= 20 in 5min
- tx_per_minute > 10
- Most txs target same pool
- **=> HIGH CONFIDENCE HFT manipulation**

### Query 4.2: Find Addresses with Abnormally High Transaction Rate

```bash
curl -X POST "localhost:9200/sui-transactions/_search?pretty" -H 'Content-Type: application/json' -d'
{
  "size": 0,
  "query": {
    "range": {"timestamp_ms": {"gte": "now-10m"}}
  },
  "aggs": {
    "sender_frequency": {
      "terms": {
        "field": "sender.keyword",
        "order": {"_count": "desc"},
        "size": 20
      },
      "aggs": {
        "minute_histogram": {
          "date_histogram": {
            "field": "timestamp_ms",
            "fixed_interval": "1m"
          }
        }
      }
    }
  }
}
'
```

Look for addresses with >10 txs/minute sustained over multiple minutes.

---

## 5. COORDINATED ATTACK DETECTION

### Query 5.1: Detect Multiple Addresses Targeting Same Pool

**Pattern:** 5-8 different addresses, same pool, within 5-10 minutes
**Indicators:** Coordinated timing, same target, possible collusion

```bash
curl -X POST "localhost:9200/sui-transactions/_search?pretty" -H 'Content-Type: application/json' -d'
{
  "size": 0,
  "query": {
    "bool": {
      "must": [
        {"term": {"modules": "simple_dex"}},
        {"range": {"timestamp_ms": {"gte": "now-15m"}}}
      ]
    }
  },
  "aggs": {
    "by_pool": {
      "terms": {"field": "events.event_data.pool_id.keyword", "size": 20},
      "aggs": {
        "unique_senders": {
          "cardinality": {"field": "sender.keyword"}
        },
        "tx_count": {"value_count": {"field": "tx_digest.keyword"}},
        "time_range_ms": {
          "bucket_script": {
            "buckets_path": {
              "max_ts": "time_stats.max",
              "min_ts": "time_stats.min"
            },
            "script": "params.max_ts - params.min_ts"
          }
        },
        "time_stats": {"stats": {"field": "timestamp_ms"}},
        "senders": {
          "terms": {"field": "sender.keyword", "size": 100}
        }
      }
    }
  }
}
'
```

**Alert Rule:**
- unique_senders >= 5
- time_range < 600000ms (10 minutes)
- tx_count >= 10
- **=> HIGH CONFIDENCE coordinated attack**

### Query 5.2: Find Clusters of Addresses Acting Simultaneously

```bash
curl -X POST "localhost:9200/sui-transactions/_search?pretty" -H 'Content-Type: application/json' -d'
{
  "size": 1000,
  "query": {
    "bool": {
      "must": [
        {"term": {"modules": "simple_dex"}},
        {"range": {"timestamp_ms": {"gte": "now-10m"}}}
      ]
    }
  },
  "sort": [{"timestamp_ms": "asc"}],
  "aggs": {
    "time_buckets": {
      "date_histogram": {
        "field": "timestamp_ms",
        "fixed_interval": "1m"
      },
      "aggs": {
        "unique_senders": {"cardinality": {"field": "sender.keyword"}},
        "by_pool": {
          "terms": {"field": "events.event_data.pool_id.keyword", "size": 10}
        }
      }
    }
  }
}
'
```

Look for time buckets with unusually high unique_senders targeting same pool.

---

## 6. ELASTICSEARCH INDEX MAPPING

For optimal query performance, create index with this mapping:

```bash
curl -X PUT "localhost:9200/sui-transactions?pretty" -H 'Content-Type: application/json' -d'
{
  "mappings": {
    "properties": {
      "tx_digest": {"type": "keyword"},
      "checkpoint_sequence_number": {"type": "long"},
      "timestamp_ms": {"type": "date"},
      "sender": {"type": "keyword"},
      "execution_status": {"type": "keyword"},
      "kind": {"type": "keyword"},

      "gas": {
        "properties": {
          "owner": {"type": "keyword"},
          "budget": {"type": "long"},
          "price": {"type": "long"},
          "used": {"type": "long"}
        }
      },

      "move_calls": {
        "type": "nested",
        "properties": {
          "package": {"type": "keyword"},
          "module": {"type": "keyword"},
          "function": {"type": "keyword"},
          "full_name": {"type": "keyword"}
        }
      },

      "events": {
        "type": "nested",
        "properties": {
          "type": {"type": "keyword"},
          "package": {"type": "keyword"},
          "module": {"type": "keyword"},
          "sender": {"type": "keyword"},
          "event_data": {
            "properties": {
              "pool_id": {"type": "keyword"},
              "sender": {"type": "keyword"},
              "token_in": {"type": "boolean"},
              "amount_in": {"type": "long"},
              "amount_out": {"type": "long"},
              "fee_amount": {"type": "long"},
              "reserve_a": {"type": "long"},
              "reserve_b": {"type": "long"},
              "price_impact": {"type": "integer"}
            }
          }
        }
      },

      "packages": {"type": "keyword"},
      "modules": {"type": "keyword"},
      "functions": {"type": "keyword"}
    }
  }
}
'
```

---

## 7. KIBANA DASHBOARDS

### Dashboard 1: Wash Trading Monitor

- **Time-series chart:** Swaps per minute by pool
- **Table:** Top address pairs by frequency (>10 swaps/30min)
- **Metric:** Average price impact for high-frequency pairs
- **Alert:** Price impact < 1% AND swap count > 15

### Dashboard 2: Money Laundering Tracker

- **Network graph:** Address relationship visualization
- **Histogram:** Transaction amount distribution (identify structuring)
- **Table:** Addresses with multiple small transactions
- **Alert:** >3 small txs (<10M) from same address in 1 hour

### Dashboard 3: HFT Detection

- **Metric:** Max txs/minute from any address
- **Time-series:** Transaction frequency by address
- **Table:** Top addresses by transaction rate
- **Alert:** >20 txs in 3 minutes from single address

### Dashboard 4: Coordinated Attack Monitor

- **Heatmap:** Pools vs unique senders (time bucketed)
- **Table:** Pools with >5 unique senders in 10min
- **Network graph:** Address clustering by pool
- **Alert:** >5 addresses + same pool + <10min window

---

## 8. MACHINE LEARNING FEATURES

For ML-based anomaly detection, extract these features:

```python
features = {
    # Frequency features
    "tx_per_minute": ...,
    "swaps_per_hour": ...,
    "burst_score": ...,  # Max txs in any 3min window

    # Amount features
    "avg_amount": ...,
    "amount_std_dev": ...,
    "amount_variance": ...,
    "small_tx_ratio": ...,  # Ratio of txs < 10M

    # Network features
    "unique_addresses_interacted": ...,
    "graph_centrality": ...,
    "clustering_coefficient": ...,

    # Temporal features
    "time_between_txs_avg": ...,
    "time_between_txs_std": ...,
    "active_time_span": ...,

    # Price impact features
    "avg_price_impact": ...,
    "max_price_impact": ...,
    "low_impact_ratio": ...,  # Ratio of txs with impact < 1%
}
```

Train models (Isolation Forest, LSTM, etc.) on these features for automated detection.

---

## 9. PYTHON POST-PROCESSING SCRIPTS

### Script: Detect Wash Trading Pairs

```python
import requests
from collections import defaultdict
from datetime import datetime, timedelta

def detect_wash_trading():
    # Get last 30min of swaps
    query = {
        "query": {
            "bool": {
                "must": [
                    {"term": {"modules": "simple_dex"}},
                    {"range": {"timestamp_ms": {"gte": "now-30m"}}}
                ]
            }
        },
        "size": 1000,
        "sort": [{"timestamp_ms": "asc"}]
    }

    resp = requests.post("http://localhost:9200/sui-transactions/_search", json=query)
    txs = resp.json()['hits']['hits']

    # Group by pool
    pool_swaps = defaultdict(list)
    for tx in txs:
        source = tx['_source']
        pool_id = source['events'][0]['event_data']['pool_id']
        pool_swaps[pool_id].append({
            'sender': source['sender'],
            'timestamp': source['timestamp_ms'],
            'amount': source['events'][0]['event_data']['amount_in'],
            'price_impact': source['events'][0]['event_data']['price_impact']
        })

    # Find alternating pairs
    for pool_id, swaps in pool_swaps.items():
        if len(swaps) < 10:
            continue

        # Check for alternating pattern
        address_sequence = [s['sender'] for s in swaps]
        # Find pairs that alternate frequently
        # ... analysis logic ...
```

### Script: Build Transaction Graph for Circular Detection

```python
import networkx as nx

def build_transaction_graph(txs):
    G = nx.DiGraph()

    for tx in txs:
        sender = tx['_source']['sender']
        # Infer receiver from amount_out flow
        # Add edge to graph
        G.add_edge(sender, receiver, weight=amount)

    # Find cycles
    cycles = list(nx.simple_cycles(G))
    suspicious_cycles = [c for c in cycles if 4 <= len(c) <= 6]

    return suspicious_cycles
```

---

## 10. SUMMARY

### Detection Confidence Levels

| Pattern | Query Indicators | Confidence |
|---------|-----------------|------------|
| Wash Trading | 2 addresses, >15 swaps/30min, same pool, low impact | HIGH |
| Money Laundering | >5 address chain, small amounts, sequential timing | MEDIUM |
| Circular Flow | 4-6 address cycle, <10min completion | MEDIUM |
| HFT Manipulation | >20 txs/3min, single address, same pool | HIGH |
| Coordinated Attack | >5 addresses, same pool, <10min window | HIGH |

### Next Steps

1. **Index Creation:** Create ES index with proper mapping
2. **Data Generation:** Run `generate_behavioral_data.py`
3. **Data Insertion:** Use bulk API to insert test data
4. **Query Testing:** Run queries above to verify pattern detection
5. **Dashboard Setup:** Create Kibana visualizations
6. **ML Training:** Extract features and train anomaly detection models
7. **Production Integration:** Extend sui-indexer to parse and index event_data fields

**🔧 NOTE:** Current indexer needs enhancement to parse event BCS data and include in Elasticsearch documents.
