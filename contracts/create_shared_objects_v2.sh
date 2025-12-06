#!/bin/bash

# ============================================================================
# Create Shared Objects (Enhanced Version)
# ============================================================================
#
# This script creates all necessary shared objects for the DeFi protocol
# and automatically captures their object IDs.
#
# Objects Created:
# 1. DEX Pools (USDC/USDT, USDT/WETH, etc.)
# 2. Flash Loan Pools (USDC)
# 3. TWAP Oracles
# 4. Lending Markets (USDC, WETH)
#
# ============================================================================

set -e

# Load environment
source .env

PACKAGE_ID=$SIMULATION_PACKAGE_ID
SENDER=$(sui client active-address)

echo ""
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║                                                                  ║"
echo "║           🏗️  CREATING SHARED OBJECTS 🏗️                         ║"
echo "║                                                                  ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""

echo "📋 Configuration:"
echo "   Package ID: $PACKAGE_ID"
echo "   Sender:     $SENDER"
echo ""

# ============================================================================
# Step 1: Mint initial coins
# ============================================================================

echo "💰 Step 1: Minting initial coins..."

# Mint USDC
echo "   Minting USDC..."
TX_USDC=$(sui client call \
    --package "$PACKAGE_ID" \
    --module "usdc" \
    --function "mint" \
    --args "$USDC_TREASURY_CAP" "1000000000000000" "$SENDER" \
    --gas-budget 10000000 \
    --json)

# Mint USDT
echo "   Minting USDT..."
TX_USDT=$(sui client call \
    --package "$PACKAGE_ID" \
    --module "usdt" \
    --function "mint" \
    --args "$USDT_TREASURY_CAP" "1000000000000000" "$SENDER" \
    --gas-budget 10000000 \
    --json)

# Mint WETH
echo "   Minting WETH..."
TX_WETH=$(sui client call \
    --package "$PACKAGE_ID" \
    --module "weth" \
    --function "mint" \
    --args "$WETH_TREASURY_CAP" "1000000000000000" "$SENDER" \
    --gas-budget 10000000 \
    --json)

sleep 2

# Get minted coin objects
USDC_COIN=$(sui client objects --json | jq -r ".[] | select(.data.type | contains(\"$PACKAGE_ID::usdc::USDC\")) | .data.objectId" | head -1)
USDT_COIN=$(sui client objects --json | jq -r ".[] | select(.data.type | contains(\"$PACKAGE_ID::usdt::USDT\")) | .data.objectId" | head -1)
WETH_COIN=$(sui client objects --json | jq -r ".[] | select(.data.type | contains(\"$PACKAGE_ID::weth::WETH\")) | .data.objectId" | head -1)

echo "   ✓ USDC: $USDC_COIN"
echo "   ✓ USDT: $USDT_COIN"
echo "   ✓ WETH: $WETH_COIN"
echo ""

# ============================================================================
# Step 2: Create DEX Pools
# ============================================================================

echo "🔄 Step 2: Creating DEX Pools..."

# Create USDC/USDT Pool
echo "   Creating USDC/USDT pool..."
TX_POOL_1=$(sui client ptb \
    --split-coins @"$USDC_COIN" "[500000000000000]" --assign usdc_split \
    --split-coins @"$USDT_COIN" "[500000000000000]" --assign usdt_split \
    --move-call "$PACKAGE_ID::simple_dex::create_pool<$PACKAGE_ID::usdc::USDC,$PACKAGE_ID::usdt::USDT>" usdc_split usdt_split \
    --gas-budget 50000000 \
    --json)

sleep 2

# Get pool ID
DEX_POOL_USDC_USDT=$(echo "$TX_POOL_1" | jq -r '.objectChanges[] | select(.objectType | contains("Pool")) | .objectId' | head -1)

if [ -z "$DEX_POOL_USDC_USDT" ]; then
    echo "   ❌ Failed to create USDC/USDT pool"
    exit 1
fi

echo "   ✓ USDC/USDT Pool: $DEX_POOL_USDC_USDT"

# Create USDT/WETH Pool
echo "   Creating USDT/WETH pool..."
TX_POOL_2=$(sui client ptb \
    --split-coins @"$USDT_COIN" "[300000000000000]" --assign usdt_split \
    --split-coins @"$WETH_COIN" "[300000000000000]" --assign weth_split \
    --move-call "$PACKAGE_ID::simple_dex::create_pool<$PACKAGE_ID::usdt::USDT,$PACKAGE_ID::weth::WETH>" usdt_split weth_split \
    --gas-budget 50000000 \
    --json)

sleep 2

DEX_POOL_USDT_WETH=$(echo "$TX_POOL_2" | jq -r '.objectChanges[] | select(.objectType | contains("Pool")) | .objectId' | head -1)
echo "   ✓ USDT/WETH Pool: $DEX_POOL_USDT_WETH"

# Create USDC/WETH Pool (for oracle manipulation)
echo "   Creating USDC/WETH pool..."
TX_POOL_3=$(sui client ptb \
    --split-coins @"$USDC_COIN" "[200000000000000]" --assign usdc_split \
    --split-coins @"$WETH_COIN" "[200000000000000]" --assign weth_split \
    --move-call "$PACKAGE_ID::simple_dex::create_pool<$PACKAGE_ID::usdc::USDC,$PACKAGE_ID::weth::WETH>" usdc_split weth_split \
    --gas-budget 50000000 \
    --json)

sleep 2

DEX_POOL_USDC_WETH=$(echo "$TX_POOL_3" | jq -r '.objectChanges[] | select(.objectType | contains("Pool")) | .objectId' | head -1)
echo "   ✓ USDC/WETH Pool: $DEX_POOL_USDC_WETH"
echo ""

# ============================================================================
# Step 3: Create Flash Loan Pool
# ============================================================================

echo "⚡ Step 3: Creating Flash Loan Pool..."

TX_FLASH=$(sui client ptb \
    --split-coins @"$USDC_COIN" "[100000000000000]" --assign usdc_split \
    --move-call "$PACKAGE_ID::flash_loan_pool::create_pool<$PACKAGE_ID::usdc::USDC>" usdc_split 9 \
    --gas-budget 50000000 \
    --json)

sleep 2

FLASH_LOAN_POOL=$(echo "$TX_FLASH" | jq -r '.objectChanges[] | select(.objectType | contains("FlashLoanPool")) | .objectId' | head -1)
echo "   ✓ Flash Loan Pool: $FLASH_LOAN_POOL"
echo ""

# ============================================================================
# Step 4: Create TWAP Oracle
# ============================================================================

echo "📊 Step 4: Creating TWAP Oracle..."

TX_ORACLE=$(sui client call \
    --package "$PACKAGE_ID" \
    --module "twap_oracle" \
    --function "create_oracle" \
    --type-args "$PACKAGE_ID::usdc::USDC" "$PACKAGE_ID::weth::WETH" \
    --args "$DEX_POOL_USDC_WETH" 1800000 60000 \
    --gas-budget 50000000 \
    --json)

sleep 2

TWAP_ORACLE=$(echo "$TX_ORACLE" | jq -r '.objectChanges[] | select(.objectType | contains("TWAPOracle")) | .objectId' | head -1)
echo "   ✓ TWAP Oracle: $TWAP_ORACLE"
echo ""

# ============================================================================
# Step 5: Create Lending Markets
# ============================================================================

echo "🏦 Step 5: Creating Lending Markets..."

# Create USDC Market
echo "   Creating USDC lending market..."
TX_LENDING_USDC=$(sui client ptb \
    --split-coins @"$USDC_COIN" "[200000000000000]" --assign usdc_split \
    --move-call "$PACKAGE_ID::compound_market::create_market<$PACKAGE_ID::usdc::USDC>" usdc_split @"$DEX_POOL_USDC_WETH" 7500 1000 @0x6 \
    --assign market \
    --move-call "0x2::transfer::public_share_object<$PACKAGE_ID::compound_market::Market<$PACKAGE_ID::usdc::USDC>>" market \
    --gas-budget 100000000 \
    --json)

sleep 2

LENDING_MARKET_USDC=$(echo "$TX_LENDING_USDC" | jq -r '.objectChanges[] | select(.objectType | contains("Market")) | .objectId' | head -1)
echo "   ✓ USDC Market: $LENDING_MARKET_USDC"

# Create WETH Market
echo "   Creating WETH lending market..."
TX_LENDING_WETH=$(sui client ptb \
    --split-coins @"$WETH_COIN" "[100000000000000]" --assign weth_split \
    --move-call "$PACKAGE_ID::compound_market::create_market<$PACKAGE_ID::weth::WETH>" weth_split @"$DEX_POOL_USDT_WETH" 7500 1000 @0x6 \
    --assign market \
    --move-call "0x2::transfer::public_share_object<$PACKAGE_ID::compound_market::Market<$PACKAGE_ID::weth::WETH>>" market \
    --gas-budget 100000000 \
    --json)

sleep 2

LENDING_MARKET_WETH=$(echo "$TX_LENDING_WETH" | jq -r '.objectChanges[] | select(.objectType | contains("Market")) | .objectId' | head -1)
echo "   ✓ WETH Market: $LENDING_MARKET_WETH"
echo ""

# ============================================================================
# Step 6: Save to setup.sh
# ============================================================================

echo "💾 Step 6: Saving object IDs to setup.sh..."

cat > setup.sh <<EOF
#!/bin/bash

# ============================================================================
# Environment Setup - Auto-generated
# ============================================================================

# Package & Upgrade
export PACKAGE_ID="$PACKAGE_ID"
export UPGRADE_CAP="$UPGRADE_CAP"

# Treasury Caps
export BTC_TREASURY="$BTC_TREASURY_CAP"
export USDC_TREASURY="$USDC_TREASURY_CAP"
export USDT_TREASURY="$USDT_TREASURY_CAP"
export WETH_TREASURY="$WETH_TREASURY_CAP"
export SUI_TREASURY="$SUI_COIN_TREASURY_CAP"

# Coin Metadata
export BTC_META="$BTC_METADATA"
export USDC_META="$USDC_METADATA"
export USDT_META="$USDT_METADATA"
export WETH_META="$WETH_METADATA"
export SUI_META="$SUI_COIN_METADATA"

# Coin Types
export USDC_TYPE="$PACKAGE_ID::usdc::USDC"
export USDT_TYPE="$PACKAGE_ID::usdt::USDT"
export WETH_TYPE="$PACKAGE_ID::weth::WETH"
export BTC_TYPE="$PACKAGE_ID::btc::BTC"
export SUI_TYPE="$PACKAGE_ID::sui_coin::SUI_COIN"

# Shared Objects
export DEX_POOL_USDC_USDT="$DEX_POOL_USDC_USDT"
export DEX_POOL_USDT_WETH="$DEX_POOL_USDT_WETH"
export DEX_POOL_USDC_WETH="$DEX_POOL_USDC_WETH"
export FLASH_LOAN_POOL="$FLASH_LOAN_POOL"
export TWAP_ORACLE="$TWAP_ORACLE"
export LENDING_MARKET_USDC="$LENDING_MARKET_USDC"
export LENDING_MARKET_WETH="$LENDING_MARKET_WETH"

# Wallet
export ADMIN=$(sui client active-address)

echo "✓ Environment variables loaded!"
echo "  Package:     \$PACKAGE_ID"
echo "  DEX Pools:   3"
echo "  Flash Loan:  \$FLASH_LOAN_POOL"
echo "  Lending:     2 markets"
EOF

chmod +x setup.sh

echo "   ✓ Saved to setup.sh"
echo ""

# ============================================================================
# Summary
# ============================================================================

echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║                                                                  ║"
echo "║              ✅ ALL SHARED OBJECTS CREATED ✅                     ║"
echo "║                                                                  ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""

echo "📊 Summary:"
echo ""
echo "   DEX Pools:"
echo "     • USDC/USDT:  $DEX_POOL_USDC_USDT"
echo "     • USDT/WETH:  $DEX_POOL_USDT_WETH"
echo "     • USDC/WETH:  $DEX_POOL_USDC_WETH"
echo ""
echo "   Flash Loan:"
echo "     • USDC Pool:  $FLASH_LOAN_POOL"
echo ""
echo "   Oracle:"
echo "     • TWAP:       $TWAP_ORACLE"
echo ""
echo "   Lending Markets:"
echo "     • USDC:       $LENDING_MARKET_USDC"
echo "     • WETH:       $LENDING_MARKET_WETH"
echo ""

echo "✅ Ready for attack scenarios!"
echo ""
echo "Next steps:"
echo "   1. Source the environment: source setup.sh"
echo "   2. Run scenarios: cd ../sui-indexer/scenarios && ./run_all_scenarios.sh"
echo ""
