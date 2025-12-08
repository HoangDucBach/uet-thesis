# Phân Tích Các Signal Của Các Analyzer Phát Hiện Tấn Công

## Tổng Quan

| Analyzer                | Mục Đích                                    | Số Signal | Threshold | Risk Levels                    |
| ----------------------- | ------------------------------------------- | --------- | --------- | ------------------------------ |
| **Oracle Manipulation** | Thao túng oracle để khai thác lending       | 6         | ≥40 điểm  | 40-59: Medium, 60-79: High, 80+: Critical |
| **Flash Loan**          | Flash loan arbitrage phức tạp               | 7         | ≥30 điểm  | 30-49: Low, 50-69: Medium, 70-84: High, 85+: Critical |
| **Sandwich**            | Front-run + back-run qua nhiều transaction  | 8         | ≥0 điểm   | 0-29: Low, 30-49: Medium, 50-69: High, 70+: Critical |
| **Price**               | Thao túng giá qua TWAP deviation             | 5         | ≥25 điểm  | 25-49: Low, 50-69: Medium, 70-84: High, 85+: Critical |

---

## 1. Oracle Manipulation Analyzer

### Bảng Signal

| Signal | Mô Tả | Event | Điểm Số | Ngưỡng |
|--------|-------|-------|---------|--------|
| Flash Loan Presence | Flash loan borrow + repay | `FlashLoanTaken`, `FlashLoanRepaid` | +20 | Bắt buộc |
| Large Price-Moving Swaps | Swap có price impact cao | `SwapExecuted` | +20-40 | ≥5% (500 bps) |
| Lending Borrows | Borrow từ lending protocol | `BorrowEvent` | +15-20 | ≥100 tokens |
| Price Deviation | Độ lệch oracle vs normal price | Tính toán | +20-40 | ≥10% (1000 bps) |
| Protocol Loss Risk | Ước tính tổn thất protocol | Tính toán | +10-20 | >0 |
| Abnormal Health Factor | Health factor bất thường | `BorrowEvent` | +10 | >1.5x (15000) |

### Công Thức Chính
- **Price Deviation**: `|oracle_price - normal_price| * 10000 / min(oracle_price, normal_price)`
- **Protocol Loss**: `max(0, borrow_amount - real_collateral_value)`

---

## 2. Flash Loan Analyzer

### Bảng Signal

| Signal | Mô Tả | Event | Điểm Số | Ngưỡng |
|--------|-------|-------|---------|--------|
| Flash Loan Presence | Flash loan borrow + repay | `FlashLoanTaken`, `FlashLoanRepaid` | Bắt buộc | Phải có |
| Circular Trading | Pattern A→B→A | Phân tích swaps | +30 | ≥2 swaps |
| Multiple Swaps | Số lượng swap | `SwapExecuted` | +10-20 | ≥2 swaps (+20 nếu ≥3) |
| Cumulative Price Impact | Tổng price impact | `SwapExecuted` | +15-25 | >10% (+25 nếu >20%) |
| Single High-Impact Swap | Swap đơn lẻ impact cao | `SwapExecuted` | +15 | >5% (500 bps) |
| Multi-Pool Arbitrage | Số pool duy nhất | Phân tích pools | +10-15 | ≥2 pools (+15 nếu ≥3) |
| Large Flash Loan | Số tiền flash loan lớn | `FlashLoanTaken` | +10 | >1000 tokens |

---

## 3. Sandwich Analyzer

### Bảng Signal

| Signal | Mô Tả | Điều Kiện | Điểm Số |
|--------|-------|-----------|---------|
| Front-Run Pattern | Swap attacker trước victim | Cùng pool, sender, direction, checkpoint ≤5 | Bắt buộc |
| Victim Transaction | Swap victim ở giữa | Cùng pool, khác sender, nằm giữa front/back-run | Bắt buộc |
| Back-Run Pattern | Swap attacker sau victim | Cùng pool, sender, direction với front-run | Bắt buộc |
| Attacker Profit | Lợi nhuận attacker | `back_run.amount_out - front_run.amount_in` | +20-40 |
| Victim Loss | Tổn thất victim (bps) | Tính từ expected output | +10-30 |
| Same Checkpoint | Front/back-run cùng checkpoint | `front_run.checkpoint == back_run.checkpoint` | +10 |
| Quick Execution | Thời gian thực thi nhanh | `time_diff < 5000ms` | +10 |
| Price Impact | Swap có impact đáng kể | `price_impact >= 100` (1%) | Bắt buộc |

### Đặc Điểm
- **Stateful**: Buffer 100 transactions
- **Cross-Transaction**: Phát hiện qua nhiều transaction
- **Checkpoint Distance**: ≤5 checkpoints

---

## 4. Price Analyzer

### Bảng Signal

| Signal | Mô Tả | Event | Điểm Số | Ngưỡng |
|--------|-------|-------|---------|--------|
| Direct Price Impact | Price impact từ swaps | `SwapExecuted` | +15-40 | ≥5% (500 bps) |
| Trade Size Ratio | Tỷ lệ trade/pool depth | `SwapExecuted` | +15-25 | >15% (+25 nếu >30%) |
| TWAP Deviation | Độ lệch spot vs TWAP | `TWAPUpdated` | +5-25 | ≥5% (500 bps) |
| Explicit Deviation | Event phát hiện deviation | `PriceDeviationDetected` | +10 | Event tồn tại |
| Pump Pattern | Nhiều swap cùng hướng | `SwapExecuted` | +10 | ≥2 swaps, cùng pool, ≥1% impact |

### Thresholds
- High price impact: 1000 bps (10%)
- Critical price impact: 2000 bps (20%)
- TWAP deviation: 500 bps (5%)
- Large trade ratio: 0.15 (15% of pool)

---

## So Sánh Nhanh

### Điểm Chung
- ✅ Tất cả sử dụng `price_impact` từ `SwapExecuted`
- ✅ Tính risk score và phân loại risk level
- ✅ Tạo `RiskEvent` với chi tiết đầy đủ

### Điểm Khác Biệt

| Analyzer | Đặc Điểm Nổi Bật |
|----------|------------------|
| **Oracle Manipulation** | Phân tích temporal correlation, protocol loss estimation |
| **Flash Loan** | Phát hiện circular trading, multi-pool arbitrage |
| **Sandwich** | Stateful analysis, cross-transaction pattern matching |
| **Price** | TWAP-based deviation, trade impact scoring |

