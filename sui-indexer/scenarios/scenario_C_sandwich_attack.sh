#!/bin/bash

# ============================================================================
# Scenario C: Sandwich Attack
# ============================================================================
#
# Classic MEV sandwich attack pattern
#
# Transaction Sequence:
# 1. Attacker front-run: Buy WETH with USDC (pump price)
# 2. Victim transaction: Buy WETH with USDC (pays inflated price)
# 3. Attacker back-run: Sell WETH for USDC (profit from price difference)
#
# Expected Detection:
# - Flash Loan: NONE (no flash loan)
# - Price Manipulation: MEDIUM (front-run swap has price impact)
# - Sandwich: HIGH (temporal correlation detected)
# - Oracle Manipulation: NONE (no lending activity)
#
# ============================================================================

set -e

source ../contracts/setup.sh

echo ""
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║                                                                  ║"
echo "║           🎯 SCENARIO C: Sandwich Attack 🎯                      ║"
echo "║                                                                  ║"
echo "║  Complexity:  MEDIUM                                             ║"
echo "║  Risk Level:  HIGH                                               ║"
echo "║  Protocols:   DEX (MEV)                                          ║"
echo "║                                                                  ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""

ATTACKER=$ADMIN
VICTIM=$ADMIN  # In real scenario, would be different address

FRONTRUN_AMOUNT=20000000000000  # 20,000 USDC
VICTIM_AMOUNT=5000000000000     # 5,000 USDC
BACKRUN_WETH=10000000000        # ~10 WETH

echo "📋 Attack Parameters:"
echo "   Attacker:        $ATTACKER"
echo "   Victim:          $VICTIM"
echo "   Front-run:       20,000 USDC → WETH"
echo "   Victim swap:     5,000 USDC → WETH"
echo "   Back-run:        ~10 WETH → USDC"
echo ""

# Get USDC for attacker
USDC_COIN=$(sui client objects --json | jq -r ".[] | select(.data.type | contains(\"$USDC_TYPE\")) | .data.objectId" | head -1)

if [ -z "$USDC_COIN" ]; then
    echo "Minting USDC for attacker..."
    sui client call \
        --package "$PACKAGE_ID" \
        --module "usdc" \
        --function "mint" \
        --args "$USDC_TREASURY" "50000000000000" "$ATTACKER" \
        --gas-budget 10000000

    USDC_COIN=$(sui client objects --json | jq -r ".[] | select(.data.type | contains(\"$USDC_TYPE\")) | .data.objectId" | head -1)
fi

# ============================================================================
# STEP 1: Front-run (Attacker buys WETH, pumps price)
# ============================================================================

echo "🚀 Step 1: Front-run (Attacker buys WETH)..."

sui client ptb \
    --split-coins @"$USDC_COIN" "[$FRONTRUN_AMOUNT]" \
    --assign frontrun_coin \
    \
    --move-call "$PACKAGE_ID::simple_dex::swap_a_to_b<$USDC_TYPE,$PACKAGE_ID::weth::WETH>" \
        @"$DEX_POOL_USDC_WETH" frontrun_coin @0x6 \
    --assign weth_out \
    \
    --transfer-objects "[weth_out]" @"$ATTACKER" \
    \
    --gas-budget 50000000

sleep 2

# ============================================================================
# STEP 2: Victim transaction (buys at inflated price)
# ============================================================================

echo "👤 Step 2: Victim transaction (buys WETH at inflated price)..."

# Get fresh USDC coin
USDC_COIN_2=$(sui client objects --json | jq -r ".[] | select(.data.type | contains(\"$USDC_TYPE\")) | .data.objectId" | head -1)

if [ -z "$USDC_COIN_2" ]; then
    echo "Minting USDC for victim..."
    sui client call \
        --package "$PACKAGE_ID" \
        --module "usdc" \
        --function "mint" \
        --args "$USDC_TREASURY" "10000000000000" "$VICTIM" \
        --gas-budget 10000000

    USDC_COIN_2=$(sui client objects --json | jq -r ".[] | select(.data.type | contains(\"$USDC_TYPE\")) | .data.objectId" | head -1)
fi

sui client ptb \
    --split-coins @"$USDC_COIN_2" "[$VICTIM_AMOUNT]" \
    --assign victim_coin \
    \
    --move-call "$PACKAGE_ID::simple_dex::swap_a_to_b<$USDC_TYPE,$PACKAGE_ID::weth::WETH>" \
        @"$DEX_POOL_USDC_WETH" victim_coin @0x6 \
    --assign victim_weth \
    \
    --transfer-objects "[victim_weth]" @"$VICTIM" \
    \
    --gas-budget 50000000

sleep 2

# ============================================================================
# STEP 3: Back-run (Attacker sells WETH, profits)
# ============================================================================

echo "💰 Step 3: Back-run (Attacker sells WETH for profit)..."

# Get WETH from front-run
WETH_COIN=$(sui client objects --json | jq -r ".[] | select(.data.type | contains(\"$PACKAGE_ID::weth::WETH\")) | .data.objectId" | head -1)

if [ -n "$WETH_COIN" ]; then
    sui client ptb \
        --split-coins @"$WETH_COIN" "[$BACKRUN_WETH]" \
        --assign backrun_coin \
        \
        --move-call "$PACKAGE_ID::simple_dex::swap_b_to_a<$USDC_TYPE,$PACKAGE_ID::weth::WETH>" \
            @"$DEX_POOL_USDC_WETH" backrun_coin @0x6 \
        --assign usdc_profit \
        \
        --transfer-objects "[usdc_profit]" @"$ATTACKER" \
        \
        --gas-budget 50000000
else
    echo "⚠️ Warning: WETH coin not found for back-run (may need to wait)"
fi

echo ""
echo "✅ Sandwich Attack Sequence Completed!"
echo ""

echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║              EXPECTED DETECTION RESULTS                          ║"
echo "╠══════════════════════════════════════════════════════════════════╣"
echo "║                                                                  ║"
echo "║  [1] Price Manipulation Detector                                 ║"
echo "║      Risk Level: MEDIUM                                          ║"
echo "║      Reason: Front-run swap with price impact                    ║"
echo "║                                                                  ║"
echo "║  [2] Sandwich Attack Detector                                    ║"
echo "║      Risk Level: HIGH                                            ║"
echo "║      Signals:                                                    ║"
echo "║        ✓ Large buy before victim (front-run)                     ║"
echo "║        ✓ Victim transaction (worse price)                        ║"
echo "║        ✓ Large sell after victim (back-run)                      ║"
echo "║        ✓ Temporal correlation (within blocks)                    ║"
echo "║        ✓ Same attacker address                                   ║"
echo "║                                                                  ║"
echo "║  Total Detections: 2 risk events                                 ║"
echo "║                                                                  ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""

echo "💡 Note: Sandwich detection requires analyzing multiple transactions"
echo "   across sequential blocks. Check indexer logs for pattern matching."
echo ""
