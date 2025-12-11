# Attack Detection Analyzer Signals Analysis

## Overview

| Analyzer                | Purpose                                  | Signals | Threshold  | Risk Levels                                           |
| ----------------------- | ---------------------------------------- | ------- | ---------- | ----------------------------------------------------- |
| **Oracle Manipulation** | Oracle manipulation to exploit lending   | 6       | ≥40 points | 40-59: Medium, 60-79: High, 80+: Critical             |
| **Flash Loan**          | Complex flash loan arbitrage             | 7       | ≥30 points | 30-49: Low, 50-69: Medium, 70-84: High, 85+: Critical |
| **Sandwich**            | Front-run + back-run across transactions | 8       | ≥0 points  | 0-29: Low, 30-49: Medium, 50-69: High, 70+: Critical  |
| **Price**               | Price manipulation via TWAP deviation    | 5       | ≥25 points | 25-49: Low, 50-69: Medium, 70-84: High, 85+: Critical |

---

## 1. Oracle Manipulation Analyzer

### Signal Table

| Signal                   | Description                      | Event                               | Points | Threshold       |
| ------------------------ | -------------------------------- | ----------------------------------- | ------ | --------------- |
| Flash Loan Presence      | Flash loan borrow + repay        | `FlashLoanTaken`, `FlashLoanRepaid` | +20    | Required        |
| Large Price-Moving Swaps | Swaps with high price impact     | `SwapExecuted`                      | +20-40 | ≥5% (500 bps)   |
| Lending Borrows          | Borrow from lending protocol     | `BorrowEvent`                       | +15-20 | ≥100 tokens     |
| Price Deviation          | Oracle vs normal price deviation | Calculated                          | +20-40 | ≥10% (1000 bps) |
| Protocol Loss Risk       | Estimated protocol loss          | Calculated                          | +10-20 | >0              |
| Abnormal Health Factor   | Abnormal health factor           | `BorrowEvent`                       | +10    | >1.5x (15000)   |

### Key Formulas

- **Price Deviation**: `|oracle_price - normal_price| * 10000 / min(oracle_price, normal_price)`
- **Protocol Loss**: `max(0, borrow_amount - real_collateral_value)`

---

## 2. Flash Loan Analyzer

### Signal Table

| Signal                  | Description                  | Event                               | Points   | Threshold            |
| ----------------------- | ---------------------------- | ----------------------------------- | -------- | -------------------- |
| Flash Loan Presence     | Flash loan borrow + repay    | `FlashLoanTaken`, `FlashLoanRepaid` | Required | Must exist           |
| Circular Trading        | A→B→A pattern                | Swap analysis                       | +30      | ≥2 swaps             |
| Multiple Swaps          | Number of swaps              | `SwapExecuted`                      | +10-20   | ≥2 swaps (+20 if ≥3) |
| Cumulative Price Impact | Total price impact           | `SwapExecuted`                      | +15-25   | >10% (+25 if >20%)   |
| Single High-Impact Swap | Single swap with high impact | `SwapExecuted`                      | +15      | >5% (500 bps)        |
| Multi-Pool Arbitrage    | Number of unique pools       | Pool analysis                       | +10-15   | ≥2 pools (+15 if ≥3) |
| Large Flash Loan        | Large flash loan amount      | `FlashLoanTaken`                    | +10      | >1000 tokens         |

---

## 3. Sandwich Analyzer

### Signal Table

| Signal             | Description                       | Conditions                                          | Points   |
| ------------------ | --------------------------------- | --------------------------------------------------- | -------- |
| Front-Run Pattern  | Attacker swap before victim       | Same pool, sender, direction, checkpoint ≤5         | Required |
| Victim Transaction | Victim swap in between            | Same pool, different sender, between front/back-run | Required |
| Back-Run Pattern   | Attacker swap after victim        | Same pool, sender, direction as front-run           | Required |
| Attacker Profit    | Attacker profit                   | `back_run.amount_out - front_run.amount_in`         | +20-40   |
| Victim Loss        | Victim loss (bps)                 | Calculated from expected output                     | +10-30   |
| Same Checkpoint    | Front/back-run in same checkpoint | `front_run.checkpoint == back_run.checkpoint`       | +10      |
| Quick Execution    | Fast execution time               | `time_diff < 5000ms`                                | +10      |
| Price Impact       | Swap with significant impact      | `price_impact >= 100` (1%)                          | Required |

### Features

- **Stateful**: Buffer of 100 transactions
- **Cross-Transaction**: Detection across multiple transactions
- **Checkpoint Distance**: ≤5 checkpoints

---

## 4. Price Analyzer

### Signal Table

| Signal              | Description                   | Event                    | Points | Threshold                       |
| ------------------- | ----------------------------- | ------------------------ | ------ | ------------------------------- |
| Direct Price Impact | Price impact from swaps       | `SwapExecuted`           | +15-40 | ≥5% (500 bps)                   |
| Trade Size Ratio    | Trade/pool depth ratio        | `SwapExecuted`           | +15-25 | >15% (+25 if >30%)              |
| TWAP Deviation      | Spot vs TWAP deviation        | `TWAPUpdated`            | +5-25  | ≥5% (500 bps)                   |
| Explicit Deviation  | Deviation detection event     | `PriceDeviationDetected` | +10    | Event exists                    |
| Pump Pattern        | Multiple swaps same direction | `SwapExecuted`           | +10    | ≥2 swaps, same pool, ≥1% impact |

### Thresholds

- High price impact: 1000 bps (10%)
- Critical price impact: 2000 bps (20%)
- TWAP deviation: 500 bps (5%)
- Large trade ratio: 0.15 (15% of pool)

---

### Summary

| Analyzer                | Key Features                                            |
| ----------------------- | ------------------------------------------------------- |
| **Oracle Manipulation** | Temporal correlation analysis, protocol loss estimation |
| **Flash Loan**          | Circular trading detection, multi-pool arbitrage        |
| **Sandwich**            | Stateful analysis, cross-transaction pattern matching   |
| **Price**               | TWAP-based deviation, trade impact scoring              |
