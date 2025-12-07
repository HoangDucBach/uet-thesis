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
    "event_type": "keyword",
    "event_data": {
      "pool_id": "keyword",
      "amount_in": "long",
      "amount_out": "long",
      "token_in_type": "keyword",
      "token_out_type": "keyword",
      "price_impact": "long"
    }
  }]
}
```

---

## 1. Wash Trading Detection

### Theory (Victor & Weintraud, WWW '21)

Wash trading forms **closed cycles** in transaction graphs where net position change = 0.
Detection via Strongly Connected Components (SCCs) in directed token trade graphs.

### Detection Approach: Multi-layer

#### 1.1 Self-Trade Detection (Same Sender, Opposite Directions)

```json
GET sui-transactions/_search
{
  "size": 0,
  "query": {"term": {"modules.keyword": "simple_dex"}},
  "aggs": {
    "by_sender": {
      "terms": {"field": "sender", "size": 100, "min_doc_count": 5},
      "aggs": {
        "directions": {
          "terms": {"field": "functions.keyword"}
        },
        "time_range": {"stats": {"field": "timestamp_ms"}},
        "events": {
          "nested": {"path": "events"},
          "aggs": {
            "pools": {"terms": {"field": "events.event_data.pool_id.keyword", "size": 5}},
            "amount_stats": {"extended_stats": {"field": "events.event_data.amount_in"}}
          }
        }
      }
    }
  }
}
```

**Alert Criteria:**

- Both `swap_a_to_b` AND `swap_b_to_a` present
- |count(a_to_b) - count(b_to_a)| / total < 0.2 (balanced directions)
- Single pool concentration > 80%
- Time span < 30 minutes
- Amount CV < 15% (uniform amounts)

#### 1.2 Coordinated Wash Trading (Multiple Addresses)

```json
GET sui-transactions/_search
{
  "size": 0,
  "query": {"term": {"modules.keyword": "simple_dex"}},
  "aggs": {
    "by_pool": {
      "nested": {"path": "events"},
      "aggs": {
        "pools": {
          "terms": {"field": "events.event_data.pool_id.keyword", "size": 20},
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
                    "unique_senders": {"cardinality": {"field": "sender"}},
                    "direction_balance": {
                      "filters": {
                        "filters": {
                          "a_to_b": {"term": {"functions.keyword": "swap_a_to_b"}},
                          "b_to_a": {"term": {"functions.keyword": "swap_b_to_a"}}
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
- Near-equal a_to_b and b_to_a counts
- Sequential timing pattern (tx1.a_to_b → tx2.b_to_a → tx3.a_to_b...)

#### 1.3 Statistical Anomaly Detection (Benford's Law)

Post-processing Python:

```python
import numpy as np
from scipy.stats import chisquare

def benford_expected():
    """Expected first digit distribution per Benford's Law"""
    return np.array([np.log10(1 + 1/d) for d in range(1, 10)])

def extract_first_digit(amount):
    """Extract first significant digit"""
    s = str(abs(int(amount)))
    return int(s[0]) if s[0] != '0' else None

def detect_benford_anomaly(amounts, threshold=0.05):
    """
    Detect wash trading via Benford's Law violation
    Returns: (is_anomaly, chi2_pvalue, observed_dist, expected_dist)
    """
    first_digits = [extract_first_digit(a) for a in amounts if a > 0]
    first_digits = [d for d in first_digits if d is not None]
    
    if len(first_digits) < 30:
        return False, 1.0, None, None
    
    observed = np.zeros(9)
    for d in first_digits:
        if 1 <= d <= 9:
            observed[d-1] += 1
    observed = observed / observed.sum()
    
    expected = benford_expected()
    _, pvalue = chisquare(observed * len(first_digits), 
                          expected * len(first_digits))
    
    return pvalue < threshold, pvalue, observed, expected

def detect_size_clustering(amounts, round_numbers=[1000, 5000, 10000]):
    """
    Detect abnormal clustering around round numbers
    Cong et al. (2023): Legitimate trading shows natural size distribution
    """
    amounts = np.array(amounts)
    cluster_count = 0
    
    for rn in round_numbers:
        # Count amounts within 1% of round number
        within_range = np.sum(np.abs(amounts - rn * 1e6) / (rn * 1e6) < 0.01)
        cluster_count += within_range
    
    cluster_ratio = cluster_count / len(amounts)
    # Anomaly if >15% of trades at round numbers
    return cluster_ratio > 0.15, cluster_ratio
```

---

## 2. Money Laundering Detection

### Theory (Chainalysis, Elliptic Research)

Real crypto laundering uses:

1. **Peel Chains**: Large amount → split into decreasing smaller amounts
2. **Chain Hopping**: Cross-chain bridges to different blockchains
3. **Mixers/Tumblers**: Pool funds to break traceability
4. **Layering via DEX**: Multiple swaps to obfuscate origin

### 2.1 Peel Chain Detection

**Pattern**: Amount decreases at each hop (not constant like simple chain)

```json
GET sui-transactions/_search
{
  "size": 1000,
  "sort": [{"timestamp_ms": "asc"}],
  "_source": ["sender", "timestamp_ms", "tx_digest", 
              "events.event_data.amount_in", "events.event_data.amount_out",
              "events.event_data.pool_id"],
  "query": {
    "bool": {
      "must": [
        {"term": {"modules.keyword": "simple_dex"}},
        {"range": {"timestamp_ms": {"gte": "now-6h"}}}
      ]
    }
  }
}
```

#### Post-processing: Peel Chain Detection

```python
import networkx as nx
from collections import defaultdict
from datetime import datetime, timedelta

def detect_peel_chains(es_hits, 
                       amount_decay_min=0.05,  # Min 5% decrease per hop
                       amount_decay_max=0.30,  # Max 30% decrease per hop
                       max_time_delta_min=10,  # Max 10 min between hops
                       min_chain_length=4):
    """
    Detect peel chain patterns where amounts decrease at each hop.
    
    Real peel chains (Chainalysis):
    - Large initial amount split into smaller pieces
    - Each hop "peels off" a portion (5-30% typically)
    - Remaining funds continue to next address
    """
    
    G = nx.DiGraph()
    txs = sorted(es_hits, key=lambda x: x['_source']['timestamp_ms'])
    
    # Build graph with amount decay edges
    for i, tx in enumerate(txs):
        src = tx['_source']
        sender = src['sender']
        amount_out = src['events'][0]['event_data']['amount_out']
        tx_time = datetime.fromisoformat(src['timestamp_ms'].replace('Z', '+00:00'))
        
        # Look for next tx with decreased amount (peel pattern)
        for next_tx in txs[i+1:i+50]:  # Search window
            next_src = next_tx['_source']
            next_sender = next_src['sender']
            
            if next_sender == sender:
                continue  # Skip same sender
                
            next_amount_in = next_src['events'][0]['event_data']['amount_in']
            next_time = datetime.fromisoformat(
                next_src['timestamp_ms'].replace('Z', '+00:00'))
            
            time_delta = (next_time - tx_time).total_seconds() / 60
            
            if time_delta > max_time_delta_min:
                break  # Outside time window
            
            # Check for peel pattern: amount decreased but not too much
            if next_amount_in < amount_out:
                decay_ratio = (amount_out - next_amount_in) / amount_out
                
                if amount_decay_min <= decay_ratio <= amount_decay_max:
                    G.add_edge(sender, next_sender, 
                              amount_in=amount_out,
                              amount_out=next_amount_in,
                              decay=decay_ratio,
                              time_delta=time_delta,
                              tx_digest=src['tx_digest'])
                    break  # Found the peel, move to next tx
    
    # Find chains (paths with length >= min_chain_length)
    chains = []
    for source in G.nodes():
        if G.in_degree(source) == 0:  # Start of potential chain
            for target in G.nodes():
                if G.out_degree(target) == 0:  # End of potential chain
                    try:
                        paths = list(nx.all_simple_paths(
                            G, source, target, cutoff=10))
                        for path in paths:
                            if len(path) >= min_chain_length:
                                # Calculate chain metrics
                                total_decay = 1.0
                                for j in range(len(path)-1):
                                    edge = G[path[j]][path[j+1]]
                                    total_decay *= (1 - edge['decay'])
                                
                                chains.append({
                                    'addresses': path,
                                    'length': len(path),
                                    'total_decay': 1 - total_decay,
                                    'confidence': 'HIGH' if len(path) >= 5 else 'MEDIUM'
                                })
                    except nx.NetworkXNoPath:
                        continue
    
    return chains
```

### 2.2 Layering Detection (Multiple Swaps to Obfuscate)

```json
GET sui-transactions/_search
{
  "size": 0,
  "query": {"term": {"modules.keyword": "simple_dex"}},
  "aggs": {
    "by_sender": {
      "terms": {"field": "sender", "size": 100, "min_doc_count": 3},
      "aggs": {
        "time_range": {"stats": {"field": "timestamp_ms"}},
        "unique_pools": {
          "nested": {"path": "events"},
          "aggs": {
            "pool_count": {
              "cardinality": {"field": "events.event_data.pool_id.keyword"}
            }
          }
        },
        "total_volume": {
          "nested": {"path": "events"},
          "aggs": {
            "sum": {"sum": {"field": "events.event_data.amount_in"}}
          }
        }
      }
    }
  }
}
```

**Alert Criteria:**

- Single address using 3+ different pools
- High volume (>50B) in short time (<1 hour)
- Pattern: Token A → B → C → D (multi-hop conversion)

---

## 3. Flash Loan Attack Detection

### Theory (Xia et al., ICDCS '23)

Flash loan attacks borrow large amounts, manipulate prices, profit, repay in single tx.

**Three attack patterns identified:**

1. Price manipulation via large swaps
2. Oracle manipulation
3. Governance manipulation

### 3.1 Large Swap Detection (Potential Price Manipulation)

```json
GET sui-transactions/_search
{
  "size": 0,
  "query": {"term": {"modules.keyword": "simple_dex"}},
  "aggs": {
    "large_swaps": {
      "nested": {"path": "events"},
      "aggs": {
        "high_volume": {
          "filter": {
            "range": {"events.event_data.amount_in": {"gte": 50000000000}}
          },
          "aggs": {
            "by_pool": {
              "terms": {"field": "events.event_data.pool_id.keyword"},
              "aggs": {
                "impact_stats": {
                  "extended_stats": {"field": "events.event_data.price_impact"}
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

```python
def detect_sandwich_attacks(es_hits, 
                            time_window_sec=30,
                            min_profit_ratio=0.01):
    """
    Detect sandwich attack pattern:
    1. Attacker: swap_a_to_b (front-run, push price up)
    2. Victim: swap_a_to_b (gets worse price)
    3. Attacker: swap_b_to_a (back-run, profit from price difference)
    """
    
    txs = sorted(es_hits, key=lambda x: x['_source']['timestamp_ms'])
    sandwiches = []
    
    for i, tx1 in enumerate(txs[:-2]):
        src1 = tx1['_source']
        
        # Look for pattern within time window
        for j in range(i+1, min(i+10, len(txs)-1)):
            tx2 = txs[j]
            src2 = tx2['_source']
            
            for k in range(j+1, min(j+10, len(txs))):
                tx3 = txs[k]
                src3 = tx3['_source']
                
                # Check time constraint
                t1 = datetime.fromisoformat(src1['timestamp_ms'].replace('Z', '+00:00'))
                t3 = datetime.fromisoformat(src3['timestamp_ms'].replace('Z', '+00:00'))
                
                if (t3 - t1).total_seconds() > time_window_sec:
                    break
                
                # Check sandwich pattern
                if (src1['sender'] == src3['sender'] and  # Same attacker
                    src1['sender'] != src2['sender'] and  # Different victim
                    src1['functions'][0] == 'swap_a_to_b' and
                    src2['functions'][0] == 'swap_a_to_b' and
                    src3['functions'][0] == 'swap_b_to_a'):
                    
                    # Same pool
                    pool1 = src1['events'][0]['event_data']['pool_id']
                    pool2 = src2['events'][0]['event_data']['pool_id']
                    pool3 = src3['events'][0]['event_data']['pool_id']
                    
                    if pool1 == pool2 == pool3:
                        # Calculate profit
                        attacker_in = src1['events'][0]['event_data']['amount_in']
                        attacker_out = src3['events'][0]['event_data']['amount_out']
                        profit = attacker_out - attacker_in
                        
                        if profit > 0:
                            sandwiches.append({
                                'attacker': src1['sender'],
                                'victim': src2['sender'],
                                'pool': pool1,
                                'profit': profit,
                                'profit_ratio': profit / attacker_in,
                                'front_tx': src1['tx_digest'],
                                'victim_tx': src2['tx_digest'],
                                'back_tx': src3['tx_digest'],
                                'confidence': 'HIGH'
                            })
    
    return sandwiches
```

---

## 4. Coordinated Market Manipulation

### 4.1 Pump Detection (Volume Spike + Price Impact)

```json
GET sui-transactions/_search
{
  "size": 0,
  "query": {"term": {"modules.keyword": "simple_dex"}},
  "aggs": {
    "by_pool": {
      "nested": {"path": "events"},
      "aggs": {
        "pools": {
          "terms": {"field": "events.event_data.pool_id.keyword", "size": 20},
          "aggs": {
            "hourly_volume": {
              "date_histogram": {
                "field": "timestamp_ms",
                "fixed_interval": "1h"
              },
              "aggs": {
                "volume": {"sum": {"field": "events.event_data.amount_in"}},
                "avg_impact": {"avg": {"field": "events.event_data.price_impact"}},
                "tx_count": {"value_count": {"field": "events.event_data.pool_id.keyword"}}
              }
            }
          }
        }
      }
    }
  }
}
```

#### Post-processing: Anomaly Detection

```python
import numpy as np
from scipy import stats

def detect_volume_anomalies(hourly_buckets, z_threshold=3.0):
    """
    Detect abnormal volume spikes that may indicate pump activity.
    Uses z-score to identify statistical outliers.
    """
    volumes = [b['volume']['value'] for b in hourly_buckets if b['volume']['value'] > 0]
    
    if len(volumes) < 10:
        return []
    
    mean_vol = np.mean(volumes)
    std_vol = np.std(volumes)
    
    anomalies = []
    for bucket in hourly_buckets:
        vol = bucket['volume']['value']
        if std_vol > 0:
            z_score = (vol - mean_vol) / std_vol
            if z_score > z_threshold:
                anomalies.append({
                    'timestamp': bucket['key_as_string'],
                    'volume': vol,
                    'z_score': z_score,
                    'tx_count': bucket['tx_count']['value'],
                    'avg_price_impact': bucket['avg_impact']['value'],
                    'confidence': 'HIGH' if z_score > 4.0 else 'MEDIUM'
                })
    
    return anomalies
```

### 4.2 Coordinated Address Detection

```python
def detect_coordinated_addresses(es_response, 
                                 time_window_min=10,
                                 min_addresses=3):
    """
    Detect groups of addresses acting in coordination.
    
    Signals:
    - Multiple addresses trading same pool in tight time window
    - Similar amounts across addresses
    - Sequential or parallel execution
    """
    from collections import defaultdict
    from itertools import combinations
    
    pool_activity = defaultdict(list)
    
    for hit in es_response['hits']['hits']:
        src = hit['_source']
        pool_id = src['events'][0]['event_data']['pool_id']
        pool_activity[pool_id].append({
            'sender': src['sender'],
            'timestamp': src['timestamp_ms'],
            'amount': src['events'][0]['event_data']['amount_in'],
            'direction': src['functions'][0]
        })
    
    coordinated_groups = []
    
    for pool_id, activities in pool_activity.items():
        # Sort by time
        activities = sorted(activities, key=lambda x: x['timestamp'])
        
        # Sliding window analysis
        for i, act in enumerate(activities):
            window_acts = [act]
            t_start = datetime.fromisoformat(act['timestamp'].replace('Z', '+00:00'))
            
            for j in range(i+1, len(activities)):
                t_j = datetime.fromisoformat(
                    activities[j]['timestamp'].replace('Z', '+00:00'))
                if (t_j - t_start).total_seconds() / 60 <= time_window_min:
                    window_acts.append(activities[j])
                else:
                    break
            
            # Check for coordination
            unique_senders = set(a['sender'] for a in window_acts)
            if len(unique_senders) >= min_addresses:
                amounts = [a['amount'] for a in window_acts]
                amount_cv = np.std(amounts) / np.mean(amounts) if np.mean(amounts) > 0 else 1
                
                coordinated_groups.append({
                    'pool': pool_id,
                    'addresses': list(unique_senders),
                    'address_count': len(unique_senders),
                    'tx_count': len(window_acts),
                    'time_window_start': act['timestamp'],
                    'amount_cv': amount_cv,
                    'confidence': 'HIGH' if amount_cv < 0.2 else 'MEDIUM'
                })
    
    return coordinated_groups
```

---

## 5. Rug Pull / Exit Scam Detection

### 5.1 Liquidity Drain Detection

```json
GET sui-transactions/_search
{
  "size": 0,
  "query": {"term": {"modules.keyword": "simple_dex"}},
  "aggs": {
    "by_pool": {
      "nested": {"path": "events"},
      "aggs": {
        "pools": {
          "terms": {"field": "events.event_data.pool_id.keyword"},
          "aggs": {
            "net_flow": {
              "date_histogram": {
                "field": "timestamp_ms",
                "fixed_interval": "1h"
              },
              "aggs": {
                "inflow": {"sum": {"field": "events.event_data.amount_in"}},
                "outflow": {"sum": {"field": "events.event_data.amount_out"}}
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

- Large single withdrawal (>30% of pool liquidity)
- Preceded by promotional activity (many small deposits)
- Creator address draining funds

---

## Alert Summary Table

| Pattern | Method | Key Indicators | Confidence |
|---------|--------|----------------|------------|
| **Self Wash Trading** | Direction balance + CV | Both directions, CV<15%, single pool | HIGH |
| **Coordinated Wash** | SCC + Time buckets | 2-10 senders, balanced dirs, <5min | HIGH |
| **Statistical Anomaly** | Benford's Law | Chi-square p<0.05 | MEDIUM |
| **Peel Chain** | Graph + Amount decay | 4+ hops, 5-30% decay each | HIGH |
| **Layering** | Multi-pool + Volume | 3+ pools, high volume, <1hr | MEDIUM |
| **Sandwich Attack** | Pattern matching | Same attacker front+back run | HIGH |
| **Volume Pump** | Z-score anomaly | z>3.0 hourly volume | MEDIUM |
| **Coordinated Group** | Time window cluster | 3+ addresses, <10min, similar amounts | MEDIUM |
| **Rug Pull** | Net flow analysis | >30% liquidity drain | HIGH |

---

## Implementation Notes

### ES Limitations

- Nested aggregations có performance cost cao
- Graph analysis (SCCs, paths) phải làm post-processing
- Real-time detection cần streaming solution (Kafka, Flink)

### Recommended Architecture

```text
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
