#!/bin/bash

# ============================================================================
# Scenario A: Basic Flash Loan Attack (Simple)
# ============================================================================
#
# This is the SIMPLEST attack scenario - pure flash loan with immediate repay
#
# Attack Flow:
# 1. Borrow 50,000 USDC from flash loan pool
# 2. (Optionally perform some operations with the loan)
# 3. Repay flash loan + fee in same transaction
#
# Expected Detection:
# - Flash Loan Detector: HIGH (flash loan present)
# - Price Manipulation: NONE (no large swaps)
# - Sandwich: NONE (no victim)
# - Oracle Manipulation: NONE (no lending activity)
#
# ============================================================================

set -e

source ../contracts/setup.sh

echo ""
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║                                                                  ║"
echo "║           🎯 SCENARIO A: Basic Flash Loan Attack 🎯              ║"
echo "║                                                                  ║"
echo "║  Complexity:  LOW                                                ║"
echo "║  Risk Level:  HIGH                                               ║"
echo "║  Protocols:   Flash Loan                                         ║"
echo "║                                                                  ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""

ATTACKER=$ADMIN
FLASH_LOAN_AMOUNT=50000000000000  # 50,000 USDC

echo "📋 Attack Parameters:"
echo "   Flash Loan Amount: 50,000 USDC"
echo "   Flash Loan Pool:   $FLASH_LOAN_POOL"
echo "   Fee Rate:          0.09% (9 bps)"
echo ""

echo "🚀 Executing Basic Flash Loan..."

# Execute flash loan borrow + repay in single transaction
sui client ptb \
    --move-call "$PACKAGE_ID::flash_loan_pool::borrow<$USDC_TYPE>" \
        @"$FLASH_LOAN_POOL" "$FLASH_LOAN_AMOUNT" \
    --assign flash_result \
    \
    --assign loan_coin flash_result.0 \
    --assign receipt flash_result.1 \
    \
    --move-call "$PACKAGE_ID::flash_loan_pool::repay<$USDC_TYPE>" \
        @"$FLASH_LOAN_POOL" loan_coin receipt \
    \
    --gas-budget 50000000

echo ""
echo "✅ Flash Loan Attack Completed!"
echo ""

echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║              EXPECTED DETECTION RESULTS                          ║"
echo "╠══════════════════════════════════════════════════════════════════╣"
echo "║                                                                  ║"
echo "║  [1] Flash Loan Detector                                         ║"
echo "║      Risk Level: HIGH                                            ║"
echo "║      Reason: Flash loan detected (50k USDC)                      ║"
echo "║      Signals: Borrow + Repay in same transaction                 ║"
echo "║                                                                  ║"
echo "║  Total Detections: 1 risk event                                  ║"
echo "║                                                                  ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""
