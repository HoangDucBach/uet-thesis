#!/bin/bash

# Test Detection System (without database storage)
# Focus on detection logic only

set -e

echo "╔════════════════════════════════════════════════════════════╗"
echo "║           DETECTION TESTING MODE                          ║"
echo "║  Database/ES storage DISABLED for performance             ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Load environment
if [ -f .env.local ]; then
    source .env.local
    echo "✓ Loaded .env.local"
else
    echo "⚠ .env.local not found - using .env only"
fi

# Export from .env
export PACKAGE_ID="0x18f41d08c00001b0295bcbd810e600354a84eb48bc534fbea47fa318257af7e2"
export COIN_FACTORY_ID="0x171419b29291e35c0420b3a969c1507607daa2acd2411077ead0c7878746db16"
export USDC_TYPE="$PACKAGE_ID::usdc::USDC"
export USDT_TYPE="$PACKAGE_ID::usdt::USDT"

echo ""
echo "Package ID:  $PACKAGE_ID"
echo "Factory ID:  $COIN_FACTORY_ID"
echo ""

# Check if indexer is running
if pgrep -f "sui-indexer" > /dev/null; then
    echo "⚠ Indexer is already running. Stop it first with:"
    echo "   pkill -f sui-indexer"
    echo ""
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

echo "═══════════════════════════════════════════════════════════"
echo "Starting indexer in DETECTION TEST MODE..."
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "Watch for these markers:"
echo "  🎯 = Transaction from target package detected"
echo "  🚨 = Risk event alert triggered"
echo "  📋 = Event details"
echo ""
echo "Press Ctrl+C to stop"
echo ""

# Start indexer with logging
RUST_LOG=info cargo run --release 2>&1 | grep -E "🎯|🚨|📋|🔍|Risk|ALERT|Checkpoint|Connected" --color=always


