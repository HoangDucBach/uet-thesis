#!/bin/bash

# ============================================================================
# Run DeFi Protocol Scenario
# ============================================================================

set -e

echo "🚀 Starting DeFi Protocol Scenario Setup..."
echo ""

# Step 1: Load environment variables
echo "📋 Step 1: Loading environment variables..."
source .env
source setup.sh
echo "✓ Environment loaded!"
echo "  - Package ID: $PACKAGE_ID"
echo "  - Active Address: $ADMIN"
echo ""

# Step 2: Verify package exists
echo "📦 Step 2: Verifying package deployment..."
if [ "$PACKAGE_ID" = "0x0" ] || [ -z "$PACKAGE_ID" ]; then
    echo "❌ Error: Package not deployed. Please run: ./publish.sh"
    exit 1
fi
echo "✓ Package verified: $PACKAGE_ID"
echo ""

# Step 3: Check if shared objects exist
echo "🔍 Step 3: Checking shared objects..."
if [ -z "$COIN_FACTORY_ID" ]; then
    echo "⚠️  Warning: COIN_FACTORY_ID not found. Creating shared objects..."
    bash create_shared_objects.sh
else
    echo "✓ Coin Factory: $COIN_FACTORY_ID"
fi

if [ -z "$DEX_POOL_USDC_USDT" ]; then
    echo "⚠️  Warning: DEX pools not found. Creating pools..."
    bash create_shared_objects.sh
else
    echo "✓ DEX Pool USDC/USDT: $DEX_POOL_USDC_USDT"
fi
echo ""

# Step 4: Mint tokens (100 million each)
echo "💰 Step 4: Minting tokens (100 million each)..."
echo "  - USDC: 100,000,000 (6 decimals = 100_000_000_000_000)"
echo "  - USDT: 100,000,000 (6 decimals = 100_000_000_000_000)"
echo "  - WETH: 100,000,000 (8 decimals = 10_000_000_000_000_000)"
echo "  - BTC: 100,000,000 (8 decimals = 10_000_000_000_000_000)"
echo "  - SUI: 100,000,000 (9 decimals = 100_000_000_000_000_000)"
echo ""

# Mint USDC (100M with 6 decimals = 100_000_000_000_000)
echo "Minting USDC (100M)..."
sui client call \
  --package $PACKAGE_ID \
  --module coin_factory \
  --function mint_usdc \
  --args @$COIN_FACTORY_ID 100000000000000 \
  --gas-budget 10000000

# Mint USDT (100M with 6 decimals = 100_000_000_000_000)
echo "Minting USDT (100M)..."
sui client call \
  --package $PACKAGE_ID \
  --module coin_factory \
  --function mint_usdt \
  --args @$COIN_FACTORY_ID 100000000000000 \
  --gas-budget 10000000

# Mint WETH (100M with 8 decimals = 10_000_000_000_000_000)
echo "Minting WETH (100M)..."
sui client call \
  --package $PACKAGE_ID \
  --module coin_factory \
  --function mint_weth \
  --args @$COIN_FACTORY_ID 10000000000000000 \
  --gas-budget 10000000

# Mint BTC (100M with 8 decimals = 10_000_000_000_000_000)
echo "Minting BTC (100M)..."
sui client call \
  --package $PACKAGE_ID \
  --module coin_factory \
  --function mint_btc \
  --args @$COIN_FACTORY_ID 10000000000000000 \
  --gas-budget 10000000

# Mint SUI_COIN (100M with 9 decimals = 100_000_000_000_000_000)
echo "Minting SUI_COIN (100M)..."
sui client call \
  --package $PACKAGE_ID \
  --module coin_factory \
  --function mint_sui_coin \
  --args @$COIN_FACTORY_ID 100000000000000000 \
  --gas-budget 10000000

echo "✓ All tokens minted!"
echo ""

# Step 5: Verify objects
echo "✅ Step 5: Scenario ready!"
echo ""
echo "📊 Summary:"
echo "  - Package: $PACKAGE_ID"
echo "  - Coin Factory: $COIN_FACTORY_ID"
if [ ! -z "$DEX_POOL_USDC_USDT" ]; then
    echo "  - DEX Pool USDC/USDT: $DEX_POOL_USDC_USDT"
fi
if [ ! -z "$DEX_POOL_USDT_WETH" ]; then
    echo "  - DEX Pool USDT/WETH: $DEX_POOL_USDT_WETH"
fi
if [ ! -z "$MARKET_USDC" ]; then
    echo "  - Market USDC: $MARKET_USDC"
fi
echo ""
echo "🎉 Scenario setup complete! You can now interact with the protocol."
echo ""
echo "💡 Next steps:"
echo "  1. Check your token balances: sui client objects $ADMIN"
echo "  2. View pools: sui client object $DEX_POOL_USDC_USDT"
echo "  3. Start trading/swapping tokens!"

