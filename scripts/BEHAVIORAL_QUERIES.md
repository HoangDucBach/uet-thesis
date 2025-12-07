# 🔍 Behavioral Pattern Detection Queries for ELK

## Focus: Time-series Analysis & Long-term Suspicious Activity

Thay vì real-time detection, focus vào phát hiện patterns qua thời gian:
- Wash trading trong 30 phút
- Money laundering chains qua nhiều hops
- Circular fund flows
- High frequency manipulation
- Coordinated attacks

---

## 1. WASH TRADING DETECTION

### Query: Detect Wash Trading (2 addresses trading back & forth)

**Pattern:** Cùng 2 addresses, giao dịch qua lại nhiều lần trong 30 phút, amounts tương tự

```bash
curl -X GET "localhost:9200/sui-transactions/_search" -H 'Content-Type: application/json' -d'
{
  "size": 0,
  "query": {
    "bool": {
      "must": [
        {"term": {"behavior_tag": "wash_trading"}},
        {
          "range": {
            "timestamp_ms": {
              "gte": "now-30m",
              "lte": "now"
            }
          }
        }
      ]
    }
  },
  "aggs": {
    "wash_pairs": {
      "terms": {
        "field": "wash_trading_pair",
        "size": 50
      },
      "aggs": {
        "trade_count": {"value_count": {"field": "tx_digest"}},
        "time_span": {
          "stats": {"field": "timestamp_ms"}
        },
        "total_volume": {
          "nested": {
            "path": "events"
          },
          "aggs": {
            "sum_amounts": {
              "sum": {"field": "events.amount_in"}
            }
          }
        }
      }
    }
  }
}
'
```

**Advanced: Detect wash trading pattern without tag**

```bash
curl -X GET "localhost:9200/sui-transactions/_search" -H 'Content-Type: application/json' -d'
{
  "size": 0,
  "query": {
    "range": {
      "timestamp_ms": {"gte": "now-1h", "lte": "now"}
    }
  },
  "aggs": {
    "by_sender": {
      "terms": {
        "field": "sender",
        "size": 100
      },
      "aggs": {
        "back_and_forth": {
          "filter": {
            "script": {
              "script": {
                "source": """
                  // Detect if same sender has opposite direction trades
                  def events = params._source.events;
                  def directions = new HashSet();
                  for (event in events) {
                    if (event.type == 'SwapExecuted') {
                      directions.add(event.token_in);
                    }
                  }
                  return directions.size() > 1;
                """
              }
            }
          }
        },
        "trade_frequency": {
          "value_count": {"field": "tx_digest"}
        }
      }
    }
  }
}
'
```

### Kibana Visualization: Wash Trading Heatmap

**Type:** Heatmap

**Metrics:**
- Count of transactions

**Buckets:**
- X-axis: Terms `sender`
- Y-axis: Terms `related_address`

**Filters:**
- Time range: Last 30 minutes
- Minimum doc count: 10

**Alert Threshold:** > 10 trades between same 2 addresses in 30min

---

## 2. MONEY LAUNDERING DETECTION

### Query: Find Laundering Chains (multi-hop transfers)

**Pattern:** Fund di chuyển qua 5-10 addresses khác nhau, structuring (break into small amounts)

```bash
curl -X GET "localhost:9200/sui-transactions/_search" -H 'Content-Type: application/json' -d'
{
  "size": 1000,
  "query": {
    "term": {"behavior_tag": "money_laundering"}
  },
  "sort": [
    {"chain_id": "asc"},
    {"laundering_hop": "asc"}
  ],
  "aggs": {
    "by_chain": {
      "terms": {
        "field": "chain_id",
        "size": 50
      },
      "aggs": {
        "chain_length": {
          "max": {"field": "laundering_hop"}
        },
        "has_structuring": {
          "filter": {
            "term": {"structuring": true}
          }
        },
        "time_span": {
          "stats": {"field": "timestamp_ms"}
        },
        "unique_addresses": {
          "cardinality": {"field": "sender"}
        }
      }
    }
  }
}
'
```

### Query: Detect Structuring (breaking large amounts into small chunks)

**Pattern:** Nhiều transactions nhỏ từ cùng address, tổng lớn, trong thời gian ngắn

```bash
curl -X GET "localhost:9200/sui-transactions/_search" -H 'Content-Type: application/json' -d'
{
  "size": 0,
  "query": {
    "range": {
      "timestamp_ms": {"gte": "now-1h"}
    }
  },
  "aggs": {
    "by_sender": {
      "terms": {
        "field": "sender",
        "size": 100
      },
      "aggs": {
        "tx_count": {
          "value_count": {"field": "tx_digest"}
        },
        "total_volume": {
          "nested": {"path": "events"},
          "aggs": {
            "sum": {"sum": {"field": "events.amount_in"}}
          }
        },
        "avg_amount": {
          "nested": {"path": "events"},
          "aggs": {
            "avg": {"avg": {"field": "events.amount_in"}}
          }
        },
        "time_window": {
          "stats": {"field": "timestamp_ms"}
        }
      }
    },
    "structuring_filter": {
      "bucket_selector": {
        "buckets_path": {
          "txCount": "tx_count",
          "totalVol": "total_volume>sum"
        },
        "script": "params.txCount > 5 && params.totalVol > 50000000000"
      }
    }
  }
}
'
```

### Kibana Visualization: Laundering Chain Flow

**Type:** Sankey Diagram (hoặc Network Graph nếu có plugin)

**Data:**
- Source: `sender`
- Target: `related_address`
- Weight: `events.amount_in`

**Filter:**
- `behavior_tag: money_laundering`
- Time range: Last 1 hour

**Risk Indicators:**
- Chain length > 5 hops
- Has structuring
- Total time < 30 minutes
- Amount > 100M

---

## 3. CIRCULAR FUND FLOW DETECTION

### Query: Detect Circular Flows (A → B → C → A)

**Pattern:** Tiền quay vòng về address ban đầu qua nhiều hops

```bash
curl -X GET "localhost:9200/sui-transactions/_search" -H 'Content-Type: application/json' -d'
{
  "size": 1000,
  "query": {
    "term": {"behavior_tag": "circular_flow"}
  },
  "sort": [
    {"circle_id": "asc"},
    {"hop_in_circle": "asc"}
  ],
  "aggs": {
    "by_circle": {
      "terms": {
        "field": "circle_id",
        "size": 50
      },
      "aggs": {
        "num_hops": {
          "max": {"field": "hop_in_circle"}
        },
        "time_to_complete": {
          "stats": {"field": "timestamp_ms"}
        },
        "return_ratio": {
          "bucket_script": {
            "buckets_path": {
              "final": "final_return_amount",
              "initial": "initial_amount"
            },
            "script": "params.final / params.initial"
          }
        }
      }
    }
  }
}
'
```

### Advanced: Detect Circular Pattern Without Tag

```bash
curl -X GET "localhost:9200/sui-transactions/_search" -H 'Content-Type: application/json' -d'
{
  "size": 0,
  "query": {
    "range": {
      "timestamp_ms": {"gte": "now-30m"}
    }
  },
  "aggs": {
    "by_sender": {
      "terms": {
        "field": "sender",
        "size": 100
      },
      "aggs": {
        "related_addresses": {
          "terms": {
            "field": "related_address",
            "size": 20
          }
        },
        "check_circular": {
          "bucket_selector": {
            "buckets_path": {
              "relatedCount": "related_addresses._bucket_count"
            },
            "script": "params.relatedCount >= 3"
          }
        }
      }
    }
  }
}
'
```

### Kibana Alert: Circular Flow Detected

**Condition:**
- Same sender appears as both source and final destination
- Through 3+ intermediaries
- Within 30 minutes
- Amount loss < 5% (indicating intentional flow, not trades)

---

## 4. HIGH FREQUENCY MANIPULATION

### Query: Detect HFT Bursts (20+ txs in 3 minutes)

**Pattern:** Burst of nhiều giao dịch liên tục từ cùng address

```bash
curl -X GET "localhost:9200/sui-transactions/_search" -H 'Content-Type: application/json' -d'
{
  "size": 0,
  "query": {
    "range": {
      "timestamp_ms": {"gte": "now-5m", "lte": "now"}
    }
  },
  "aggs": {
    "by_sender": {
      "terms": {
        "field": "sender",
        "size": 50,
        "min_doc_count": 15
      },
      "aggs": {
        "time_range": {
          "stats": {"field": "timestamp_ms"}
        },
        "frequency_score": {
          "bucket_script": {
            "buckets_path": {
              "count": "_count",
              "timeSpan": "time_range.max - time_range.min"
            },
            "script": "params.count / (params.timeSpan / 60000.0)"
          }
        },
        "by_pool": {
          "nested": {"path": "events"},
          "aggs": {
            "pools": {
              "terms": {"field": "events.pool_id"}
            }
          }
        }
      }
    }
  }
}
'
```

### Query: Calculate HFT Frequency Metrics

```bash
curl -X GET "localhost:9200/sui-transactions/_search" -H 'Content-Type: application/json' -d'
{
  "size": 0,
  "query": {
    "bool": {
      "must": [
        {"term": {"behavior_tag": "hft_manipulation"}},
        {"range": {"timestamp_ms": {"gte": "now-10m"}}}
      ]
    }
  },
  "aggs": {
    "by_burst": {
      "terms": {
        "field": "burst_id",
        "size": 50
      },
      "aggs": {
        "trades_per_minute": {
          "bucket_script": {
            "buckets_path": {
              "count": "_count",
              "span": "time_stats.max - time_stats.min"
            },
            "script": "params.count / (params.span / 60000.0)"
          }
        },
        "time_stats": {
          "stats": {"field": "timestamp_ms"}
        },
        "avg_trade_size": {
          "nested": {"path": "events"},
          "aggs": {
            "avg": {"avg": {"field": "events.amount_in"}}
          }
        }
      }
    }
  }
}
'
```

### Kibana Dashboard: HFT Activity Monitor

**Panel 1:** Transaction Rate Over Time
- Line chart: Count per 10-second interval
- Group by: sender
- Alert if > 10 txs/minute

**Panel 2:** Top HFT Addresses
- Bar chart: Transaction count
- Time range: Last 10 minutes
- Min count: 15

**Panel 3:** HFT Pool Targeting
- Pie chart: Distribution of pools
- Filter: HFT addresses only

---

## 5. COORDINATED ATTACK DETECTION

### Query: Find Coordinated Attacks (Multiple addresses, same time, same pool)

**Pattern:** Nhiều addresses khác nhau cùng trade vào 1 pool trong khoảng thời gian ngắn

```bash
curl -X GET "localhost:9200/sui-transactions/_search" -H 'Content-Type: application/json' -d'
{
  "size": 0,
  "query": {
    "range": {
      "timestamp_ms": {"gte": "now-15m"}
    }
  },
  "aggs": {
    "by_pool": {
      "nested": {"path": "events"},
      "aggs": {
        "pools": {
          "terms": {
            "field": "events.pool_id",
            "size": 20
          },
          "aggs": {
            "reverse_nested": {
              "reverse_nested": {},
              "aggs": {
                "unique_senders": {
                  "cardinality": {"field": "sender"}
                },
                "time_window": {
                  "stats": {"field": "timestamp_ms"}
                },
                "total_impact": {
                  "nested": {"path": "events"},
                  "aggs": {
                    "sum_impact": {
                      "sum": {"field": "events.price_impact"}
                    }
                  }
                }
              }
            }
          }
        }
      }
    },
    "coordinated_filter": {
      "bucket_selector": {
        "buckets_path": {
          "senders": "reverse_nested>unique_senders",
          "timeSpan": "reverse_nested>time_window.max - reverse_nested>time_window.min"
        },
        "script": "params.senders >= 4 && params.timeSpan < 600000"
      }
    }
  }
}
'
```

### Query: Correlation Analysis Between Addresses

```bash
curl -X GET "localhost:9200/sui-transactions/_search" -H 'Content-Type: application/json' -d'
{
  "size": 0,
  "query": {
    "term": {"behavior_tag": "coordinated_attack"}
  },
  "aggs": {
    "by_attack": {
      "terms": {
        "field": "attack_id",
        "size": 50
      },
      "aggs": {
        "attackers": {
          "terms": {
            "field": "sender",
            "size": 20
          }
        },
        "attack_metrics": {
          "stats_bucket": {
            "buckets_path": "attackers>_count"
          }
        },
        "total_volume": {
          "nested": {"path": "events"},
          "aggs": {
            "sum": {"sum": {"field": "events.amount_in"}}
          }
        },
        "combined_impact": {
          "nested": {"path": "events"},
          "aggs": {
            "max": {"max": {"field": "events.price_impact"}}
          }
        }
      }
    }
  }
}
'
```

---

## 6. TIME-SERIES ANALYSIS QUERIES

### Query: 30-Minute Window Suspicious Activity

```bash
curl -X GET "localhost:9200/sui-transactions/_search" -H 'Content-Type: application/json' -d'
{
  "size": 0,
  "query": {
    "range": {
      "timestamp_ms": {"gte": "now-30m"}
    }
  },
  "aggs": {
    "time_buckets": {
      "date_histogram": {
        "field": "timestamp_ms",
        "fixed_interval": "5m"
      },
      "aggs": {
        "behavior_breakdown": {
          "terms": {
            "field": "behavior_tag",
            "size": 10
          }
        },
        "suspicious_score": {
          "bucket_script": {
            "buckets_path": {
              "total": "_count",
              "normal": "behavior_breakdown[normal]>_count"
            },
            "script": "(params.total - params.normal) / params.total * 100"
          }
        }
      }
    }
  }
}
'
```

### Query: Address Reputation Score (based on 1-hour history)

```bash
curl -X GET "localhost:9200/sui-transactions/_search" -H 'Content-Type: application/json' -d'
{
  "size": 0,
  "query": {
    "range": {
      "timestamp_ms": {"gte": "now-1h"}
    }
  },
  "aggs": {
    "by_address": {
      "terms": {
        "field": "sender",
        "size": 100
      },
      "aggs": {
        "behavior_distribution": {
          "terms": {
            "field": "behavior_tag"
          }
        },
        "risk_score": {
          "bucket_script": {
            "buckets_path": {
              "total": "_count",
              "washTrading": "behavior_distribution[wash_trading]>_count",
              "laundering": "behavior_distribution[money_laundering]>_count",
              "hft": "behavior_distribution[hft_manipulation]>_count"
            },
            "script": """
              double score = 0;
              if (params.washTrading != null) score += params.washTrading * 3;
              if (params.laundering != null) score += params.laundering * 5;
              if (params.hft != null) score += params.hft * 2;
              return score / params.total * 100;
            """
          }
        },
        "unique_related": {
          "cardinality": {"field": "related_address"}
        }
      }
    }
  }
}
'
```

---

## 7. GRAPH ANALYSIS

### Query: Build Transaction Graph (Address Relationships)

```bash
curl -X GET "localhost:9200/sui-transactions/_search" -H 'Content-Type: application/json' -d'
{
  "size": 0,
  "query": {
    "range": {
      "timestamp_ms": {"gte": "now-1h"}
    }
  },
  "aggs": {
    "address_network": {
      "adjacency_matrix": {
        "filters": {
          "senders": {"terms": {"sender": [...]}},
          "receivers": {"terms": {"related_address": [...]}}
        }
      }
    },
    "relationship_strength": {
      "terms": {
        "script": {
          "source": "doc['sender'].value + '->' + doc['related_address'].value"
        },
        "size": 100
      },
      "aggs": {
        "frequency": {"value_count": {"field": "tx_digest"}},
        "total_value": {
          "nested": {"path": "events"},
          "aggs": {
            "sum": {"sum": {"field": "events.amount_in"}}
          }
        }
      }
    }
  }
}
'
```

---

## 8. ALERT RULES

### Rule 1: Wash Trading Alert
```
IF (
  Same 2 addresses
  AND > 10 trades in 30 minutes
  AND Similar amounts
  AND Low price impact (<1%)
) THEN Alert: WASH_TRADING
```

### Rule 2: Money Laundering Alert
```
IF (
  > 5 different addresses in sequence
  AND Within 40 minutes
  AND Has structuring (multiple small txs)
  AND Total amount > 100M
) THEN Alert: MONEY_LAUNDERING
```

### Rule 3: HFT Manipulation Alert
```
IF (
  > 20 transactions from same address
  AND Within 3 minutes
  AND Same pool
  AND Alternating directions
) THEN Alert: HFT_MANIPULATION
```

### Rule 4: Coordinated Attack Alert
```
IF (
  > 5 different addresses
  AND Same pool
  AND Within 10 minutes
  AND Combined price impact > 30%
) THEN Alert: COORDINATED_ATTACK
```

---

## 9. KIBANA DASHBOARDS

### Dashboard 1: Behavioral Overview
- Pie chart: Behavior distribution (30m window)
- Line chart: Suspicious activity trend
- Metric: Total risk score
- Table: Top risky addresses

### Dashboard 2: Money Laundering Monitor
- Sankey: Fund flow paths
- Heatmap: Address relationships
- Bar chart: Chain lengths
- Metric: Total laundered volume

### Dashboard 3: Market Manipulation
- Time series: HFT burst detection
- Network graph: Coordinated attackers
- Area chart: Price impact over time
- Alert feed: Real-time suspicious patterns

---

## 10. MACHINE LEARNING FEATURES

Extract features cho ML models:

```python
# Feature extraction for behavioral classification
features = {
    'tx_frequency_5m': count_in_window(5),
    'tx_frequency_30m': count_in_window(30),
    'unique_counterparties': cardinality('related_address'),
    'avg_amount': avg('events.amount_in'),
    'std_amount': std_dev('events.amount_in'),
    'back_forth_ratio': count_opposite_directions() / total,
    'time_regularity': std_dev('time_diff'),
    'pool_diversity': cardinality('events.pool_id'),
    'circular_path_score': detect_circular_path(),
    'structuring_score': detect_structuring()
}
```

---

**Focus:** Các queries này phát hiện **patterns qua thời gian**, không phải single transaction detection!
