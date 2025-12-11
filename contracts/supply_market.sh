#!/bin/bash
set -e

source .env

USDC_TYPE="${PACKAGE_ID}::usdc::USDC"
WETH_TYPE="${PACKAGE_ID}::weth::WETH"

USDC_SUPPLY_AMOUNT=10000000000000

sui client ptb \
    --move-call "$PACKAGE_ID::coin_factory::mint_usdc" @$COIN_FACTORY_ID $USDC_SUPPLY_AMOUNT \
    --assign usdc_coin \
    --move-call "$PACKAGE_ID::compound_market::supply<$USDC_TYPE>" \
        @$MARKET_USDC \
        usdc_coin \
        @0x6 \
    --assign position \
    --transfer-objects "[position]" @$(sui client active-address) \
    --gas-budget 100000000 \
    --json

WETH_SUPPLY_AMOUNT=100000000000

sui client ptb \
    --move-call "$PACKAGE_ID::coin_factory::mint_weth" @$COIN_FACTORY_ID $WETH_SUPPLY_AMOUNT \
    --assign weth_coin \
    --move-call "$PACKAGE_ID::compound_market::supply<$WETH_TYPE>" \
        @$MARKET_WETH \
        weth_coin \
        @0x6 \
    --assign position \
    --transfer-objects "[position]" @$(sui client active-address) \
    --gas-budget 100000000 \
    --json
