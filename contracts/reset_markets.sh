#!/bin/bash
set -e
source .env

USDC_TYPE="${PACKAGE_ID}::usdc::USDC"
WETH_TYPE="${PACKAGE_ID}::weth::WETH"

USDC_MINT_AMOUNT=100000000000
COLLATERAL_FACTOR=7500
RESERVE_FACTOR=1000

RES_USDC=$(sui client ptb \
    --move-call "$PACKAGE_ID::coin_factory::mint_usdc" @$COIN_FACTORY_ID $USDC_MINT_AMOUNT \
    --assign usdc_coin \
    --move-call "$PACKAGE_ID::compound_market::create_market<$USDC_TYPE>" \
        usdc_coin \
        @$DEX_POOL_WETH_USDC \
        $COLLATERAL_FACTOR \
        $RESERVE_FACTOR \
        @0x6 \
    --assign market \
    --move-call "0x2::transfer::public_share_object<$PACKAGE_ID::compound_market::Market<$USDC_TYPE>>" market \
    --gas-budget 100000000 \
    --json)

NEW_MARKET_USDC=$(echo "$RES_USDC" | jq -r '.objectChanges[] | select(.objectType | contains("compound_market::Market") and contains("usdc::USDC")) | .objectId')

if [ -z "$NEW_MARKET_USDC" ] || [ "$NEW_MARKET_USDC" == "null" ]; then
    exit 1
fi

WETH_MINT_AMOUNT=10000000000

RES_WETH=$(sui client ptb \
    --move-call "$PACKAGE_ID::coin_factory::mint_weth" @$COIN_FACTORY_ID $WETH_MINT_AMOUNT \
    --assign weth_coin \
    --move-call "$PACKAGE_ID::compound_market::create_market<$WETH_TYPE>" \
        weth_coin \
        @$DEX_POOL_WETH_USDC \
        $COLLATERAL_FACTOR \
        $RESERVE_FACTOR \
        @0x6 \
    --assign market \
    --move-call "0x2::transfer::public_share_object<$PACKAGE_ID::compound_market::Market<$WETH_TYPE>>" market \
    --gas-budget 100000000 \
    --json)

NEW_MARKET_WETH=$(echo "$RES_WETH" | jq -r '.objectChanges[] | select(.objectType | contains("compound_market::Market") and contains("weth::WETH")) | .objectId')

if [ -z "$NEW_MARKET_WETH" ] || [ "$NEW_MARKET_WETH" == "null" ]; then
    exit 1
fi

if grep -q "MARKET_USDC=" .env; then
    sed -i '' "s/MARKET_USDC=.*/MARKET_USDC=$NEW_MARKET_USDC/" .env
else
    echo "MARKET_USDC=$NEW_MARKET_USDC" >> .env
fi

if grep -q "MARKET_WETH=" .env; then
    sed -i '' "s/MARKET_WETH=.*/MARKET_WETH=$NEW_MARKET_WETH/" .env
else
    echo "MARKET_WETH=$NEW_MARKET_WETH" >> .env
fi
