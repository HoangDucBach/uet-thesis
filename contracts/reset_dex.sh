#!/bin/bash
set -e
source .env

USDC_TYPE="${PACKAGE_ID}::usdc::USDC"
WETH_TYPE="${PACKAGE_ID}::weth::WETH"

# Mint initial liquidity for the pool
# 100,000 USDC and 10 WETH (Price ~ 10,000 USDC/ETH)
USDC_AMOUNT=100000000000
WETH_AMOUNT=10000000000

echo "Creating new DEX pool..."

RES=$(sui client ptb \
    --move-call "$PACKAGE_ID::coin_factory::mint_usdc" @$COIN_FACTORY_ID $USDC_AMOUNT \
    --assign usdc \
    --move-call "$PACKAGE_ID::coin_factory::mint_weth" @$COIN_FACTORY_ID $WETH_AMOUNT \
    --assign weth \
    --move-call "$PACKAGE_ID::simple_dex::create_pool<$WETH_TYPE, $USDC_TYPE>" \
        weth \
        usdc \
    --gas-budget 100000000 \
    --json)

POOL_ID=$(echo "$RES" | jq -r '.objectChanges[] | select(.objectType | contains("simple_dex::Pool")) | .objectId')

if [ -z "$POOL_ID" ] || [ "$POOL_ID" == "null" ]; then
    echo "Failed to create pool"
    echo "$RES"
    exit 1
fi

echo "Created DEX Pool: $POOL_ID"

# Update .env
if grep -q "DEX_POOL_WETH_USDC=" .env; then
    sed -i '' "s/DEX_POOL_WETH_USDC=.*/DEX_POOL_WETH_USDC=$POOL_ID/" .env
else
    echo "DEX_POOL_WETH_USDC=$POOL_ID" >> .env
fi

echo "Updated .env with new DEX_POOL_WETH_USDC"
