#!/bin/bash

# ============================================================================
# Verification Script: Check Detection Results
# ============================================================================
#
# Analyzes sui-indexer output to verify detection system is working correctly
#
# ============================================================================

echo ""
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║                                                                  ║"
echo "║         🔍 DETECTION RESULTS VERIFICATION 🔍                     ║"
echo "║                                                                  ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""

# Check if log file exists
LOG_FILE="/tmp/sui-indexer.log"

if [ ! -f "$LOG_FILE" ]; then
    echo "⚠️  Log file not found: $LOG_FILE"
    echo "   Looking for alternative locations..."

    # Try to find sui-indexer process and its output
    if pgrep -f "sui-indexer" > /dev/null; then
        echo "   ✓ sui-indexer process is running"
        echo "   Check console output for detection alerts"
    else
        echo "   ❌ sui-indexer is not running"
        exit 1
    fi
fi

echo "📊 Detection Statistics:"
echo ""

# Count detection alerts
if [ -f "$LOG_FILE" ]; then
    TOTAL_DETECTIONS=$(grep -c "DETECTION ALERT" "$LOG_FILE" || echo "0")
    CRITICAL=$(grep "Risk Level.*CRITICAL" "$LOG_FILE" | wc -l || echo "0")
    HIGH=$(grep "Risk Level.*HIGH" "$LOG_FILE" | wc -l || echo "0")
    MEDIUM=$(grep "Risk Level.*MEDIUM" "$LOG_FILE" | wc -l || echo "0")

    echo "   Total Detection Alerts:  $TOTAL_DETECTIONS"
    echo "   - CRITICAL:              $CRITICAL"
    echo "   - HIGH:                  $HIGH"
    echo "   - MEDIUM:                $MEDIUM"
    echo ""
fi

# Show recent detections
echo "📋 Recent Detection Events:"
echo ""

if [ -f "$LOG_FILE" ]; then
    grep -A 20 "DETECTION ALERT" "$LOG_FILE" | tail -50
else
    echo "   (Check console output if running in foreground)"
fi

echo ""
echo "✅ Verification complete!"
echo ""
