# Hướng dẫn sử dụng Queries trong Kibana

## Cách 1: Kibana Dev Tools (Khuyến nghị)

1. Mở Kibana → Click **Dev Tools** (icon búa ở sidebar trái)
2. Trong Console, dán query dưới đây
3. Nhấn **Ctrl+Enter** (hoặc click nút Run) để chạy

**Lưu ý:** Trong Kibana Dev Tools, bạn chỉ cần dán phần JSON, không cần `curl` command.

---

## 1. WASH TRADING DETECTION

### Query cơ bản (có behavior_tag):

```json
GET sui-transactions/_search
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
```

### Query nâng cao (không cần tag):

```json
GET sui-transactions/_search
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
        "trade_frequency": {
          "value_count": {"field": "tx_digest"}
        },
        "time_window": {
          "stats": {"field": "timestamp_ms"}
        }
      }
    }
  }
}
```

---

## 2. MONEY LAUNDERING DETECTION

```json
GET sui-transactions/_search
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
```

### Detect Structuring:

```json
GET sui-transactions/_search
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
    }
  }
}
```

---

## 3. CIRCULAR FLOW DETECTION

```json
GET sui-transactions/_search
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
        }
      }
    }
  }
}
```

---

## 4. HIGH FREQUENCY MANIPULATION

```json
GET sui-transactions/_search
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
```

---

## 5. COORDINATED ATTACK DETECTION

```json
GET sui-transactions/_search
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

---

## 6. TIME-SERIES ANALYSIS

### 30-Minute Window Suspicious Activity:

```json
GET sui-transactions/_search
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
        }
      }
    }
  }
}
```

### Address Reputation Score:

```json
GET sui-transactions/_search
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
        "unique_related": {
          "cardinality": {"field": "related_address"}
        }
      }
    }
  }
}
```

---

## 7. QUERIES ĐƠN GIẢN (Không có behavior_tag)

### Tìm tất cả transactions có behavior_tag:

```json
GET sui-transactions/_search
{
  "size": 20,
  "query": {
    "exists": {"field": "behavior_tag"}
  }
}
```

### Phân bố theo behavior_tag:

```json
GET sui-transactions/_search
{
  "size": 0,
  "aggs": {
    "by_behavior": {
      "terms": {
        "field": "behavior_tag",
        "size": 20
      }
    }
  }
}
```

### Tìm transactions theo sender:

```json
GET sui-transactions/_search
{
  "size": 20,
  "query": {
    "term": {"sender": "0x000000000000000000000000000000000000bb07"}
  }
}
```

### Tìm transactions trong khoảng thời gian:

```json
GET sui-transactions/_search
{
  "size": 20,
  "query": {
    "range": {
      "timestamp_ms": {
        "gte": "now-1h",
        "lte": "now"
      }
    }
  },
  "sort": [{"timestamp_ms": "desc"}]
}
```

---

## Cách 2: Kibana Discover

1. Mở **Discover** (icon compass ở sidebar)
2. Chọn index pattern: `sui-transactions*`
3. Sử dụng KQL (Kibana Query Language) hoặc Lucene syntax

### Ví dụ KQL queries:

```
behavior_tag: wash_trading
sender: "0x000000000000000000000000000000000000bb07"
timestamp_ms >= now-30m
behavior_tag: (wash_trading OR money_laundering)
```

---

## Cách 3: Tạo Visualizations

1. Mở **Visualize** → **Create visualization**
2. Chọn loại chart (Bar, Pie, Line, etc.)
3. Chọn index: `sui-transactions*`
4. Cấu hình:
   - **Metrics**: Count, Sum, Avg, etc.
   - **Buckets**: Terms (behavior_tag, sender), Date Histogram (timestamp_ms), etc.

### Ví dụ: Pie chart phân bố behavior_tag

- **Metric**: Count
- **Bucket**: Terms aggregation
  - Field: `behavior_tag`
  - Size: 10

---

## Tips

1. **Dev Tools** là cách tốt nhất để test queries phức tạp
2. **Discover** tốt cho tìm kiếm và filter nhanh
3. **Visualize** để tạo dashboards
4. Luôn kiểm tra field names trong index mapping trước khi query
5. Sử dụng `GET sui-transactions/_mapping` để xem cấu trúc fields

