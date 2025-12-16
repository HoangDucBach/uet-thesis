#!/bin/bash

# Quick Attack Transaction Generator
# Generates various attack patterns for testing detection

set -e

# Load environment
source .env.local 2>/dev/null || true
export PACKAGE_ID="0x18f41d08c00001b0295bcbd810e600354a84eb48bc534fbea47fa318257af7e2"
export COIN_FACTORY_ID="0x171419b29291e35c0420b3a969c1507607daa2acd2411077ead0c7878746db16"
export USDC_TYPE="$PACKAGE_ID::usdc::USDC"
export USDT_TYPE="$PACKAGE_ID::usdt::USDT"

echo "╔════════════════════════════════════════════════════════════╗"
echo "║           ATTACK TRANSACTION GENERATOR                    ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Check required objects
if [ -z "$DEX_POOL_USDC_USDT" ]; then
    echo "❌ DEX_POOL_USDC_USDT not set!"
    echo "Run this first:"
    echo "export DEX_POOL_USDC_USDT='0xf2de8b782c69c4d614baa0de31400a9d4f839284806900703d6d2901c36447f5'"
    exit 1
fi

if [ -z "$FLASH_LOAN_POOL" ]; then
    echo "⚠ FLASH_LOAN_POOL not set. Need to create flash loan pool first."
    echo ""
    echo "Create it with:"
    echo "sui client ptb \\"
    echo "  --move-call \$PACKAGE_ID::coin_factory::mint_usdc @\$COIN_FACTORY_ID 10000000000 \\"
    echo "  --assign usdc \\"
    echo "  --move-call \"\$PACKAGE_ID::flash_loan_pool::create_pool<\$USDC_TYPE>\" usdc 9 \\"
    echo "  --gas-budget 100000000"
    echo ""
    read -p "Continue without flash loan pool? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

echo "Select attack type to generate:"
echo ""
echo "1. Simple Swap (No alert - baseline)"
echo "2. Large Swap - Price Impact (Medium risk)"
echo "3. Flash Loan + 2 Swaps Circular (High risk) ⭐"
echo "4. Flash Loan + Multiple Pools (Critical risk)"
echo ""
read -p "Choose [1-4]: " choice

case $choice in
    1)
        echo ""
        echo "═══════════════════════════════════════════════════════════"
        echo "TEST 1: Simple Swap (Baseline - No Alert Expected)"
        echo "═══════════════════════════════════════════════════════════"
        echo ""
        
        sui client ptb \
          --move-call $PACKAGE_ID::coin_factory::mint_usdc @$COIN_FACTORY_ID 100000000 \
          --assign usdc \
          --move-call "$PACKAGE_ID::simple_dex::swap_a_to_b<$USDC_TYPE,$USDT_TYPE>" \
            @$DEX_POOL_USDC_USDT usdc 0 \
          --assign usdt \
          --transfer-objects "[usdt]" @$(sui client active-address) \
          --gas-budget 100000000
        
        echo ""
        echo "✓ Small swap executed (100 USDC)"
        echo "✓ Expected: NO ALERT (normal trading)"
        ;;
        
    2)
        echo ""
        echo "═══════════════════════════════════════════════════════════"
        echo "TEST 2: Large Swap - High Price Impact"
        echo "═══════════════════════════════════════════════════════════"
        echo ""
        
        sui client ptb \
          --move-call $PACKAGE_ID::coin_factory::mint_usdc @$COIN_FACTORY_ID 500000000 \
          --assign usdc \
          --move-call "$PACKAGE_ID::simple_dex::swap_a_to_b<$USDC_TYPE,$USDT_TYPE>" \
            @$DEX_POOL_USDC_USDT usdc 0 \
          --assign usdt \
          --transfer-objects "[usdt]" @$(sui client active-address) \
          --gas-budget 100000000
        
        echo ""
        echo "✓ Large swap executed (500 USDC = 50% of pool)"
        echo "✓ Expected: MEDIUM/HIGH ALERT (price manipulation)"
        ;;
        
    3)
        echo ""
        echo "═══════════════════════════════════════════════════════════"
        echo "TEST 3: Flash Loan + Circular Arbitrage ⭐"
        echo "═══════════════════════════════════════════════════════════"
        echo ""
        
        if [ -z "$FLASH_LOAN_POOL" ]; then
            echo "❌ Flash loan pool required for this test!"
            exit 1
        fi
        
        sui client ptb \
          --move-call "$PACKAGE_ID::flash_loan_pool::borrow_flash_loan<$USDC_TYPE>" \
            @$FLASH_LOAN_POOL 400000000 \
          --assign borrowed \
          --assign receipt \
          --move-call "$PACKAGE_ID::simple_dex::swap_a_to_b<$USDC_TYPE,$USDT_TYPE>" \
            @$DEX_POOL_USDC_USDT borrowed 0 \
          --assign usdt \
          --move-call "$PACKAGE_ID::simple_dex::swap_b_to_a<$USDC_TYPE,$USDT_TYPE>" \
            @$DEX_POOL_USDC_USDT usdt 0 \
          --assign usdc_back \
          --move-call $PACKAGE_ID::coin_factory::mint_usdc \
            @$COIN_FACTORY_ID 360000 \
          --assign fee \
          --merge-coins usdc_back "[fee]" \
          --move-call "$PACKAGE_ID::flash_loan_pool::repay_flash_loan<$USDC_TYPE>" \
            @$FLASH_LOAN_POOL usdc_back receipt \
          --gas-budget 200000000
        
        echo ""
        echo "✓ Flash loan arbitrage executed"
        echo "✓ Pattern: Borrow 400 USDC → Swap → Swap → Repay"
        echo "✓ Circular trading: USDC → USDT → USDC"
        echo "✓ Expected: HIGH ALERT (flash loan attack)"
        ;;
        
    4)
        echo ""
        echo "═══════════════════════════════════════════════════════════"
        echo "TEST 4: Multi-Pool Flash Loan Attack"
        echo "═══════════════════════════════════════════════════════════"
        echo ""
        
        if [ -z "$FLASH_LOAN_POOL" ] || [ -z "$DEX_POOL_USDT_WETH" ]; then
            echo "❌ Need both flash loan pool and USDT/WETH pool!"
            exit 1
        fi
        
        # Complex: USDC → USDT → WETH → USDT → USDC (3 swaps, 2 pools)
        echo "⚠ Complex multi-pool attack - requires careful gas budget"
        echo "This test needs manual setup of proper pool states"
        echo "Recommended: Run Test 3 first to validate basic detection"
        ;;
        
    *)
        echo "Invalid choice!"
        exit 1
        ;;
esac

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "Now check indexer terminal for detection alerts!"
echo "Look for: 🚨 DETECTION ALERT"
echo "═══════════════════════════════════════════════════════════"

