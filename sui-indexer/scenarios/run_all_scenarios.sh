#!/bin/bash

# ============================================================================
# Master Script: Run All Attack Scenarios
# ============================================================================
#
# Executes all 6 attack scenarios in sequence and collects detection metrics
#
# ============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo ""
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║                                                                  ║"
echo "║        🎯 RUNNING ALL ATTACK SCENARIOS 🎯                        ║"
echo "║                                                                  ║"
echo "║  This will execute 6 different attack scenarios to test         ║"
echo "║  the 4-layer detection system comprehensively.                   ║"
echo "║                                                                  ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""

# Check if sui-indexer is running
if ! pgrep -f "sui-indexer" > /dev/null; then
    echo "⚠️  WARNING: sui-indexer is not running!"
    echo "   Start it first to see detection results:"
    echo "   cd sui-indexer && cargo run --release"
    echo ""
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# ============================================================================
# Run Scenarios
# ============================================================================

TOTAL_SCENARIOS=4
CURRENT=0

run_scenario() {
    local scenario_file=$1
    local scenario_name=$2

    CURRENT=$((CURRENT + 1))

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  [$CURRENT/$TOTAL_SCENARIOS] $scenario_name"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    if [ -f "$scenario_file" ]; then
        chmod +x "$scenario_file"
        "$scenario_file"

        echo ""
        echo "⏳ Waiting 5 seconds for indexer to process..."
        sleep 5
        echo ""
    else
        echo "❌ Scenario file not found: $scenario_file"
    fi
}

# Run each scenario
run_scenario "$SCRIPT_DIR/scenario_A_flash_loan.sh" "Scenario A: Basic Flash Loan"
run_scenario "$SCRIPT_DIR/scenario_B_price_manipulation.sh" "Scenario B: Price Manipulation"
run_scenario "$SCRIPT_DIR/scenario_C_sandwich_attack.sh" "Scenario C: Sandwich Attack"
run_scenario "$SCRIPT_DIR/scenario_D_oracle_manipulation.sh" "Scenario D: Oracle Manipulation (CRITICAL)"

# ============================================================================
# Summary
# ============================================================================

echo ""
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║                                                                  ║"
echo "║                  ALL SCENARIOS COMPLETED ✅                       ║"
echo "║                                                                  ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""

echo "📊 Expected Detection Summary:"
echo ""
echo "   Total Scenarios:     4"
echo "   Total Detections:    ~8-9 risk events"
echo ""
echo "   Risk Levels:"
echo "   - CRITICAL:  1-2 events  (Oracle Manipulation)"
echo "   - HIGH:      4-5 events  (Flash Loan, Price Manip, Sandwich)"
echo "   - MEDIUM:    2-3 events  (Price impact, Flash loan usage)"
echo ""

echo "🔍 Verification Steps:"
echo ""
echo "   1. Check sui-indexer logs:"
echo "      tail -f /var/log/sui-indexer.log | grep -i \"DETECTION ALERT\""
echo ""
echo "   2. Query detection results:"
echo "      ./scenarios/verify_detections.sh"
echo ""
echo "   3. Check PostgreSQL:"
echo "      psql -U postgres -d sui_indexer -c \"SELECT * FROM transactions ORDER BY created_at DESC LIMIT 10;\""
echo ""
echo "   4. Check Elasticsearch:"
echo "      curl -X GET \"localhost:9200/sui-transactions/_search?pretty\" -H 'Content-Type: application/json' -d '{\"query\": {\"match_all\": {}}, \"size\": 10}'"
echo ""

echo "✨ Detection testing complete!"
echo ""
