#!/bin/bash
set -e
source .env

POOL_ID=$DEX_POOL_WETH_USDC
TOKEN_A="$PACKAGE_ID::weth::WETH"
TOKEN_B="$PACKAGE_ID::usdc::USDC"
# Current LP Supply is ~7.7B (7722556505)
LP_TO_REMOVE=7700000000

sui client ptb \
    --move-call "$PACKAGE_ID::simple_dex::remove_liquidity<$TOKEN_A, $TOKEN_B>" \
        @$POOL_ID \
        $LP_TO_REMOVE \
        0 \
        0 \
    --assign res \
    --assign coin_a res.0 \
    --assign coin_b res.1 \
    --transfer-objects "[coin_a, coin_b]" @$(sui client active-address) \
    --gas-budget 50000000 --json