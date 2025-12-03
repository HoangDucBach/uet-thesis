# DeFi Attack Detection Algorithms - Research & Implementation

## Overview

This document outlines the detection algorithms implemented in the sui-indexer for identifying real-time DeFi attacks on the Sui blockchain. The detection system uses pattern-based analysis of on-chain events to identify malicious activities without relying on explicit "attack" signals.

## Research Background

### Academic References

1. **Flash Loan Attacks**
   - "Attack on the DeFi Ecosystem: A Survey" (Qin et al., 2021)
   - "Empirical Analysis of DeFi Liquidations" (Qin et al., 2021)

2. **Price Manipulation**
   - "High-Frequency Trading on Decentralized On-Chain Exchanges" (Zhou et al., 2021)
   - "Cyclic Arbitrage in DEXs" (Wang et al., 2022)

3. **Sandwich Attacks**
   - "Quantifying Blockchain Extractable Value" (Daian et al., 2020)
   - "Unity is Strength: A Formalization of Cross-Domain MEV" (Babel et al., 2021)

---

## Detection Algorithms

### 1. Flash Loan Attack Detection

#### Algorithm Overview

Flash loan attacks involve borrowing large amounts of capital, executing profitable trades through price manipulation or arbitrage, and repaying the loan within a single transaction.

#### Detection Method: **Pattern-Based Multi-Signal Analysis**

**Input**: Single transaction with events
**Output**: Risk level (None, Low, Medium, High, Critical)

**Algorithm Steps**:

```
1. Event Extraction
   - Extract FlashLoanTaken events → {amount, fee, pool_id}
   - Extract FlashLoanRepaid events → {amount_repaid, fee_paid}
   - Extract SwapExecuted events → [{amount_in, amount_out, price_impact, pool_id}]

2. Pattern Detection
   IF (has_flash_loan_taken AND has_flash_loan_repaid):

       2.1 Circular Trading Detection
           - Build token flow graph from swaps
           - Detect if start_token == end_token
           - Count unique pools touched

       2.2 Price Impact Analysis
           - Calculate total_price_impact = Σ price_impact_i
           - Detect if any single swap has price_impact > 500 bps (5%)

       2.3 Profit Estimation
           - Compare flash_loan_amount vs final_balance
           - Estimate profit = final_balance - (flash_loan_amount + fee)

       2.4 Complexity Analysis
           - Count number of swaps
           - Identify multi-pool arbitrage patterns

3. Risk Scoring
   risk_score = 0

   IF circular_trading: risk_score += 30
   IF swap_count >= 3: risk_score += 20
   IF total_price_impact > 1000 bps: risk_score += 25
   IF max_single_impact > 500 bps: risk_score += 15
   IF estimated_profit > threshold: risk_score += 10

   CLASSIFY:
   - risk_score < 30: None
   - 30 <= risk_score < 50: Low
   - 50 <= risk_score < 70: Medium
   - 70 <= risk_score < 85: High
   - risk_score >= 85: Critical

4. Return
   IF risk_score >= 30:
       RETURN RiskEvent{
           type: FlashLoanAttack,
           level: CLASSIFIED_LEVEL,
           details: {
               flash_loan_amount,
               swap_count,
               circular_trading,
               total_price_impact,
               estimated_profit,
               pools_touched
           }
       }
```

**Key Features**:
- ✅ No reliance on explicit "attack" events
- ✅ Multi-signal analysis (not just single metric)
- ✅ Weighted scoring system
- ✅ Graduated risk levels

**Advantages over current approaches**:
- Most systems only detect if flash loan exists (binary)
- This algorithm analyzes the **complexity and impact** of the transaction
- Distinguishes legitimate arbitrage from manipulative attacks

**Limitations**:
- Cannot detect off-chain coordination
- May have false positives for complex legitimate arbitrage
- Profit estimation is approximate (doesn't account for all fees)

---

### 2. Price Manipulation Detection

#### Algorithm Overview

Price manipulation involves artificially moving the price of an asset through large trades to profit from the price difference or exploit other protocols.

#### Detection Method: **TWAP Deviation Analysis + Trade Impact Scoring**

**Input**: Transaction with swap events + TWAP oracle state
**Output**: Risk level + deviation metrics

**Algorithm Steps**:

```
1. Event Parsing
   - Extract SwapExecuted events → {amount_in, amount_out, price_impact, reserve_a, reserve_b}
   - Extract TWAPUpdated events → {twap_price, spot_price, deviation_bps}
   - Extract PriceDeviationDetected events → {deviation_bps, timestamp}

2. Price Impact Analysis

   2.1 Calculate Spot Price Change
       price_before = reserve_a_before / reserve_b_before
       price_after = reserve_a_after / reserve_b_after
       price_change_pct = |price_after - price_before| / price_before * 100

   2.2 Pool Depth Analysis
       pool_depth = min(reserve_a, reserve_b)
       swap_to_depth_ratio = amount_in / pool_depth

   2.3 TWAP Deviation Analysis (if oracle exists)
       IF TWAPUpdated event exists:
           deviation = |spot_price - twap_price| / twap_price * 100
           deviation_velocity = deviation / time_since_last_update

3. Manipulation Score Calculation

   score = 0

   # Price impact scoring
   IF price_impact > 2000 bps (20%): score += 40
   ELSE IF price_impact > 1000 bps (10%): score += 30
   ELSE IF price_impact > 500 bps (5%): score += 15

   # Trade size relative to pool
   IF swap_to_depth_ratio > 0.3: score += 25
   ELSE IF swap_to_depth_ratio > 0.15: score += 15

   # TWAP deviation (if available)
   IF deviation > 20%: score += 25
   ELSE IF deviation > 10%: score += 15
   ELSE IF deviation > 5%: score += 5

   # Rapid deviation
   IF deviation_velocity > 1% per minute: score += 10

4. Pattern Detection

   4.1 Pump and Dump Detection
       - Track consecutive swaps in same direction
       - Detect if >3 large swaps push price one direction

   4.2 Wash Trading Detection (requires historical context)
       - Check if same address trades back and forth
       - Calculate volume vs unique addresses ratio

5. Classification
   - score < 25: None
   - 25 <= score < 50: Low (normal high volatility)
   - 50 <= score < 70: Medium (suspicious)
   - 70 <= score < 85: High (likely manipulation)
   - score >= 85: Critical (clear manipulation)
```

**Key Metrics**:
- **Price Impact**: Direct measure of price movement
- **Swap-to-Depth Ratio**: Indicates if trade is abnormally large
- **TWAP Deviation**: Compares instant price vs average (oracle)
- **Deviation Velocity**: Speed of price change (rapid = suspicious)

**Advantages**:
- Combines multiple independent signals
- Uses TWAP oracle as baseline (resistant to manipulation)
- Considers pool depth (context-aware)
- Graduated scoring (not binary)

**Limitations**:
- Requires TWAP oracle for best accuracy
- May miss slow manipulation (< 5% moves)
- High volatility can trigger false positives

---

### 3. Sandwich Attack Detection

#### Algorithm Overview

Sandwich attacks involve front-running a victim's transaction with a buy order, letting the victim execute at a worse price, then back-running with a sell order to profit.

#### Detection Method: **Cross-Transaction Pattern Matching**

**Input**: Multiple transactions within same checkpoint/block
**Output**: Matched sandwich patterns with attacker addresses

**Algorithm Steps**:

```
1. Transaction Buffering

   # Maintain sliding window of recent transactions
   buffer = CircularBuffer(capacity: 100)

   FOR each transaction in checkpoint:
       buffer.push(transaction)

2. Pattern Extraction Per Transaction

   FOR each tx in buffer:
       IF has SwapExecuted event:
           pattern = {
               tx_digest,
               sender,
               pool_id,
               token_in_type,
               amount_in,
               amount_out,
               price_impact,
               timestamp,
               checkpoint_seq
           }

           # Classify direction
           IF token_in == TokenA:
               direction = "A_to_B"
           ELSE:
               direction = "B_to_A"

3. Sandwich Pattern Matching

   FOR each potential_victim in buffer:

       # Look for front-run (before victim)
       front_run_candidates = buffer.transactions.filter(
           tx.checkpoint_seq == victim.checkpoint_seq - 1 OR
           (tx.checkpoint_seq == victim.checkpoint_seq AND
            tx.timestamp < victim.timestamp)
       ).filter(
           tx.pool_id == victim.pool_id AND
           tx.direction == victim.direction AND
           tx.price_impact > threshold
       )

       # Look for back-run (after victim)
       back_run_candidates = buffer.transactions.filter(
           tx.checkpoint_seq == victim.checkpoint_seq + 1 OR
           (tx.checkpoint_seq == victim.checkpoint_seq AND
            tx.timestamp > victim.timestamp)
       ).filter(
           tx.pool_id == victim.pool_id AND
           tx.direction == OPPOSITE(victim.direction) AND
           tx.sender IN front_run_candidates.senders
       )

       # Match sandwich
       FOR each front in front_run_candidates:
           FOR each back in back_run_candidates:
               IF front.sender == back.sender:
                   # Found sandwich pattern!

                   4. Profit Calculation
                       price_after_front = calculate_price(pool, front)
                       price_after_victim = calculate_price(pool, victim)
                       price_after_back = calculate_price(pool, back)

                       attacker_profit = (back.amount_out - front.amount_in)
                       victim_loss = expected_amount_out - victim.amount_out

                   5. Scoring
                       score = 0

                       IF attacker_profit > 0: score += 40
                       IF victim_loss > victim.amount_in * 0.01 (1%): score += 30
                       IF time_between(front, back) < 30 seconds: score += 20
                       IF same checkpoint: score += 10

                       CLASSIFY:
                       IF score >= 70: CRITICAL
                       ELSE IF score >= 50: HIGH
                       ELSE IF score >= 30: MEDIUM

                   6. Report
                       EMIT SandwichAttackDetected{
                           attacker: front.sender,
                           victim: victim.sender,
                           front_run_tx: front.tx_digest,
                           victim_tx: victim.tx_digest,
                           back_run_tx: back.tx_digest,
                           attacker_profit,
                           victim_loss,
                           risk_level: CLASSIFIED
                       }
```

**Key Features**:
- Cross-transaction analysis (not single-tx)
- Temporal pattern matching
- Profit calculation for both attacker and victim
- Requires stateful buffer

**Advantages**:
- Accurately identifies MEV extraction
- Quantifies victim impact
- Works across multiple blocks

**Limitations**:
- Requires buffering recent transactions (memory overhead)
- May miss sandwiches spread across many blocks
- Cannot detect coordinated attacks from different addresses
- Performance overhead for pattern matching

---

## Implementation Architecture

### Data Flow

```
Sui Blockchain
    ↓
Checkpoint Data
    ↓
Transaction Filter (Package ID)
    ↓
Event Extraction
    ↓
┌─────────────────────────────────────┐
│   Detection Pipeline                │
│                                     │
│  ┌────────────────────────────┐    │
│  │ Flash Loan Detector        │    │
│  │  - Pattern matching        │    │
│  │  - Risk scoring            │    │
│  └────────────────────────────┘    │
│                                     │
│  ┌────────────────────────────┐    │
│  │ Price Manipulation Detector│    │
│  │  - TWAP analysis           │    │
│  │  - Impact scoring          │    │
│  └────────────────────────────┘    │
│                                     │
│  ┌────────────────────────────┐    │
│  │ Sandwich Detector          │    │
│  │  - Cross-tx matching       │    │
│  │  - Profit calculation      │    │
│  └────────────────────────────┘    │
└─────────────────────────────────────┘
    ↓
Risk Events
    ↓
┌─────────────────────────────────────┐
│   Action Pipeline                   │
│  - Logging                          │
│  - Database storage                 │
│  - Alerting (Slack/Discord)         │
│  - Elasticsearch indexing           │
└─────────────────────────────────────┘
```

### Performance Considerations

1. **Event Filtering**: Only process transactions from target package ID
2. **Lazy Evaluation**: Only deep-analyze if basic patterns match
3. **Circular Buffer**: Limit memory usage for sandwich detection
4. **Async Processing**: Non-blocking detection pipeline

---

## Comparison with Existing Approaches

### Traditional Binary Detection

**Approach**: Check if transaction contains "suspicious" event
```rust
// Old approach
if event.type == "FlashLoanAttackExecuted" {
    return Risk::Critical;
}
```

**Limitations**:
- ❌ Requires explicit attack signals
- ❌ Binary classification only
- ❌ No context awareness
- ❌ Easy to evade

### Our Multi-Signal Scoring

**Approach**: Analyze multiple independent signals and score
```rust
// Our approach
let score = analyze_circular_trading() +
            analyze_price_impact() +
            analyze_profit() +
            analyze_complexity();

return classify_by_score(score);
```

**Advantages**:
- ✅ Works on legitimate protocol events
- ✅ Graduated risk levels
- ✅ Context-aware (pool depth, TWAP, etc.)
- ✅ Harder to evade (need to minimize all signals)

---

## Future Improvements

1. **Machine Learning Integration**
   - Train models on labeled attack data
   - Feature extraction from event patterns
   - Anomaly detection for novel attacks

2. **Cross-Protocol Analysis**
   - Track user actions across multiple protocols
   - Detect coordinated attacks

3. **Graph Analysis**
   - Build transaction flow graphs
   - Detect complex attack patterns

4. **Real-time Alerting**
   - Sub-second detection latency
   - Integration with monitoring systems

---

## References

1. Qin, K., Zhou, L., Afonin, Y., Lazzaretti, L., & Gervais, A. (2021). CeFi vs. DeFi–Comparing Centralized to Decentralized Finance. arXiv preprint arXiv:2106.08157.

2. Daian, P., Goldfeder, S., Kell, T., Li, Y., Zhao, X., Bentov, I., ... & Juels, A. (2020, May). Flash boys 2.0: Frontrunning in decentralized exchanges, miner extractable value, and consensus instability. In 2020 IEEE Symposium on Security and Privacy (SP) (pp. 910-927). IEEE.

3. Zhou, L., Qin, K., Torres, C. F., Le, D. V., & Gervais, A. (2021, February). High-frequency trading on decentralized on-chain exchanges. In 2021 IEEE Symposium on Security and Privacy (SP) (pp. 428-445). IEEE.

4. Wang, D., Wu, S., Lin, Z., Wu, L., Yuan, X., Zhou, Y., ... & Wang, H. (2022, May). Towards understanding flash loan and its applications in DeFi ecosystem. In Proceedings of the ACM Web Conference 2022 (pp. 2082-2093).
