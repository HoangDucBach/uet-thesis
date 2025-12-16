#!/bin/bash

# Source environment variables
source .env

# Get active address
SENDER=$(sui client active-address)
echo "Active address: $SENDER"

# Amount to supply: 5M USDC
# USDC has 6 decimals
# 5,000,000 * 10^6 = 5,000,000,000,000
AMOUNT=5000000000000

echo "Splitting $AMOUNT raw units (5M USDC) from $USDC_100M_ID..."
echo "Supplying to Market $MARKET_USDC..."

sui client ptb \
    --move-call "0x2::coin::split<$PACKAGE_ID::usdc::USDC>" @$USDC_100M_ID 5000000000000 \
    --assign coin_to_supply \
    --move-call "$PACKAGE_ID::compound_market::supply<$PACKAGE_ID::usdc::USDC>" \
        @$MARKET_USDC \
        coin_to_supply \
        @0x6 \
    --assign position \
    --transfer-objects "[position]" @$SENDER \
    --gas-budget 100000000

echo "Done."
