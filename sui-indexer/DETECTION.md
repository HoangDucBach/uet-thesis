# Real-Time DeFi Attack Detection System

## Overview

This sui-indexer implements a sophisticated real-time detection system for identifying three major types of DeFi attacks on the Sui blockchain:

1. **Flash Loan Attacks** - Complex arbitrage exploits using uncollateralized loans
2. **Price Manipulation** - Market manipulation through large trades and TWAP deviation
3. **Sandwich Attacks** - MEV extraction through transaction front-running and back-running

The detection system operates on live blockchain data, analyzing every transaction as it's finalized in checkpoints, and triggers alerts when suspicious patterns are detected.

---

## Detection Architecture

```
Sui Blockchain Checkpoints
        ↓
   Transaction Stream
        ↓
  Package ID Filter ←──────── Only process target protocol
        ↓
┌──────────────────────────────┐
│   Detection Pipeline         │
│                              │
│  ┌────────────────────────┐ │
│  │ Flash Loan Detector    │ │──→ Multi-signal pattern analysis
│  └────────────────────────┘ │
│                              │
│  ┌────────────────────────┐ │
│  │ Price Manipulation     │ │──→ TWAP deviation + impact scoring
│  └────────────────────────┘ │
│                              │
│  ┌────────────────────────┐ │
│  │ Sandwich Detector      │ │──→ Cross-transaction pattern matching
│  └────────────────────────┘ │
└──────────────────────────────┘
        ↓
   Risk Events (Graduated Levels)
        ↓
┌──────────────────────────────┐
│   Action Pipeline            │
│  - Logging                   │
│  - Alerting (Slack/Discord)  │
│  - Database Storage          │
└──────────────────────────────┘
```

---

## Detection Algorithms

### 1. Flash Loan Attack Detection

**Algorithm**: Multi-Signal Pattern Analysis

**How It Works**:

The detector analyzes transactions for patterns indicating flash loan-based attacks by examining multiple independent signals:

1. **Event Extraction**
   - Detects `FlashLoanTaken` and `FlashLoanRepaid` events in same transaction
   - Extracts `SwapExecuted` events for trade analysis
   - No reliance on explicit "attack" events

2. **Pattern Detection** (6 independent signals)
   - **Circular Trading**: Detects token flow cycles (A→B→C→A)
   - **Swap Complexity**: Counts number of swaps (≥3 is suspicious)
   - **Cumulative Price Impact**: Sums price impacts across all swaps
   - **Maximum Single Impact**: Identifies individual high-impact swaps
   - **Multi-Pool Arbitrage**: Detects trading across multiple pools
   - **Loan Size**: Flags unusually large flash loans

3. **Risk Scoring**
   ```
   risk_score = 0
   if circular_trading: +30
   if swaps ≥ 3: +20
   if total_impact > 2000 bps: +25
   if max_impact > 500 bps: +15
   if pools ≥ 3: +15
   if loan_amount > 1B: +10

   Classification:
   < 30: None (legitimate)
   30-49: Low
   50-69: Medium
   70-84: High
   ≥ 85: Critical
   ```

**Example Detection**:
```
Transaction: 0xabc123...
✓ Flash loan taken: 1,000,000 USDC
✓ Swaps detected: 4
✓ Circular trading: USDC → USDT → WETH → USDC
✓ Total price impact: 2,500 bps (25%)
✓ Pools touched: 3
✓ Flash loan repaid with profit

Risk Score: 90 → CRITICAL
```

**Advantages**:
- ✅ No reliance on fake "attack" events
- ✅ Graduated risk levels (not binary)
- ✅ Context-aware (considers pool depth, complexity)
- ✅ Harder to evade (must minimize all signals)
- ✅ Works with legitimate protocol events only

**Limitations**:
- ❌ Cannot detect off-chain coordination
- ❌ May false-positive on complex legitimate arbitrage
- ❌ Profit estimation is approximate

---

### 2. Price Manipulation Detection

**Algorithm**: TWAP Deviation Analysis + Trade Impact Scoring

**How It Works**:

The detector identifies price manipulation by analyzing trade impacts and comparing spot prices to Time-Weighted Average Prices (TWAP):

1. **Event Extraction**
   - Parses `SwapExecuted` events with reserve data
   - Extracts `TWAPUpdated` events from oracle (if available)
   - Detects `PriceDeviationDetected` events

2. **Multi-Signal Analysis** (4 independent signals)
   - **Direct Price Impact**: Measures immediate price change from trade
   - **Swap-to-Depth Ratio**: Compares trade size to pool liquidity
   - **TWAP Deviation**: Calculates spot price vs. time-weighted average
   - **Pump Pattern**: Detects consecutive large swaps in same direction

3. **Risk Scoring**
   ```
   risk_score = 0

   # Price impact
   if price_impact ≥ 2000 bps (20%): +40
   elif price_impact ≥ 1000 bps (10%): +30
   elif price_impact ≥ 500 bps (5%): +15

   # Trade size relative to pool
   if swap_to_depth > 30%: +25
   elif swap_to_depth > 15%: +15

   # TWAP deviation (if oracle available)
   if deviation ≥ 2000 bps (20%): +25
   elif deviation ≥ 1000 bps (10%): +15
   elif deviation ≥ 500 bps (5%): +5

   # Pump pattern
   if consecutive_swaps_same_direction ≥ 2: +10

   Classification:
   < 25: None
   25-49: Low
   50-69: Medium
   70-84: High
   ≥ 85: Critical
   ```

**Example Detection**:
```
Transaction: 0xdef456...
✓ Swap: 500,000 USDC → WETH
✓ Price impact: 1,800 bps (18%)
✓ Swap-to-depth ratio: 35%
✓ Pool depth: 1,400,000 USDC
✓ TWAP price: 3,000 USDC/ETH
✓ Spot price: 3,600 USDC/ETH
✓ Deviation: 2,000 bps (20%)

Risk Score: 90 → CRITICAL
```

**Advantages**:
- ✅ Works with or without TWAP oracle
- ✅ Context-aware (considers pool depth)
- ✅ Detects both instant and gradual manipulation
- ✅ TWAP provides manipulation-resistant baseline
- ✅ Multiple independent signals

**Limitations**:
- ❌ High volatility can trigger false positives
- ❌ May miss slow manipulation (< 5% moves)
- ❌ Requires oracle for best accuracy

---

### 3. Sandwich Attack Detection

**Algorithm**: Cross-Transaction Pattern Matching with Stateful Buffer

**How It Works**:

The detector identifies sandwich attacks by matching transaction patterns across multiple blocks:

1. **Transaction Buffering**
   - Maintains circular buffer of recent 100 swap patterns
   - Tracks checkpoint sequence, timestamp, sender, pool, amounts
   - Auto-cleans entries older than 5 checkpoints

2. **Pattern Matching** (Front-run → Victim → Back-run)
   ```
   For each new swap (potential back-run):
     1. Find front-run candidates:
        - Same pool
        - Same sender as back-run (the attacker)
        - Before back-run (earlier checkpoint/timestamp)
        - Same token direction
        - Within 5 checkpoints

     2. Find victim between front-run and back-run:
        - Same pool
        - Different sender
        - Timestamp: front-run < victim < back-run
        - Same direction as attacker

     3. If found: SANDWICH DETECTED
   ```

3. **Profit/Loss Calculation**
   - **Attacker Profit**: `back_run.amount_out - front_run.amount_in`
   - **Victim Loss**: Estimates expected output without manipulation
   - **Loss in basis points**: `(expected - actual) / expected * 10000`

4. **Risk Scoring**
   ```
   risk_score = 0
   if attacker_profit > 0: +40
   if victim_loss > 1%: +30
   if time_span < 30 seconds: +20
   if same_checkpoint: +10

   Classification:
   < 30: None
   30-49: Medium
   50-69: High
   ≥ 70: Critical
   ```

**Example Detection**:
```
Checkpoint 1000, tx 1: 0xabc...
  Attacker swaps 1000 USDC → 0.33 ETH

Checkpoint 1000, tx 2: 0xdef...
  Victim swaps 5000 USDC → 1.55 ETH (expected 1.65 ETH)

Checkpoint 1001, tx 1: 0xghi...
  Attacker swaps 0.33 ETH → 1050 USDC

✓ Sandwich detected!
✓ Attacker: same address (0x123...)
✓ Attacker profit: 50 USDC
✓ Victim loss: 100 USDC (~6%)
✓ Time span: 3 seconds

Risk Score: 80 → HIGH
```

**Advantages**:
- ✅ Accurately identifies MEV extraction
- ✅ Quantifies both attacker profit and victim loss
- ✅ Works across multiple blocks/checkpoints
- ✅ Detects patterns invisible to single-tx analysis
- ✅ Provides full attack chain (3 transactions)

**Limitations**:
- ❌ Requires buffering (memory overhead)
- ❌ May miss sandwiches spread across many blocks
- ❌ Cannot detect coordinated attacks from different addresses
- ❌ Pattern matching has O(n²) complexity for large buffers

---

## Comparison with Traditional Approaches

### Traditional Binary Detection

**Old Approach**: Check for explicit "attack" event
```rust
// Naive approach
if event.type == "FlashLoanAttackExecuted" {
    return Risk::Critical;
}
```

**Problems**:
- ❌ Requires protocol to explicitly emit "attack" events
- ❌ Binary classification only (attack or not)
- ❌ No context awareness
- ❌ Easy to evade by not emitting events
- ❌ Relies on protocol being honest about attacks

### Our Multi-Signal Approach

**Our Approach**: Analyze multiple independent signals
```rust
// Sophisticated approach
let score = analyze_circular_trading() +
            analyze_price_impact() +
            analyze_complexity() +
            analyze_profit();

return classify_by_score(score);
```

**Advantages**:
- ✅ Works with legitimate protocol events only
- ✅ Graduated risk levels (Low/Medium/High/Critical)
- ✅ Context-aware (pool depth, TWAP, timing)
- ✅ Harder to evade (need to minimize ALL signals)
- ✅ More accurate (fewer false positives)
- ✅ Protocol-agnostic (works with any DEX)

---

## Configuration

### Environment Variables

```bash
# Target package to monitor
SIMULATION_PACKAGE_ID=0x0a78ed73edcaca699f8ffead05a9626aadd6edb30d49523574c8016806b0530e

# Alert webhook (Slack/Discord)
ALERT_WEBHOOK_URL=https://hooks.slack.com/services/YOUR/WEBHOOK/URL

# Alert threshold (only alert on High/Critical by default)
ALERT_THRESHOLD=High  # Options: Low, Medium, High, Critical
```

### Detection Thresholds

Thresholds are configured in analyzer modules:

**Flash Loan** (`analyzer/flash_loan.rs`):
```rust
min_swap_count: 2,                  // Minimum swaps to analyze
price_impact_threshold: 500,        // 5% price impact
high_price_impact_threshold: 1000,  // 10% high impact
```

**Price Manipulation** (`analyzer/price.rs`):
```rust
min_price_impact: 500,              // 5% minimum impact
twap_deviation_threshold: 1000,     // 10% TWAP deviation
high_impact_threshold: 2000,        // 20% critical impact
```

**Sandwich** (`analyzer/sandwich.rs`):
```rust
max_buffer_size: 100,               // Buffer capacity
max_checkpoint_distance: 5,         // Checkpoint window
min_price_impact: 100,              // 1% minimum impact
```

---

## Usage

### Running the Indexer

```bash
# Set environment variables
export DATABASE_URL=postgresql://user:pass@localhost/sui_indexer
export ELASTICSEARCH_URL=http://localhost:9200
export SIMULATION_PACKAGE_ID=0xYOUR_PACKAGE_ID
export ALERT_WEBHOOK_URL=https://your.webhook.url

# Run indexer
cd sui-indexer
cargo run --release
```

### Monitoring Output

The indexer logs detected attacks to console:

```
🔍 Detected 1 risk events in tx abc12345
⚠️  [CRITICAL] Flash Loan Attack detected
    TX: 0xabc12345...
    Attacker: 0x789...
    Details: Flash loan arbitrage detected: 4 swaps across 3 pools,
            25% total price impact, circular trading pattern
    Profit: ~1000 USDC
    Risk Score: 90/100
```

### Integrating with Monitoring

The action pipeline supports multiple handlers:

1. **LogAction**: Console logging (always enabled)
2. **AlertAction**: Webhook alerts (Slack/Discord)
3. **ElasticsearchAction**: Index events for analysis
4. **DatabaseAction**: Store in PostgreSQL

Add custom handlers in `src/action/`:

```rust
pub struct CustomAction;

#[async_trait]
impl ActionHandler for CustomAction {
    async fn handle(&self, event: &RiskEvent) -> Result<()> {
        // Your custom logic
        Ok(())
    }
}
```

---

## Performance Considerations

### Throughput

- **Flash Loan Detection**: O(n) where n = number of swaps in transaction
- **Price Manipulation**: O(n) where n = number of swaps in transaction
- **Sandwich Detection**: O(b²) where b = buffer size (default 100)

### Memory Usage

- **Flash Loan**: Minimal (stateless)
- **Price Manipulation**: Minimal (stateless)
- **Sandwich**: ~100 KB (stateful buffer with 100 patterns)

### Optimizations

1. **Package ID Filtering**: Only analyzes transactions from target package
2. **Lazy Evaluation**: Skips deep analysis if basic patterns don't match
3. **Circular Buffer**: Limits memory usage with automatic cleanup
4. **Async Processing**: Non-blocking detection pipeline

---

## Testing

### Unit Tests

```bash
cargo test --package sui-indexer
```

### Integration Tests

Deploy test contracts and run simulated attacks:

```bash
cd contracts
sui move test  # Test attack scenarios
```

### Manual Testing

Use the contracts to generate test attacks:

```move
// Flash loan attack
let loan = flash_loan_pool::borrow(&mut pool, 1_000_000);
// ... perform swaps ...
flash_loan_pool::repay(&mut pool, repayment, loan);
```

---

## Future Improvements

### Short Term

1. **Enhanced Sandwich Detection**
   - Track multi-address coordination
   - Detect sandwiches across longer time windows
   - Improve profit/loss estimation with pool state

2. **Machine Learning Integration**
   - Train models on labeled attack data
   - Feature extraction from event patterns
   - Anomaly detection for novel attacks

3. **Additional Attack Types**
   - Reentrancy attacks
   - Oracle manipulation
   - Governance attacks
   - Liquidation cascades

### Long Term

1. **Cross-Protocol Analysis**
   - Track user actions across multiple protocols
   - Detect coordinated attacks
   - Build transaction flow graphs

2. **Predictive Detection**
   - Identify suspicious addresses before attacks
   - Pattern recognition on historical data
   - Risk scoring for addresses

3. **Real-time Alerting**
   - Sub-second detection latency
   - Integration with monitoring dashboards
   - Automated response mechanisms

---

## Academic Foundation

This detection system is based on research from:

1. **Qin et al. (2021)**: "Attack on the DeFi Ecosystem: A Survey"
2. **Daian et al. (2020)**: "Flash Boys 2.0: Frontrunning in Decentralized Exchanges"
3. **Zhou et al. (2021)**: "High-Frequency Trading on Decentralized On-Chain Exchanges"
4. **Wang et al. (2022)**: "Towards Understanding Flash Loan and its Applications"

Full academic details and algorithm pseudocode: [DETECTION_RESEARCH.md](../DETECTION_RESEARCH.md)

---

## License

Apache-2.0

---

## Contact

For questions or issues:
- **GitHub Issues**: [Create an issue](../../issues)
- **Documentation**: See inline code comments for implementation details
