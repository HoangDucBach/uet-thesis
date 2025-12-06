#!/bin/bash

# ============================================================================
# Scenario B: Price Manipulation Attack
# ============================================================================
#
# Large swap causing significant price impact (>10%)
#
# Attack Flow:
# 1. Execute large swap: 30,000 USDC → WETH
# 2. Price impact: ~20-30%
# 3. (Optional) Reverse swap to extract profit
#
# Expected Detection:
# - Flash Loan: NONE (no flash loan)
# - Price Manipulation: HIGH (significant price impact)
# - Sandwich: NONE (no victim)
# - Oracle Manipulation: NONE (no lending activity)
#
# ============================================================================

set -e

source ../contracts/setup.sh

echo ""
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║                                                                  ║"
echo "║        🎯 SCENARIO B: Price Manipulation Attack 🎯               ║"
echo "║                                                                  ║"
echo "║  Complexity:  MEDIUM                                             ║"
echo "║  Risk Level:  HIGH                                               ║"
echo "║  Protocols:   DEX                                                ║"
echo "║                                                                  ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""

ATTACKER=$ADMIN
SWAP_AMOUNT=30000000000000  # 30,000 USDC

echo "📋 Attack Parameters:"
echo "   Swap Amount:  30,000 USDC"
echo "   DEX Pool:     $DEX_POOL_USDC_WETH"
echo "   Expected Impact: 20-30%"
echo ""

# Get or mint USDC
USDC_COIN=$(sui client objects --json | jq -r ".[] | select(.data.type | contains(\"$USDC_TYPE\")) | .data.objectId" | head -1)

if [ -z "$USDC_COIN" ]; then
    echo "Minting USDC..."
    sui client call \
        --package "$PACKAGE_ID" \
        --module "usdc" \
        --function "mint" \
        --args "$USDC_TREASURY" "50000000000000" "$ATTACKER" \
        --gas-budget 10000000

    USDC_COIN=$(sui client objects --json | jq -r ".[] | select(.data.type | contains(\"$USDC_TYPE\")) | .data.objectId" | head -1)
fi

echo "🚀 Executing Large Swap (Price Manipulation)..."

# Execute large swap
sui client ptb \
    --split-coins @"$USDC_COIN" "[$SWAP_AMOUNT]" \
    --assign swap_coin \
    \
    --move-call "$PACKAGE_ID::simple_dex::swap_a_to_b<$USDC_TYPE,$PACKAGE_ID::weth::WETH>" \
        @"$DEX_POOL_USDC_WETH" swap_coin @0x6 \
    --assign weth_out \
    \
    --transfer-objects "[weth_out]" @"$ATTACKER" \
    \
    --gas-budget 50000000

echo ""
echo "✅ Price Manipulation Attack Completed!"
echo ""

echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║              EXPECTED DETECTION RESULTS                          ║"
echo "╠══════════════════════════════════════════════════════════════════╣"
echo "║                                                                  ║"
echo "║  [1] Price Manipulation Detector                                 ║"
echo "║      Risk Level: HIGH                                            ║"
echo "║      Reason: Large price impact (>20%)                           ║"
echo "║      Swap Amount: 30,000 USDC                                    ║"
echo "║      Impact: Significant liquidity drain                         ║"
echo "║                                                                  ║"
echo "║  Total Detections: 1 risk event                                  ║"
echo "║                                                                  ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""
