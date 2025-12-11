# DeFi Attack Detection System v2

## Based on Academic Research & Industry Best Practices

### References
- Chainalysis Money Laundering Report 2024
- Elliptic AI-based AML Detection (2024)
- Victor & Weintraud: "Detecting and Quantifying Wash Trading on DEX" (WWW '21)
- Cong et al: "Crypto Wash Trading" (Management Science, 2023)
- Xia et al: "Detecting Flash Loan Based Attacks" (ICDCS '23)

---

## Data Schema (Sui Blockchain)

```json
{
  "tx_digest": "keyword",
  "timestamp_ms": "date",
  "sender": "keyword",
  "modules": ["simple_dex"],
  "functions": ["swap_a_to_b", "swap_b_to_a"],
  "gas_used": "long",
  "events": [{
    "type": "keyword",
    "package": "keyword",
    "module": "keyword",
    "sender": "keyword",
    "event_data": {
      "pool_id": "keyword",
      "amount_in": "long",
      "amount_out": "long",
      "token_in": "boolean",
      "price_impact": "long"
    }
  }]
}
```

**Note**: `events` is a **nested** type in Elasticsearch. Use nested queries when filtering/aggregating on `events.event_data.*` fields.

---

## 1. Wash Trading Detection

### Theory (Victor & Weintraud, WWW '21)

Wash trading forms **closed cycles** in transaction graphs where net position change = 0.
Detection via Strongly Connected Components (SCCs) in directed token trade graphs.

### 1.1 Self-Trade Detection (Same Sender, Opposite Directions)

**Query:**

```json
POST sui-transactions/_search
{
  "size": 0,
  "query": {
    "term": {"modules": "simple_dex"}
  },
  "aggs": {
    "by_sender": {
      "terms": {
        "field": "sender",
        "size": 100,
        "min_doc_count": 5
      },
      "aggs": {
        "directions": {
          "terms": {"field": "functions"}
        },
        "time_range": {
          "stats": {"field": "timestamp_ms"}
        },
        "events": {
          "nested": {"path": "events"},
          "aggs": {
            "pools": {
              "terms": {
                "field": "events.event_data.pool_id",
                "size": 5
              }
            },
            "amount_stats": {
              "extended_stats": {
                "field": "events.event_data.amount_in"
              }
            }
          }
        }
      }
    }
  }
}
```

**Post-processing Alert Criteria:**
- Both `swap_a_to_b` AND `swap_b_to_a` present
- Balance ratio: `|count(a_to_b) - count(b_to_a)| / total < 0.3`
- Single pool concentration > 60%
- Time span < 60 minutes
- Amount CV < 25% (uniform amounts)

### 1.2 Coordinated Wash Trading (Multiple Addresses)

**Query:**

```json
POST sui-transactions/_search
{
  "size": 0,
  "query": {
    "term": {"modules": "simple_dex"}
  },
  "aggs": {
    "by_pool": {
      "nested": {"path": "events"},
      "aggs": {
        "pools": {
          "terms": {
            "field": "events.event_data.pool_id",
            "size": 20
          },
          "aggs": {
            "back": {
              "reverse_nested": {},
              "aggs": {
                "time_buckets": {
                  "date_histogram": {
                    "field": "timestamp_ms",
                    "fixed_interval": "5m"
                  },
                  "aggs": {
                    "unique_senders": {
                      "cardinality": {"field": "sender"}
                    },
                    "direction_balance": {
                      "filters": {
                        "filters": {
                          "a_to_b": {"term": {"functions": "swap_a_to_b"}},
                          "b_to_a": {"term": {"functions": "swap_b_to_a"}}
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
```

**Alert Criteria:**
- 2-10 unique senders in same 5-min bucket
- Near-equal a_to_b and b_to_a counts (ratio < 0.3)
- Sequential timing pattern (tx1.a_to_b → tx2.b_to_a → tx3.a_to_b...)

### 1.3 Statistical Anomaly Detection (Benford's Law)

Post-processing Python code (see `detect_money_laundering.py`):

```python
def detect_benford_anomaly(amounts, threshold=0.05):
    """
    Detect wash trading via Benford's Law violation
    Real trades follow Benford's: ~30% start with 1, ~18% with 2, etc.
    Fake trades often cluster at round numbers
    """
    # Implementation in detect_money_laundering.py
    pass
```

---

## 2. Money Laundering Detection

### Theory (Chainalysis, Elliptic Research)

Real crypto laundering patterns:
1. **Peel Chains**: Large amount → split into decreasing smaller amounts (5-30% per hop)
2. **Layering via DEX**: Multiple swaps through different pools to obfuscate origin

### 2.1 Peel Chain Detection

**Query (retrieve transactions for post-processing):**

```json
POST sui-transactions/_search
{
  "size": 1000,
  "sort": [{"timestamp_ms": {"order": "asc"}}],
  "_source": [
    "sender",
    "timestamp_ms",
    "tx_digest",
    "events.event_data.amount_in",
    "events.event_data.amount_out",
    "events.event_data.pool_id"
  ],
  "query": {
    "bool": {
      "must": [
        {"term": {"modules": "simple_dex"}}
      ]
    }
  }
}
```

**Post-processing Algorithm:**
- Amount decreases at each hop (5-30% decay ratio)
- Max 10 minutes between hops
- Minimum chain length: 4 addresses
- See `detect_money_laundering.py` for full implementation

### 2.2 Layering Detection (Multiple Swaps to Obfuscate)

**Query:**

```json
POST sui-transactions/_search
{
  "size": 0,
  "query": {
    "term": {"modules": "simple_dex"}
  },
  "aggs": {
    "by_sender": {
      "terms": {
        "field": "sender",
        "size": 100,
        "min_doc_count": 3
      },
      "aggs": {
        "time_range": {
          "stats": {"field": "timestamp_ms"}
        },
        "unique_pools": {
          "nested": {"path": "events"},
          "aggs": {
            "pool_count": {
              "cardinality": {"field": "events.event_data.pool_id"}
            }
          }
        },
        "total_volume": {
          "nested": {"path": "events"},
          "aggs": {
            "sum": {"sum": {"field": "events.event_data.amount_in"}}
          }
        },
        "tx_count": {
          "value_count": {"field": "tx_digest"}
        }
      }
    }
  }
}
```

**Alert Criteria:**
- Single address using 3+ different pools
- Total volume > 10B
- Time span < 2 hours

---

## 3. Flash Loan Attack Detection

### Theory (Xia et al., ICDCS '23)

Flash loan attacks: Borrow large amounts, manipulate prices, profit, repay in single transaction.

### 3.1 Large Swap Detection (Price Manipulation)

**Query:**

```json
POST sui-transactions/_search
{
  "size": 0,
  "query": {
    "term": {"modules": "simple_dex"}
  },
  "aggs": {
    "large_swaps": {
      "nested": {"path": "events"},
      "aggs": {
        "high_volume": {
          "filter": {
            "range": {
              "events.event_data.amount_in": {"gte": 50000000000}
            }
          },
          "aggs": {
            "by_pool": {
              "terms": {
                "field": "events.event_data.pool_id"
              },
              "aggs": {
                "impact_stats": {
                  "extended_stats": {
                    "field": "events.event_data.price_impact"
                  }
                },
                "back": {
                  "reverse_nested": {},
                  "aggs": {
                    "time_concentration": {
                      "date_histogram": {
                        "field": "timestamp_ms",
                        "fixed_interval": "1m"
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
```

### 3.2 Sandwich Attack Detection

**Pattern**: Attacker front-runs victim's tx, then back-runs

Post-processing required (see `detect_money_laundering.py`):
- Front-run: `swap_a_to_b` (attacker)
- Victim: `swap_a_to_b` (gets worse price)
- Back-run: `swap_b_to_a` (attacker profits)
- All within ~30 seconds
- Same pool
- Same attacker address

---

## 4. Coordinated Market Manipulation

### 4.1 Pump Detection (Volume Spike)

**Query:**

```json
POST sui-transactions/_search
{
  "size": 0,
  "query": {
    "term": {"modules": "simple_dex"}
  },
  "aggs": {
    "by_pool": {
      "nested": {"path": "events"},
      "aggs": {
        "pools": {
          "terms": {
            "field": "events.event_data.pool_id",
            "size": 20
          },
          "aggs": {
            "back_to_parent": {
              "reverse_nested": {},
              "aggs": {
                "hourly_volume": {
                  "date_histogram": {
                    "field": "timestamp_ms",
                    "fixed_interval": "1h"
                  },
                  "aggs": {
                    "to_events": {
                      "nested": {"path": "events"},
                      "aggs": {
                        "volume": {
                          "sum": {"field": "events.event_data.amount_in"}
                        },
                        "avg_impact": {
                          "avg": {"field": "events.event_data.price_impact"}
                        },
                        "tx_count": {
                          "value_count": {"field": "events.event_data.pool_id"}
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
```

**Post-processing**: Use z-score anomaly detection (z > 3.0) to identify volume spikes.

---

## Alert Summary Table

| Pattern | Method | Key Indicators | Confidence |
|---------|--------|----------------|------------|
| **Self Wash Trading** | Direction balance + CV | Both directions, CV<25%, single pool>60%, <60min | HIGH |
| **Coordinated Wash** | Time buckets + Direction balance | 2-10 senders, balanced dirs, <5min | HIGH |
| **Statistical Anomaly** | Benford's Law | Chi-square p<0.05 | MEDIUM |
| **Peel Chain** | Graph + Amount decay | 4+ hops, 5-30% decay each, <10min | HIGH |
| **Layering** | Multi-pool + Volume | 3+ pools, >10B volume, <2hr | MEDIUM |
| **Sandwich Attack** | Pattern matching | Same attacker front+back run, <30s | HIGH |
| **Volume Pump** | Z-score anomaly | z>3.0 hourly volume | MEDIUM |

---

## Implementation Notes

### Elasticsearch Query Syntax

**Important corrections:**
- Use `modules` (not `modules.keyword`) - field type is already `keyword`
- Use `functions` (not `functions.keyword`) - field type is already `keyword`
- Use `events.event_data.pool_id` (not `events.event_data.pool_id.keyword`)
- Always use `nested` query when filtering on `events.*` fields
- Use `reverse_nested` to go back from nested to parent level in aggregations

### Example: Query transactions with specific pool_id

```json
POST sui-transactions/_search
{
  "query": {
    "nested": {
      "path": "events",
      "query": {
        "term": {
          "events.event_data.pool_id": "0x..."
        }
      }
    }
  }
}
```

### Post-processing Requirements

Many detection algorithms require post-processing Python code:
- **Peel Chain Detection**: Graph algorithms (NetworkX)
- **Sandwich Attack**: Pattern matching with time windows
- **Benford's Law**: Statistical tests (scipy.stats)
- **Z-score Anomaly**: NumPy statistical functions

See `detect_money_laundering.py` for complete implementations.

### Performance Considerations

- Nested aggregations have high performance cost
- Graph analysis (SCCs, paths) must be done post-processing
- For real-time detection, consider streaming solution (Kafka, Flink)

### Recommended Architecture

```
[Sui Indexer] → [Kafka] → [Flink/Spark Streaming] → [ES Index]
                              ↓
                    [ML Models: GNN, LSTM]
                              ↓
                    [Alert System] → [Dashboard]
```

### ML Enhancement Opportunities

1. **Graph Neural Networks (GNN)**: Detect complex wash trading patterns
2. **LSTM/Transformer**: Time-series anomaly detection
3. **Clustering**: Identify address groups (DBSCAN, HDBSCAN)
4. **Node2Vec/DeepWalk**: Address embedding for similarity detection

---

## Usage

Run detection script:
```bash
python3 detect_money_laundering.py
```

Results saved to: `ml_detection_results.json`
