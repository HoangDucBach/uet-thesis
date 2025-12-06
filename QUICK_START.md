# 🚀 QUICK START - Attack Scenario Testing

## ✅ Đã có sẵn:
- ✅ Contracts deployed: `0x0a78ed73edcaca699f8ffead05a9626aadd6edb30d49523574c8016806b0530e`
- ✅ Shared objects created (DEX, Flash Loan, Lending, Oracle)
- ✅ Treasury caps & metadata
- ✅ 4 attack scenarios sẵn sàng

## 🎯 Run ngay bây giờ:

### **Step 1: Start Infrastructure** (5 phút)
```bash
cd /home/user/uet-thesis/infrastructures
docker-compose up -d

# Verify
docker-compose ps
```

Cần có:
- ✅ PostgreSQL (port 5432)
- ✅ Elasticsearch (port 9200)
- ✅ Redis (port 6379)

---

### **Step 2: Build Sui-Indexer** (2 phút)
```bash
cd /home/user/uet-thesis/sui-indexer
cargo build --release
```

---

### **Step 3: Run Indexer** (Terminal 1)
```bash
cd /home/user/uet-thesis/sui-indexer
cargo run --release
```

Giữ terminal này mở, bạn sẽ thấy detection alerts ở đây!

---

### **Step 4: Run Attack Scenarios** (Terminal 2)
```bash
# Terminal mới
cd /home/user/uet-thesis/sui-indexer/scenarios
source ../../contracts/setup.sh

# Run từng scenario:
./scenario_A_flash_loan.sh              # Flash loan basic
./scenario_B_price_manipulation.sh      # Price manipulation
./scenario_C_sandwich_attack.sh         # Sandwich attack
./scenario_D_oracle_manipulation.sh     # ⭐ CRITICAL - Oracle attack

# Hoặc run tất cả:
./run_all_scenarios.sh
```

---

## 📊 Xem Detection Results:

### **Trong Terminal 1 (Indexer):**
Bạn sẽ thấy:
```
╔════════════════════════════════════════════════════════════╗
║ 🚨 DETECTION ALERT - 3 Risk Events Found
╠════════════════════════════════════════════════════════════╣
║ Transaction: 0xabc123...
║ Checkpoint:  12345
╚════════════════════════════════════════════════════════════╝

📋 Event 1/3
   Type:        FlashLoanAttack
   Level:       High
   Description: Large flash loan detected (100,000 USDC)
```

### **Query PostgreSQL:**
```bash
docker exec -it postgres psql -U postgres -d sui_indexer -c "
  SELECT tx_digest, execution_status, created_at
  FROM transactions
  ORDER BY created_at DESC
  LIMIT 10;
"
```

### **Query Elasticsearch:**
```bash
curl -X GET "localhost:9200/sui-transactions/_search?pretty" \
  -H 'Content-Type: application/json' \
  -d '{"query": {"match_all": {}}, "size": 10}'
```

---

## 🎯 Expected Results:

| Scenario | Detections | Risk Level |
|----------|-----------|------------|
| A - Flash Loan | 1 | HIGH |
| B - Price Manip | 1 | HIGH |
| C - Sandwich | 2 | HIGH |
| D - Oracle ⭐ | 3 | CRITICAL |

**Total**: ~7 risk events

---

## 🔥 Scenario D - Oracle Manipulation (CRITICAL)

Đây là scenario quan trọng nhất cho thesis:

```bash
./scenario_D_oracle_manipulation.sh
```

**Attack Flow:**
1. Flash loan 100,000 USDC
2. Swap 80k USDC → WETH (price UP 50%)
3. Borrow from lending using manipulated oracle
4. Repay flash loan
5. Protocol loses ~50k USDC (bad debt)

**Expected Detection:**
- ✅ Flash Loan: HIGH
- ✅ Price Manipulation: CRITICAL (>50% impact)
- ✅ Oracle Manipulation: CRITICAL (5/5 signals)

**5 Signals Detected:**
1. ✓ Flash loan present (100k)
2. ✓ Large price deviation (>50%)
3. ✓ Significant borrow (150k)
4. ✓ Temporal correlation (same block)
5. ✓ Unhealthy position (under-collateralized)

---

## 🐛 Troubleshooting:

### Indexer không detect:
```bash
# Check package ID
grep SIMULATION_PACKAGE_ID /home/user/uet-thesis/sui-indexer/src/constants.rs
# Should be: 0x0a78ed73edcaca699f8ffead05a9626aadd6edb30d49523574c8016806b0530e
```

### Shared objects không tìm thấy:
```bash
source /home/user/uet-thesis/contracts/setup.sh
echo $FLASH_LOAN_POOL_USDC
echo $MARKET_USDC
```

### Database connection error:
```bash
cd /home/user/uet-thesis/infrastructures
docker-compose restart postgres
```

---

## 📝 Files Updated:

✅ `contracts/setup.sh` - All addresses loaded
✅ `sui-indexer/src/constants.rs` - Package ID updated
✅ `sui-indexer/scenarios/*.sh` - Ready to run

---

## 🎓 For Thesis:

After running scenarios, collect metrics:

1. **Detection Accuracy**: True positives / Total attacks
2. **Latency**: Time from tx to detection
3. **False Positives**: Manual verification
4. **Coverage**: Which attack types detected

Screenshot the detection alerts for presentation! 📸

---

**Ready to start!** 🚀

Just run:
```bash
cd /home/user/uet-thesis/infrastructures && docker-compose up -d
cd /home/user/uet-thesis/sui-indexer && cargo run --release
```

Then in another terminal:
```bash
cd /home/user/uet-thesis/sui-indexer/scenarios
source ../../contracts/setup.sh
./run_all_scenarios.sh
```
