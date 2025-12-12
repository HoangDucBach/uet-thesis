#!/bin/bash
set -e
source .env

ATTACKER=$(sui client active-address)
USDC_TYPE="$PACKAGE_ID::usdc::USDC"
WETH_TYPE="$PACKAGE_ID::weth::WETH"

# Scenario 1: Active Trader (Leverage Loop)
# Behavior: Supply Collateral -> Borrow Stablecoin -> Buy more Collateral -> Supply again
# Risk Level: Low because LTV is kept healthy (~2%) and swap impact is minimal

SUPPLY_AMOUNT=50000000000 # 50 WETH
BORROW_AMOUNT=10000000000 # 10,000 USDC

sui client ptb \
    --split-coins @$WETH_100M_ID "[$SUPPLY_AMOUNT]" \
    --assign weth_coin \
    --move-call "$PACKAGE_ID::compound_market::supply<$WETH_TYPE>" \
        @$MARKET_WETH weth_coin @0x6 \
    --assign position \
    --move-call "$PACKAGE_ID::compound_market::borrow<$WETH_TYPE, $USDC_TYPE>" \
        @$MARKET_WETH @$MARKET_USDC position @$DEX_POOL_WETH_USDC $BORROW_AMOUNT @0x6 \
    --assign usdc_loan \
    --move-call "$PACKAGE_ID::simple_dex::swap_b_to_a<$WETH_TYPE, $USDC_TYPE>" \
        @$DEX_POOL_WETH_USDC usdc_loan 0 \
    --assign weth_bought \
    --move-call "$PACKAGE_ID::compound_market::supply<$WETH_TYPE>" \
        @$MARKET_WETH weth_bought @0x6 \
    --assign position_2 \
    --transfer-objects "[position, position_2]" @$ATTACKER \
    --gas-budget 100000000 --json
