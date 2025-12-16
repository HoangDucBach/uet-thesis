# Cách đọc và phân tích kết quả Query Wash Trading

## Cấu trúc kết quả từ Query 1.2

Khi chạy query aggregation, bạn sẽ nhận được kết quả như sau:

```json
{
  "took": 165,
  "hits": {
    "total": {"value": 1941},
    "hits": []
  },
  "aggregations": {
    "by_pool": {
      "doc_count": 1941,
      "pools": {
        "buckets": [
          {
            "key": "0xcd7c37355a73ace339b03847c860a43797a06cd675f051831562e39e2d4ba14e",
            "doc_count": 702,
            "reverse_nested": {
              "by_sender": {
                "buckets": [
                  {
                    "key": "0x000000000000000000000000000000000000bb07",
                    "doc_count": 50,
                    "tx_count": {"value": 50},
                    "avg_price_impact": {"value": 45.2},
                    "avg_amount": {"value": 10000000000},
                    "time_range": {
                      "min": 1765054331958,
                      "max": 1765054331958,
                      "avg": 1765054331958
                    }
                  },
                  {
                    "key": "0x000000000000000000000000000000000000bb08",
                    "doc_count": 48,
                    "tx_count": {"value": 48},
                    "avg_price_impact": {"value": 42.1},
                    "avg_amount": {"value": 9950000000},
                    "time_range": {
                      "min": 1765054332000,
                      "max": 1765054333000
                    }
                  }
                ]
              }
            }
          }
        ]
      }
    }
  }
}
```

## Cách đọc từng phần:

### 1. **Tổng quan (Top level)**
- `"took": 165` → Query mất 165ms để chạy
- `"hits.total.value": 1941` → Có 1941 transactions match query filter
- `"hits.hits": []` → Không trả về documents (vì `size: 0`)

### 2. **Aggregation: by_pool**
- `"doc_count": 1941` → Tổng số events trong tất cả pools
- `"pools.buckets"` → Danh sách các pools được group lại

### 3. **Mỗi Pool (bucket)**
```json
{
  "key": "0xcd7c37...",  // Pool ID
  "doc_count": 702,      // Số lượng events trong pool này
  "reverse_nested": {
    "by_sender": {
      "buckets": [...]   // Danh sách các addresses giao dịch trong pool này
    }
  }
}
```

### 4. **Mỗi Sender (trong pool)**
```json
{
  "key": "0x000000000000000000000000000000000000bb07",  // Địa chỉ
  "doc_count": 50,                                       // Số transactions
  "tx_count": {"value": 50},                             // Tổng số tx
  "avg_price_impact": {"value": 45.2},                   // Price impact trung bình (bps)
  "avg_amount": {"value": 10000000000},                  // Số tiền trung bình
  "time_range": {
    "min": 1765054331958,  // Thời gian giao dịch đầu tiên
    "max": 1765054331958,  // Thời gian giao dịch cuối cùng
    "avg": 1765054331958   // Thời gian trung bình
  }
}
```

## Phát hiện Wash Trading:

### Dấu hiệu Wash Trading:

1. **High Frequency (Tần suất cao)**
   - `tx_count >= 10` trong 30 phút
   - `doc_count >= 10` cho cùng một sender trong pool

2. **Low Price Impact (Tác động giá thấp)**
   - `avg_price_impact < 100` (nhỏ hơn 1%)
   - Nghĩa là giao dịch không làm thay đổi giá nhiều → có thể là fake volume

3. **Similar Amounts (Số tiền tương tự)**
   - So sánh `avg_amount` giữa các senders trong cùng pool
   - Nếu 2 addresses có `avg_amount` gần giống nhau → có thể đang trade qua lại

4. **Time Window (Cửa sổ thời gian)**
   - Tính `time_range.max - time_range.min`
   - Nếu < 30 phút (1800000ms) và có nhiều tx → suspicious

### Ví dụ phân tích:

**Scenario 1: Wash Trading Detected**
```
Pool: 0xcd7c37...
  Sender A: 50 txs, avg_price_impact: 45, avg_amount: 10M
  Sender B: 48 txs, avg_price_impact: 42, avg_amount: 9.95M
  Time window: 5 minutes
  
→ HIGH CONFIDENCE: Wash Trading
  - Cả 2 đều có >10 txs trong 5 phút
  - Price impact rất thấp (<1%)
  - Amounts gần giống nhau
```

**Scenario 2: Normal Trading**
```
Pool: 0xcd7c37...
  Sender A: 3 txs, avg_price_impact: 250, avg_amount: 50M
  Sender B: 2 txs, avg_price_impact: 180, avg_amount: 30M
  Time window: 2 hours
  
→ NORMAL: Legitimate trading
  - Ít transactions
  - Price impact cao (thực sự ảnh hưởng giá)
  - Time window dài
```

## Công thức tính toán:

### 1. Tính thời gian window (ms):
```python
time_window_ms = time_range.max - time_range.min
time_window_minutes = time_window_ms / 60000
```

### 2. Tính tần suất giao dịch:
```python
tx_per_minute = tx_count.value / time_window_minutes
```

### 3. Tính độ lệch amount:
```python
# So sánh 2 senders trong cùng pool
amount_variance = abs(avg_amount_A - avg_amount_B) / max(avg_amount_A, avg_amount_B)
# Nếu < 10% → suspicious
```

### 4. Wash Trading Score:
```python
score = 0
if tx_count >= 10: score += 3
if avg_price_impact < 100: score += 3
if amount_variance < 0.1: score += 2
if time_window_minutes < 30: score += 2

# Score >= 7 → HIGH CONFIDENCE wash trading
# Score >= 5 → MEDIUM CONFIDENCE
# Score < 5 → LOW CONFIDENCE
```

## Query để tìm Wash Trading Pairs:

Sau khi có kết quả, bạn cần:

1. **Group theo pool** → Xem pool nào có nhiều senders
2. **Trong mỗi pool** → Tìm 2 senders có:
   - `tx_count` cao (>10)
   - `avg_price_impact` thấp (<100)
   - `avg_amount` gần giống nhau
   - `time_range` trong cùng window ngắn (<30min)

3. **Post-processing** (Python):
   - Lấy danh sách transactions của 2 addresses
   - Kiểm tra xem có pattern alternating không (A→B→A→B...)
   - Tính correlation giữa amounts

## Ví dụ Python để phân tích:

```python
import json

result = {...}  # Kết quả từ Elasticsearch

wash_trading_pairs = []

for pool in result['aggregations']['by_pool']['pools']['buckets']:
    pool_id = pool['key']
    senders = pool['reverse_nested']['by_sender']['buckets']
    
    # Tìm các senders có tx_count cao
    high_freq_senders = [s for s in senders if s['tx_count']['value'] >= 10]
    
    # So sánh từng cặp
    for i, sender_a in enumerate(high_freq_senders):
        for sender_b in high_freq_senders[i+1:]:
            # Tính toán metrics
            price_impact_a = sender_a['avg_price_impact']['value']
            price_impact_b = sender_b['avg_price_impact']['value']
            amount_a = sender_a['avg_amount']['value']
            amount_b = sender_b['avg_amount']['value']
            
            # Tính variance
            amount_variance = abs(amount_a - amount_b) / max(amount_a, amount_b)
            
            # Tính time window
            time_window = (sender_a['time_range']['max'] - 
                          sender_a['time_range']['min']) / 60000
            
            # Check wash trading indicators
            if (price_impact_a < 100 and price_impact_b < 100 and
                amount_variance < 0.1 and time_window < 30):
                
                wash_trading_pairs.append({
                    'pool_id': pool_id,
                    'sender_a': sender_a['key'],
                    'sender_b': sender_b['key'],
                    'tx_count_a': sender_a['tx_count']['value'],
                    'tx_count_b': sender_b['tx_count']['value'],
                    'confidence': 'HIGH'
                })

print(f"Found {len(wash_trading_pairs)} wash trading pairs")
```

## Tóm tắt:

**Từ kết quả query, bạn biết được:**

1. ✅ **Pool nào** có nhiều giao dịch nhất
2. ✅ **Address nào** giao dịch nhiều nhất trong mỗi pool
3. ✅ **Price impact** trung bình của mỗi address
4. ✅ **Amount** trung bình của mỗi address
5. ✅ **Time window** của các giao dịch

**Sau đó phân tích để phát hiện:**
- 🔍 Wash trading: 2 addresses trade qua lại với frequency cao, price impact thấp
- 🔍 Market manipulation: 1 address có quá nhiều tx trong thời gian ngắn
- 🔍 Fake volume: Pool có volume cao nhưng price impact thấp

