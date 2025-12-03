# Test Scenarios for DeFi Attack Detection

## Quick Start

Các scenarios này giúp test detection system bằng cách simulate các attack patterns thực tế.

## Setup

```bash
# Load environment variables
cd contracts
source .env

# Verify package deployed
sui client object $PACKAGE_ID
```

## Cách Test Đơn Giản Nhất

### Option 1: Sử dụng Sui CLI (Manual)

**Bước 1: Tạo Pool và Add Liquidity**

```bash
# Set variables
PACKAGE_ID=0x18f41d08c00001b0295bcbd810e600354a84eb48bc534fbea47fa318257af7e2

# Create USDC-WETH pool
sui client call \
  --package $PACKAGE_ID \
  --module simple_dex \
  --function create_pool \
  --type-args ${PACKAGE_ID}::usdc::USDC ${PACKAGE_ID}::weth::WETH \
  --gas-budget 100000000

# Lưu lại POOL_ID từ output (trong Created Objects)
```

**Bước 2: Mint Coins**

```bash
# Mint USDC (cần USDC_TREASURY_CAP từ .env)
sui client call \
  --package $PACKAGE_ID \
  --module usdc \
  --function mint \
  --args <USDC_TREASURY_CAP> 10000000000000 \
  --gas-budget 100000000

# Lưu lại USDC_COIN_ID từ output

# Mint WETH
sui client call \
  --package $PACKAGE_ID \
  --module weth \
  --function mint \
  --args <WETH_TREASURY_CAP> 10000000000 \
  --gas-budget 100000000

# Lưu lại WETH_COIN_ID
```

**Bước 3: Add Liquidity vào Pool**

```bash
sui client call \
  --package $PACKAGE_ID \
  --module simple_dex \
  --function add_liquidity \
  --type-args ${PACKAGE_ID}::usdc::USDC ${PACKAGE_ID}::weth::WETH \
  --args <POOL_ID> <USDC_COIN_ID> <WETH_COIN_ID> 5000000000000 5000000000 \
  --gas-budget 100000000
```

### Scenario 1: Flash Loan Attack

```bash
# 1. Borrow flash loan (large amount)
sui client call \
  --package $PACKAGE_ID \
  --module flash_loan_pool \
  --function borrow \
  --type-args ${PACKAGE_ID}::usdc::USDC \
  --args <POOL_ID> 5000000000000 \
  --gas-budget 100000000

# 2. Multiple swaps (arbitrage pattern)
# Swap 1: USDC -> WETH
sui client call \
  --package $PACKAGE_ID \
  --module simple_dex \
  --function swap_a_to_b \
  --type-args ${PACKAGE_ID}::usdc::USDC ${PACKAGE_ID}::weth::WETH \
  --args <POOL_ID> <USDC_COIN_ID> 4000000000000 \
  --gas-budget 100000000

# Swap 2: WETH -> USDC (circular trading)
sui client call \
  --package $PACKAGE_ID \
  --module simple_dex \
  --function swap_b_to_a \
  --type-args ${PACKAGE_ID}::usdc::USDC ${PACKAGE_ID}::weth::WETH \
  --args <POOL_ID> <WETH_COIN_ID> \
  --gas-budget 100000000

# 3. Repay flash loan
sui client call \
  --package $PACKAGE_ID \
  --module flash_loan_pool \
  --function repay \
  --type-args ${PACKAGE_ID}::usdc::USDC \
  --args <POOL_ID> <USDC_COIN_ID> \
  --gas-budget 100000000
```

**Detection Expected:**
```
🔍 Detected 1 risk events in tx abc123...
⚠️  [CRITICAL] Flash Loan Attack
Risk Score: 90/100
- Flash loan: 5000 USDC
- 3+ swaps detected
- Circular trading pattern
- High price impact
```

---

### Scenario 2: Price Manipulation

```bash
# Large swap (>20% of pool)
sui client call \
  --package $PACKAGE_ID \
  --module simple_dex \
  --function swap_a_to_b \
  --type-args ${PACKAGE_ID}::usdc::USDC ${PACKAGE_ID}::weth::WETH \
  --args <POOL_ID> <USDC_COIN_ID> 1500000000000 \
  --gas-budget 100000000

# Consecutive swaps (pump pattern)
sui client call \
  --package $PACKAGE_ID \
  --module simple_dex \
  --function swap_a_to_b \
  --type-args ${PACKAGE_ID}::usdc::USDC ${PACKAGE_ID}::weth::WETH \
  --args <POOL_ID> <USDC_COIN_ID> 800000000000 \
  --gas-budget 100000000
```

**Detection Expected:**
```
🔍 Detected 1 risk events in tx def456...
⚠️  [HIGH] Price Manipulation
Risk Score: 75/100
- Price impact: 18%
- Swap-to-depth ratio: 30%
- Consecutive large swaps
```

---

### Scenario 3: Sandwich Attack

Cần 2 wallets (attacker và victim) hoặc simulate bằng 3 transactions liên tiếp:

```bash
# Transaction 1: Front-run (Attacker buys)
sui client call \
  --package $PACKAGE_ID \
  --module simple_dex \
  --function swap_a_to_b \
  --type-args ${PACKAGE_ID}::usdc::USDC ${PACKAGE_ID}::weth::WETH \
  --args <POOL_ID> <ATTACKER_USDC> 1000000000 \
  --gas-budget 100000000

# Transaction 2: Victim transaction (large trade)
sui client call \
  --package $PACKAGE_ID \
  --module simple_dex \
  --function swap_a_to_b \
  --type-args ${PACKAGE_ID}::usdc::USDC ${PACKAGE_ID}::weth::WETH \
  --args <POOL_ID> <VICTIM_USDC> 5000000000 \
  --gas-budget 100000000

# Transaction 3: Back-run (Attacker sells)
sui client call \
  --package $PACKAGE_ID \
  --module simple_dex \
  --function swap_b_to_a \
  --type-args ${PACKAGE_ID}::usdc::USDC ${PACKAGE_ID}::weth::WETH \
  --args <POOL_ID> <ATTACKER_WETH> \
  --gas-budget 100000000
```

**Detection Expected:**
```
🔍 Detected 1 risk events in tx ghi789...
⚠️  [CRITICAL] Sandwich Attack
Risk Score: 80/100
- Attacker: 0x123...
- Victim loss: 6%
- Attacker profit: 50 USDC
- 3-transaction pattern detected
```

---

## Option 2: Sử dụng Move Test (Automated)

Contract đã có sẵn test cases trong `contracts/sources/`:

```bash
cd contracts
sui move test

# Run specific test
sui move test test_flash_loan
sui move test test_price_manipulation
```

Move tests sẽ tự động emit events mà indexer có thể detect.

---

## Verification Checklist

Sau khi chạy scenarios:

### 1. Check Indexer Console
```
✓ Xem output trong terminal chạy indexer
✓ Tìm messages "🔍 Detected X risk events"
✓ Verify risk scores và levels
```

### 2. Check Elasticsearch
```bash
# Count detected events
curl -X GET "localhost:9200/sui-transactions/_search?q=risk_level:*&size=0"

# View latest detections
curl -X GET "localhost:9200/sui-transactions/_search" -H 'Content-Type: application/json' -d'
{
  "query": {"exists": {"field": "risk_level"}},
  "sort": [{"timestamp_ms": "desc"}],
  "size": 10
}'
```

### 3. Check PostgreSQL
```bash
psql postgresql://postgres:postgres@localhost:5432/sui_indexer

SELECT tx_digest, sender, execution_status
FROM transactions
ORDER BY timestamp_ms DESC
LIMIT 10;
```

---

## Tips

1. **Chạy từng scenario riêng lẻ**: Dễ verify detection
2. **Chờ 5-10 giây giữa các test**: Để indexer xử lý kịp
3. **Monitor cả 2 terminals**: Một chạy indexer, một chạy scenarios
4. **Save object IDs**: Mỗi lần mint coin hoặc create pool, save ID để reuse
5. **Check gas budget**: Nếu transaction fail, tăng gas budget

---

## Troubleshooting

**"Pool not found"**
- Verify pool đã được tạo: `sui client object <POOL_ID>`

**"Insufficient balance"**
- Mint thêm coins với treasury caps

**"No detection output"**
- Check indexer đang chạy
- Verify SIMULATION_PACKAGE_ID trong .env
- Check logs: `RUST_LOG=debug cargo run`

**"Type mismatch error"**
- Double check type arguments khớp với package ID

---

## Advanced: Automated Test Suite

Nếu muốn tự động hóa, tạo file `run_all_tests.sh`:

```bash
#!/bin/bash
echo "Running all attack scenarios..."

echo "1. Flash Loan Attack..."
# ... commands ...
sleep 10

echo "2. Price Manipulation..."
# ... commands ...
sleep 10

echo "3. Sandwich Attack..."
# ... commands ...
sleep 10

echo "✅ All scenarios complete!"
echo "📊 Check indexer output for results"
```

---

## Expected Results Summary

| Scenario | Risk Level | Key Signals | Score Range |
|----------|-----------|-------------|-------------|
| Flash Loan | Critical | Circular trading, 3+ swaps, high impact | 85-100 |
| Price Manipulation | High/Critical | >15% impact, large swap ratio | 70-90 |
| Sandwich | Critical | Front/back pattern, victim loss | 70-90 |

---

Để test chi tiết hơn, xem: `/home/user/uet-thesis/SETUP_GUIDE.md`
