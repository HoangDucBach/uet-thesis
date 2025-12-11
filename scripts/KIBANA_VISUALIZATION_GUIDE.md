# Hướng dẫn tạo Visualization trên Kibana

## Prerequisites

1. **Kibana đã cài đặt và kết nối với Elasticsearch**
2. **Index pattern đã được tạo** cho `sui-transactions`
3. **Dữ liệu đã được index** vào Elasticsearch

---

## Bước 1: Tạo Index Pattern

1. Vào **Management** → **Stack Management** → **Index Patterns**
2. Click **Create index pattern**
3. Nhập tên index: `sui-transactions`
4. Chọn **timestamp field**: `timestamp_ms`
5. Click **Create index pattern**

**Lưu ý quan trọng**: Kibana có thể không tự động detect nested fields. Bạn cần verify rằng `events` được nhận diện là nested type.

---

## Bước 2: Các Visualization quan trọng

### 2.1 Transaction Volume Over Time (Time Series)

**Mục đích**: Theo dõi volume giao dịch theo thời gian, phát hiện anomalies

**Cách tạo:**
1. **Analytics** → **Visualize Library** → **Create visualization**
2. Chọn **Lens** (hoặc **Time Series**)
3. Chọn index pattern: `sui-transactions`

**Configuration:**
- **X-axis**: `timestamp_ms` (Date Histogram)
  - Interval: `1h` hoặc `5m` (tùy độ chi tiết)
- **Y-axis**: Metric Aggregation
  - Aggregation: `Value count` hoặc `Sum`
  - Field: Nếu dùng Sum, cần dùng **nested aggregation**:
    - Click **Add metric**
    - Chọn **Nested** aggregation
    - Path: `events`
    - Sub-aggregation: `Sum`
    - Field: `events.event_data.amount_in`

**Filter (optional):**
- Add filter: `modules.keyword: simple_dex`

---

### 2.2 Wash Trading Detection - Direction Balance

**Mục đích**: Phát hiện self wash trading (same sender, both directions)

**Cách tạo:**
1. **Create visualization** → **Lens** hoặc **Data Table**
2. Chọn index: `sui-transactions`

**Configuration:**

**Method 1: Sử dụng Data Table**
- **Bucket**: `sender` (Terms aggregation, size: 100)
- **Bucket**: `functions` (Terms aggregation, size: 10)
- **Metrics**: 
  - Count
  - Stats trên `events.event_data.amount_in` (cần nested aggregation)

**Method 2: Sử dụng Saved Query (Recommended)**
Tạo **Saved Search** trước với query:

```json
{
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
        "amount_stats": {
          "nested": {"path": "events"},
          "aggs": {
            "stats": {
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

Sau đó tạo visualization từ saved search này.

---

### 2.3 Pool Activity Heatmap

**Mục đích**: Xem activity theo pool và thời gian

**Cách tạo:**
1. **Create visualization** → **Heatmap** hoặc **Lens**
2. Chọn index: `sui-transactions`

**Configuration (Lens):**
- **X-axis**: `timestamp_ms` (Date Histogram, 1h interval)
- **Y-axis**: 
  - Tạo **Nested** aggregation trên `events`
  - Field: `events.event_data.pool_id`
  - Aggregation: `Terms` (top 10 pools)
- **Color**: 
  - Metric: `Count` hoặc `Sum(events.event_data.amount_in)`
  - Color scale: Sequential (green → red)

**Lưu ý**: Kibana Lens có thể không hỗ trợ nested fields trực tiếp. Trong trường hợp này, dùng **Aggregations-based visualization**:

1. **Create visualization** → **Vertical Bar** hoặc **Line**
2. **Metrics**:
   - Add metric → **Nested** → Path: `events`
   - Sub-aggregation: **Sum** → Field: `events.event_data.amount_in`
3. **Buckets**:
   - **X-axis**: `timestamp_ms` (Date Histogram)
   - **Split series**: Nested → Path: `events` → Terms → `events.event_data.pool_id`

---

### 2.4 Money Laundering - Peel Chain Visualization

**Mục đích**: Visualize flow của peel chains

**Cách tạo (Network Graph):**
1. **Create visualization** → **Vega** hoặc **Timelion**

**Hoặc sử dụng Saved Query + Post-processing:**
1. Tạo **Saved Search** với query peel chain (lấy transactions)
2. Export data
3. Post-process bằng Python script (`detect_money_laundering.py`)
4. Visualize bằng external tool (NetworkX, Cytoscape) hoặc re-index kết quả

**Alternative: Sankey Diagram (Vega)**
```json
{
  "$schema": "https://vega.github.io/schema/vega/v5.json",
  "description": "Peel Chain Flow",
  "data": [
    {
      "name": "peel_chains",
      "url": {
        "index": "sui-transactions",
        "body": {
          "query": {
            "term": {"modules": "simple_dex"}
          },
          "size": 1000,
          "_source": ["sender", "events.event_data.amount_out", "events.event_data.amount_in"]
        }
      }
    }
  ],
  "marks": [...]
}
```

---

### 2.5 Top Active Addresses

**Mục đích**: Xem top addresses theo volume/transaction count

**Cách tạo:**
1. **Create visualization** → **Horizontal Bar** hoặc **Data Table**
2. Chọn index: `sui-transactions`

**Configuration:**
- **Metric**: 
  - Nested aggregation → Path: `events` → Sum → `events.event_data.amount_in`
  - Hoặc Count
- **Bucket**: 
  - `sender` (Terms, size: 20, order by metric desc)

**Filter**: `modules: simple_dex`

---

### 2.6 Price Impact Distribution

**Mục đích**: Phát hiện large swaps với high price impact (flash loan attacks)

**Cách tạo:**
1. **Create visualization** → **Histogram** hoặc **Lens**
2. Chọn index: `sui-transactions`

**Configuration:**
- **X-axis**: 
  - Nested → Path: `events` → Histogram → `events.event_data.price_impact`
  - Interval: Auto hoặc 1000000 (1M)
- **Y-axis**: Count
- **Filter**: 
  - `modules: simple_dex`
  - Range filter: `events.event_data.amount_in >= 50000000000` (large swaps)

**Lưu ý**: Nested histogram có thể cần dùng **Aggregations** thay vì Lens.

---

### 2.7 Transaction Direction Balance

**Mục đích**: Xem tỷ lệ swap_a_to_b vs swap_b_to_a

**Cách tạo:**
1. **Create visualization** → **Pie Chart** hoặc **Donut**
2. Chọn index: `sui-transactions`

**Configuration:**
- **Slice by**: `functions` (Terms aggregation)
- **Size**: Count
- **Filter**: `modules: simple_dex`

---

### 2.8 Time-based Anomaly Detection

**Mục đích**: Phát hiện volume spikes (pump detection)

**Cách tạo:**
1. **Create visualization** → **Time Series**
2. Chọn index: `sui-transactions`

**Configuration:**
- **X-axis**: `timestamp_ms` (Date Histogram, 1h)
- **Y-axis**: 
  - Nested → Sum → `events.event_data.amount_in`
- **Anomaly Detection**:
  - Click **Add metric** → **Anomaly detection** (nếu có Machine Learning enabled)
  - Hoặc dùng **Reference lines** với z-score threshold

---

## Bước 3: Tạo Dashboard

1. **Analytics** → **Dashboards** → **Create dashboard**
2. Add visualizations:
   - Click **Add** → Chọn các visualization đã tạo
   - Hoặc tạo mới trực tiếp từ dashboard
3. **Layout**:
   - Drag & drop để sắp xếp
   - Resize panels
4. **Time Picker**: Set default time range (Last 7 days, Last 24 hours, etc.)
5. **Filters**:
   - Add filter bar ở top
   - Common filters: `modules: simple_dex`

---

## Lưu ý quan trọng về Nested Fields

### Vấn đề với Nested Fields trong Kibana

Kibana có thể không query nested fields đúng cách trong một số trường hợp. Có 3 cách xử lý:

**1. Sử dụng Aggregations-based Visualization (Recommended)**
- Không dùng Lens cho nested fields
- Dùng **Vertical Bar**, **Line**, **Data Table** với aggregation editor
- Thêm Nested aggregation trong **Metrics** hoặc **Buckets**

**2. Sử dụng Saved Search**
- Tạo Saved Search với nested query đúng
- Tạo visualization từ saved search

**3. Tạo Runtime Fields (nếu cần)**
Trong Index Pattern settings:
- **Management** → **Index Patterns** → `sui-transactions` → **Runtime fields**
- Add runtime field:
  - Name: `events_pool_id`
  - Type: `keyword`
  - Script:
    ```painless
    if (doc['events.type'].size() > 0) {
      def eventData = params._source.events[0].event_data;
      if (eventData != null && eventData.pool_id != null) {
        return eventData.pool_id;
      }
    }
    return null;
    ```
- Lưu ý: Runtime fields có thể chậm hơn, chỉ dùng khi thực sự cần

---

## Các Visualization Template

### Template 1: Wash Trading Dashboard

**Components:**
1. **Transaction Volume Over Time** (Line chart)
2. **Direction Balance** (Pie chart: swap_a_to_b vs swap_b_to_a)
3. **Top Self-Traders Table** (Data table: sender, direction counts, CV)
4. **Pool Concentration** (Horizontal bar: top pools)

**Filters:**
- Time range: Last 7 days
- Module: simple_dex

---

### Template 2: Money Laundering Dashboard

**Components:**
1. **Transaction Timeline** (Time series)
2. **Peel Chain Flow** (Sankey diagram - cần Vega hoặc external)
3. **Top Layering Addresses** (Table: sender, pool_count, volume)
4. **Amount Distribution** (Histogram: amount_in/out)

**Filters:**
- Time range: Custom (last 24h, 48h)
- Min amount filter

---

### Template 3: Attack Detection Dashboard

**Components:**
1. **Large Swaps** (Table: amount_in > 50B)
2. **Price Impact vs Amount** (Scatter plot)
3. **Sandwich Attack Alerts** (Data table)
4. **Volume Anomalies** (Time series với anomaly overlay)

---

## Troubleshooting

### Vấn đề: Nested fields không hiển thị

**Giải pháp:**
1. Verify mapping: `curl http://localhost:9200/sui-transactions/_mapping | grep nested`
2. Refresh index pattern: Management → Index Patterns → Refresh
3. Dùng Aggregations editor thay vì Lens
4. Tạo Saved Search với nested query trước

### Vấn đề: Performance chậm

**Giải pháp:**
1. Giảm time range
2. Tăng interval (5m → 1h)
3. Thêm filters để giảm data
4. Dùng index aliases với filtered data

### Vấn đề: Cannot query nested field

**Giải pháp:**
- Luôn dùng **nested query** trong Kibana:
  - Filter: `events.event_data.pool_id: value` sẽ không hoạt động
  - Phải dùng query DSL hoặc Saved Search

---

## Export & Share

### Export Dashboard
1. Click **Share** → **Export**
2. Copy shareable link
3. Embed code (nếu cần)

### Save Search Results
1. Trong Discover: Save search
2. Export data: CSV, JSON

---

## Best Practices

1. **Đặt tên rõ ràng**: "Wash Trading - Direction Balance" thay vì "Chart 1"
2. **Thêm descriptions**: Mô tả ngắn gọn mục đích
3. **Sử dụng filters**: Luôn filter theo `modules: simple_dex`
4. **Refresh rate**: Set auto-refresh cho real-time dashboards
5. **Time range**: Đặt default time range hợp lý
6. **Color schemes**: Dùng color schemes consistent
7. **Annotations**: Thêm annotations cho events quan trọng

---

## Advanced: Custom Visualizations với Vega

Để tạo network graphs, sankey diagrams cho peel chains, có thể dùng Vega:

1. **Create visualization** → **Vega**
2. Sử dụng Vega spec với Elasticsearch data source
3. Example: See network graph example trong documentation

---

## Quick Reference

| Visualization Type | Use Case | Nested Support |
|-------------------|----------|----------------|
| **Lens** | General purpose, easy | Limited |
| **Aggregations** | Complex nested queries | ✅ Full support |
| **Data Table** | Detailed analysis | ✅ Full support |
| **Time Series** | Temporal patterns | ✅ With nested |
| **Vega** | Custom graphs (network, sankey) | Via query |

---

## Example Dashboard JSON

Có thể export dashboard JSON và import lại:
1. **Management** → **Saved Objects** → **Export**
2. Chọn dashboard → Export
3. Import: **Import** → Upload file

---

## Resources

- [Kibana Lens Documentation](https://www.elastic.co/guide/en/kibana/current/lens.html)
- [Kibana Aggregations](https://www.elastic.co/guide/en/kibana/current/aggregations.html)
- [Nested Fields in Kibana](https://www.elastic.co/guide/en/elasticsearch/reference/current/nested.html)

---

## Next Steps

1. Tạo index pattern
2. Tạo 2-3 visualization đơn giản để test
3. Tạo dashboard đầu tiên
4. Expand với các visualization phức tạp hơn
5. Setup alerts (nếu có ML enabled)

