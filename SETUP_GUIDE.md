# Hướng Dẫn Setup và Test DeFi Attack Detection System

## 🚀 Bước 1: Chuẩn Bị Môi Trường

### Prerequisites
- ✅ Contracts đã deploy (DONE)
- PostgreSQL
- Elasticsearch
- Sui CLI
- Rust (cargo)

### Kiểm tra Package ID
```bash
# Package ID từ deployment
PACKAGE_ID=0x18f41d08c00001b0295bcbd810e600354a84eb48bc534fbea47fa318257af7e2

# Verify package tồn tại
sui client object $PACKAGE_ID
```

---

## 📦 Bước 2: Setup PostgreSQL

### Cài đặt PostgreSQL
```bash
# Ubuntu/Debian
sudo apt update
sudo apt install postgresql postgresql-contrib

# macOS
brew install postgresql
brew services start postgresql

# Hoặc dùng Docker
docker run --name sui-postgres \
  -e POSTGRES_PASSWORD=postgres \
  -e POSTGRES_DB=sui_indexer \
  -p 5432:5432 \
  -d postgres:15
```

### Tạo Database
```bash
# Kết nối PostgreSQL
sudo -u postgres psql

# Trong psql shell
CREATE DATABASE sui_indexer;
CREATE USER sui_user WITH PASSWORD 'your_password';
GRANT ALL PRIVILEGES ON DATABASE sui_indexer TO sui_user;
\q
```

### Test Connection
```bash
psql postgresql://sui_user:your_password@localhost:5432/sui_indexer -c "SELECT 1"
```

---

## 🔍 Bước 3: Setup Elasticsearch

### Cài đặt Elasticsearch
```bash
# Docker (Recommended)
docker run --name sui-elasticsearch \
  -e "discovery.type=single-node" \
  -e "xpack.security.enabled=false" \
  -e "ES_JAVA_OPTS=-Xms512m -Xmx512m" \
  -p 9200:9200 \
  -p 9300:9300 \
  -d elasticsearch:8.11.0

# Hoặc download binary
wget https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-8.11.0-linux-x86_64.tar.gz
tar -xzf elasticsearch-8.11.0-linux-x86_64.tar.gz
cd elasticsearch-8.11.0/
./bin/elasticsearch
```

### Test Elasticsearch
```bash
curl http://localhost:9200
# Phải thấy response với cluster name
```

---

## ⚙️ Bước 4: Config Sui Indexer

### Tạo file `.env` trong `sui-indexer/`
```bash
cd sui-indexer
cat > .env << 'EOF'
# Database
DATABASE_URL=postgresql://sui_user:your_password@localhost:5432/sui_indexer

# Elasticsearch
ELASTICSEARCH_URL=http://localhost:9200
ELASTICSEARCH_INDEX=sui-transactions

# Target Package (từ deployment)
SIMULATION_PACKAGE_ID=0x18f41d08c00001b0295bcbd810e600354a84eb48bc534fbea47fa318257af7e2

# Alert Webhook (Optional - Slack/Discord)
# ALERT_WEBHOOK_URL=https://hooks.slack.com/services/YOUR/WEBHOOK/URL

# Sui RPC
SUI_RPC_URL=https://fullnode.testnet.sui.io:443

# Log level
RUST_LOG=info
EOF
```

### Chạy Database Migrations
```bash
cd sui-indexer
diesel migration run
```

---

## 🏗️ Bước 5: Build Indexer

```bash
cd sui-indexer

# Build release (production)
cargo build --release

# Hoặc build debug (faster compile, slower runtime)
cargo build
```

---

## 🧪 Bước 6: Tạo Test Scenarios

### Scenario 1: Flash Loan Attack
Tạo file `contracts/scripts/test_flash_loan_attack.sh`:

```bash
#!/bin/bash
set -e

PACKAGE_ID="0x18f41d08c00001b0295bcbd810e600354a84eb48bc534fbea47fa318257af7e2"
USDC_TREASURY=$(cat .env | grep USDC_TREASURY_CAP | cut -d'=' -f2)
WETH_TREASURY=$(cat .env | grep WETH_TREASURY_CAP | cut -d'=' -f2)

echo "🎯 Simulating Flash Loan Attack..."

# 1. Tạo pools
echo "1️⃣ Creating liquidity pools..."
sui client call \
  --package $PACKAGE_ID \
  --module simple_dex \
  --function create_pool \
  --type-args ${PACKAGE_ID}::usdc::USDC ${PACKAGE_ID}::weth::WETH \
  --gas-budget 10000000

# Lưu pool ID từ output
POOL_ID="<POOL_ID_FROM_OUTPUT>"

# 2. Add liquidity
echo "2️⃣ Adding liquidity..."
# Mint USDC
USDC_COIN=$(sui client call \
  --package $PACKAGE_ID \
  --module usdc \
  --function mint \
  --args $USDC_TREASURY 1000000000000 \
  --gas-budget 10000000 | grep "Created Objects" -A5 | grep "ID:" | cut -d':' -f2 | xargs)

# Mint WETH
WETH_COIN=$(sui client call \
  --package $PACKAGE_ID \
  --module weth \
  --function mint \
  --args $WETH_TREASURY 1000000000 \
  --gas-budget 10000000 | grep "Created Objects" -A5 | grep "ID:" | cut -d':' -f2 | xargs)

# 3. Execute Flash Loan Attack
echo "3️⃣ Executing flash loan attack..."
sui client call \
  --package $PACKAGE_ID \
  --module flash_loan_pool \
  --function borrow \
  --type-args ${PACKAGE_ID}::usdc::USDC \
  --args $POOL_ID 500000000000 \
  --gas-budget 10000000

# 4. Multiple swaps (arbitrage)
echo "4️⃣ Executing arbitrage swaps..."
# USDC -> WETH
sui client call \
  --package $PACKAGE_ID \
  --module simple_dex \
  --function swap_a_to_b \
  --type-args ${PACKAGE_ID}::usdc::USDC ${PACKAGE_ID}::weth::WETH \
  --args $POOL_ID $USDC_COIN 400000000000 \
  --gas-budget 10000000

# ... more swaps ...

# 5. Repay flash loan
echo "5️⃣ Repaying flash loan..."
sui client call \
  --package $PACKAGE_ID \
  --module flash_loan_pool \
  --function repay \
  --type-args ${PACKAGE_ID}::usdc::USDC \
  --args $POOL_ID $USDC_COIN \
  --gas-budget 10000000

echo "✅ Flash loan attack simulation complete!"
echo "📊 Check indexer logs for detection results"
```

### Scenario 2: Price Manipulation
Tạo file `contracts/scripts/test_price_manipulation.sh`:

```bash
#!/bin/bash
set -e

PACKAGE_ID="0x18f41d08c00001b0295bcbd810e600354a84eb48bc534fbea47fa318257af7e2"

echo "🎯 Simulating Price Manipulation Attack..."

# 1. Large swap to manipulate price
echo "1️⃣ Executing large swap (30% of pool)..."
sui client call \
  --package $PACKAGE_ID \
  --module simple_dex \
  --function swap_a_to_b \
  --type-args ${PACKAGE_ID}::usdc::USDC ${PACKAGE_ID}::weth::WETH \
  --args $POOL_ID $USDC_COIN 300000000000 \
  --gas-budget 10000000

# 2. Multiple consecutive swaps (pump pattern)
echo "2️⃣ Pump pattern: multiple consecutive swaps..."
for i in {1..3}; do
  echo "   Swap #$i"
  sui client call \
    --package $PACKAGE_ID \
    --module simple_dex \
    --function swap_a_to_b \
    --type-args ${PACKAGE_ID}::usdc::USDC ${PACKAGE_ID}::weth::WETH \
    --args $POOL_ID $USDC_COIN 100000000000 \
    --gas-budget 10000000
  sleep 2
done

echo "✅ Price manipulation simulation complete!"
```

### Scenario 3: Sandwich Attack
Tạo file `contracts/scripts/test_sandwich_attack.sh`:

```bash
#!/bin/bash
set -e

PACKAGE_ID="0x18f41d08c00001b0295bcbd810e600354a84eb48bc534fbea47fa318257af7e2"
ATTACKER_ADDRESS=$(sui client active-address)

echo "🎯 Simulating Sandwich Attack..."

# 1. Front-run: Attacker buys
echo "1️⃣ Front-run transaction..."
sui client call \
  --package $PACKAGE_ID \
  --module simple_dex \
  --function swap_a_to_b \
  --type-args ${PACKAGE_ID}::usdc::USDC ${PACKAGE_ID}::weth::WETH \
  --args $POOL_ID $ATTACKER_USDC 100000000000 \
  --gas-budget 10000000

# 2. Victim transaction (simulate with different address)
echo "2️⃣ Victim transaction..."
# In real scenario, this would be from different wallet
sui client call \
  --package $PACKAGE_ID \
  --module simple_dex \
  --function swap_a_to_b \
  --type-args ${PACKAGE_ID}::usdc::USDC ${PACKAGE_ID}::weth::WETH \
  --args $POOL_ID $VICTIM_USDC 500000000000 \
  --gas-budget 10000000

# 3. Back-run: Attacker sells
echo "3️⃣ Back-run transaction..."
sleep 2  # Wait a bit
sui client call \
  --package $PACKAGE_ID \
  --module simple_dex \
  --function swap_b_to_a \
  --type-args ${PACKAGE_ID}::usdc::USDC ${PACKAGE_ID}::weth::WETH \
  --args $POOL_ID $ATTACKER_WETH \
  --gas-budget 10000000

echo "✅ Sandwich attack simulation complete!"
echo "🔍 Sandwich detector should identify pattern across these 3 transactions"
```

---

## 🚀 Bước 7: Chạy Hệ Thống

### Terminal 1: Start Indexer
```bash
cd sui-indexer

# Run với logs
RUST_LOG=info cargo run --release

# Hoặc run binary
./target/release/sui-indexer
```

**Expected Output:**
```
✓ Indexed 0 transactions to Elasticsearch (flattened from ExecuteTransaction)
Elasticsearch client initialized: http://localhost:9200 -> sui-transactions
```

### Terminal 2: Execute Test Scenarios
```bash
cd contracts/scripts

# Make scripts executable
chmod +x test_*.sh

# Run flash loan attack
./test_flash_loan_attack.sh

# Chờ 5-10 giây để indexer xử lý

# Run price manipulation
./test_price_manipulation.sh

# Chờ 5-10 giây

# Run sandwich attack
./test_sandwich_attack.sh
```

### Terminal 3: Monitor Logs
```bash
# Watch indexer output
tail -f sui-indexer/logs/detection.log

# Or grep for detections
tail -f sui-indexer/logs/detection.log | grep "🔍 Detected"
```

---

## 📊 Bước 8: Verify Detection

### Kiểm tra Console Output
Trong Terminal 1 (indexer), bạn sẽ thấy:

```
🔍 Detected 1 risk events in tx abc12345
⚠️  [CRITICAL] Flash Loan Attack detected
    TX: 0xabc12345...
    Details: Flash loan arbitrage: 4 swaps, 25% impact, circular trading
    Risk Score: 90/100

🔍 Detected 1 risk events in tx def67890
⚠️  [HIGH] Price Manipulation detected
    TX: 0xdef67890...
    Details: 18% price impact, 35% swap-to-depth ratio
    Risk Score: 75/100

🔍 Detected 1 risk events in tx ghi11121
⚠️  [CRITICAL] Sandwich Attack detected
    TX: 0xghi11121...
    Attacker: 0x123...
    Victim loss: 6%, Attacker profit: 50 USDC
    Risk Score: 80/100
```

### Query Elasticsearch
```bash
# Get all detected events
curl -X GET "localhost:9200/sui-transactions/_search" -H 'Content-Type: application/json' -d'
{
  "query": {
    "exists": {
      "field": "risk_level"
    }
  }
}
'

# Get critical events only
curl -X GET "localhost:9200/sui-transactions/_search" -H 'Content-Type: application/json' -d'
{
  "query": {
    "term": {
      "risk_level": "Critical"
    }
  }
}
'
```

### Query PostgreSQL
```bash
psql postgresql://sui_user:your_password@localhost:5432/sui_indexer

-- Count total transactions
SELECT COUNT(*) FROM transactions;

-- Find transactions with package ID
SELECT tx_digest, sender, timestamp_ms
FROM transactions
WHERE raw_transaction::text LIKE '%18f41d08c00001b0295bcbd810e600354a84eb48bc534fbea47fa318257af7e2%';
```

---

## 🧪 Bước 9: Test Từng Detector Riêng Lẻ

### Unit Tests
```bash
cd sui-indexer

# Test all
cargo test

# Test specific detector
cargo test flash_loan
cargo test price_manipulation
cargo test sandwich

# With output
cargo test -- --nocapture
```

### Integration Test với Real Data
```bash
# Tạo file test_integration.sh
cat > test_integration.sh << 'EOF'
#!/bin/bash

echo "Testing Flash Loan Detector..."
cargo test test_flash_loan_detection -- --nocapture

echo "Testing Price Manipulation Detector..."
cargo test test_price_manipulation_detection -- --nocapture

echo "Testing Sandwich Detector..."
cargo test test_sandwich_detection -- --nocapture
EOF

chmod +x test_integration.sh
./test_integration.sh
```

---

## 📈 Bước 10: Monitoring và Analytics

### Setup Kibana (Optional)
```bash
# Run Kibana with Docker
docker run --name sui-kibana \
  --link sui-elasticsearch:elasticsearch \
  -p 5601:5601 \
  -d kibana:8.11.0

# Open browser
open http://localhost:5601
```

### Create Dashboard
1. Vào Kibana: http://localhost:5601
2. **Create Index Pattern**: `sui-transactions*`
3. **Create Visualizations**:
   - Pie chart: Risk levels distribution
   - Line chart: Attacks over time
   - Table: Latest detected attacks
4. **Create Dashboard**: Combine all visualizations

### Slack/Discord Alerts (Optional)
```bash
# Get webhook URL từ Slack/Discord
# Add vào .env
echo "ALERT_WEBHOOK_URL=https://hooks.slack.com/services/YOUR/WEBHOOK" >> .env

# Restart indexer
```

---

## 🔧 Troubleshooting

### Lỗi thường gặp

**1. "No transactions detected"**
```bash
# Check Sui RPC connection
curl https://fullnode.testnet.sui.io:443/

# Verify package ID
sui client object $PACKAGE_ID
```

**2. "Database connection failed"**
```bash
# Test PostgreSQL
psql postgresql://sui_user:password@localhost:5432/sui_indexer -c "SELECT 1"

# Run migrations
cd sui-indexer && diesel migration run
```

**3. "Elasticsearch not reachable"**
```bash
# Check Elasticsearch
curl http://localhost:9200/_cluster/health

# Restart Elasticsearch
docker restart sui-elasticsearch
```

**4. "Type mismatch CheckpointTransaction vs ExecutedTransaction"**
- Đây là known issue đã được workaround
- Package filtering chỉ check events (đủ cho mục đích detection)

---

## 📝 Performance Testing

### Load Test Script
```bash
# Tạo file load_test.sh
cat > load_test.sh << 'EOF'
#!/bin/bash

echo "Running load test: 100 transactions"
for i in {1..100}; do
  echo "Transaction #$i"
  sui client call \
    --package $PACKAGE_ID \
    --module simple_dex \
    --function swap_a_to_b \
    --type-args ${PACKAGE_ID}::usdc::USDC ${PACKAGE_ID}::weth::WETH \
    --args $POOL_ID $USDC_COIN 10000000 \
    --gas-budget 10000000 &

  if [ $((i % 10)) -eq 0 ]; then
    wait  # Wait every 10 transactions
    echo "Checkpoint: $i transactions sent"
  fi
done

wait
echo "✅ Load test complete"
EOF

chmod +x load_test.sh
```

---

## 🎓 Next Steps

1. **Viết báo cáo thesis**:
   - Document detection algorithms (đã có DETECTION_RESEARCH.md)
   - So sánh với các giải pháp hiện tại
   - Kết quả test scenarios

2. **Improve detection**:
   - Fine-tune thresholds dựa trên test results
   - Add thêm attack patterns
   - Machine learning integration

3. **Production deployment**:
   - Deploy lên server
   - Setup proper monitoring
   - CI/CD pipeline

---

## 📚 Tài liệu tham khảo

- **Detection Algorithms**: `sui-indexer/DETECTION.md`
- **Research Foundation**: `sui-indexer/DETECTION_RESEARCH.md`
- **Contract Docs**: `contracts/README.md`

---

**Questions? Issues?**
- Check logs: `sui-indexer/logs/`
- Debug mode: `RUST_LOG=debug cargo run`
- Linter warnings đã được fix tự động
