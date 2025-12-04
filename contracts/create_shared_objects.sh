#!/bin/bash
echo "==================================================================="
echo "CREATING SHARED OBJECTS FOR TESTING"
echo "==================================================================="

# 1. Create Coin Factory
echo "📦 Step 1: Creating Coin Factory..."
FACTORY_TX=$(sui client call \
  --package $PACKAGE_ID \
  --module coin_factory \
  --function create_factory \
  --args \
    $USDC_TREASURY \
    $USDT_TREASURY \
    $WETH_TREASURY \
    $BTC_TREASURY \
    $SUI_TREASURY \
  --gas-budget 100000000 \
  --json | jq -r '.digest')

echo "✓ Factory TX: $FACTORY_TX"
sleep 3

# Get Factory ID from transaction
export COIN_FACTORY=$(sui client object --json $FACTORY_TX | jq -r '.objectChanges[] | select(.type == "created" and (.objectType | contains("CoinFactory"))) | .objectId')
echo "✓ Coin Factory ID: $COIN_FACTORY"

# 2. Create Flash Loan Pools
echo ""
echo "💰 Step 2: Creating Flash Loan Pools..."

# Mint initial liquidity
USDC_10K=$(sui client call \
  --package $PACKAGE_ID \
  --module coin_factory \
  --function mint_usdc \
  --args $COIN_FACTORY 10000000000000 \
  --gas-budget 10000000 \
  --json | jq -r '.objectChanges[] | select(.type == "created" and (.objectType | contains("Coin"))) | .objectId')

echo "✓ Minted 10,000 USDC: $USDC_10K"

# Create USDC Flash Loan Pool (0.09% fee = 9 bps)
FL_POOL_TX=$(sui client call \
  --package $PACKAGE_ID \
  --module flash_loan_pool \
  --function create_pool \
  --type-args $USDC_TYPE \
  --args $USDC_10K 9 \
  --gas-budget 10000000 \
  --json | jq -r '.digest')

export FLASH_LOAN_POOL=$(sui client object --json $FL_POOL_TX | jq -r '.objectChanges[] | select(.type == "created" and (.objectType | contains("FlashLoanPool"))) | .objectId')
echo "✓ Flash Loan Pool (USDC): $FLASH_LOAN_POOL"

# 3. Create DEX Pools
echo ""
echo "🔄 Step 3: Creating DEX Pools..."

# Mint tokens for pools
USDC_5K=$(sui client call --package $PACKAGE_ID --module coin_factory --function mint_usdc --args $COIN_FACTORY 5000000000000 --gas-budget 10000000 --json | jq -r '.objectChanges[] | select(.type == "created" and (.objectType | contains("Coin"))) | .objectId')
USDT_5K=$(sui client call --package $PACKAGE_ID --module coin_factory --function mint_usdt --args $COIN_FACTORY 5000000000000 --gas-budget 10000000 --json | jq -r '.objectChanges[] | select(.type == "created" and (.objectType | contains("Coin"))) | .objectId')
WETH_5K=$(sui client call --package $PACKAGE_ID --module coin_factory --function mint_weth --args $COIN_FACTORY 5000000000000 --gas-budget 10000000 --json | jq -r '.objectChanges[] | select(.type == "created" and (.objectType | contains("Coin"))) | .objectId')

# Create Pool USDC/USDT
POOL1_TX=$(sui client call \
  --package $PACKAGE_ID \
  --module simple_dex \
  --function create_pool \
  --type-args $USDC_TYPE $USDT_TYPE \
  --args $USDC_5K $USDT_5K \
  --gas-budget 20000000 \
  --json | jq -r '.digest')

export DEX_POOL_USDC_USDT=$(sui client object --json $POOL1_TX | jq -r '.objectChanges[] | select(.type == "created" and (.objectType | contains("Pool"))) | .objectId')
echo "✓ DEX Pool USDC/USDT: $DEX_POOL_USDC_USDT"

# Create Pool USDT/WETH
USDT_5K_2=$(sui client call --package $PACKAGE_ID --module coin_factory --function mint_usdt --args $COIN_FACTORY 5000000000000 --gas-budget 10000000 --json | jq -r '.objectChanges[] | select(.type == "created" and (.objectType | contains("Coin"))) | .objectId')

POOL2_TX=$(sui client call \
  --package $PACKAGE_ID \
  --module simple_dex \
  --function create_pool \
  --type-args $USDT_TYPE $WETH_TYPE \
  --args $USDT_5K_2 $WETH_5K \
  --gas-budget 20000000 \
  --json | jq -r '.digest')

export DEX_POOL_USDT_WETH=$(sui client object --json $POOL2_TX | jq -r '.objectChanges[] | select(.type == "created" and (.objectType | contains("Pool"))) | .objectId')
echo "✓ DEX Pool USDT/WETH: $DEX_POOL_USDT_WETH"

# 4. Create TWAP Oracle
echo ""
echo "📊 Step 4: Creating TWAP Oracle..."

ORACLE_TX=$(sui client call \
  --package $PACKAGE_ID \
  --module twap_oracle \
  --function create_oracle \
  --type-args $USDC_TYPE $USDT_TYPE \
  --args $DEX_POOL_USDC_USDT 1800000 60000 \
  --gas-budget 10000000 \
  --json | jq -r '.digest')

export TWAP_ORACLE=$(sui client object --json $ORACLE_TX | jq -r '.objectChanges[] | select(.type == "created" and (.objectType | contains("TWAPOracle"))) | .objectId')
echo "✓ TWAP Oracle: $TWAP_ORACLE"

# 5. Save to .env.local
echo ""
echo "💾 Step 5: Saving to .env.local..."

cat >> .env.local << EOF
# Shared Objects (Created $(date))
COIN_FACTORY_ID=$COIN_FACTORY
FLASH_LOAN_POOL_USDC=$FLASH_LOAN_POOL
DEX_POOL_USDC_USDT=$DEX_POOL_USDC_USDT
DEX_POOL_USDT_WETH=$DEX_POOL_USDT_WETH
TWAP_ORACLE_USDC_USDT=$TWAP_ORACLE
EOF

echo ""
echo "==================================================================="
echo "✅ SETUP COMPLETE!"
echo "==================================================================="
echo "Coin Factory:        $COIN_FACTORY"
echo "Flash Loan Pool:     $FLASH_LOAN_POOL"
echo "DEX Pool USDC/USDT:  $DEX_POOL_USDC_USDT"
echo "DEX Pool USDT/WETH:  $DEX_POOL_USDT_WETH"
echo "TWAP Oracle:         $TWAP_ORACLE"
echo ""
echo "📝 Saved to .env.local - run: source .env.local"
echo "==================================================================="