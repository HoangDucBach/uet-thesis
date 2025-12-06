# Attack Scenarios for Detection System Testing

This directory contains realistic attack scenarios to test the 4-layer detection system:

1. **Flash Loan Detector** - Detects flash loan patterns
2. **Price Manipulation Detector** - Detects large swaps with price impact
3. **Sandwich Attack Detector** - Detects front-running/back-running patterns
4. **Oracle Manipulation Detector** - Detects cross-protocol exploitation

## Scenario Overview

### 1. Basic Flash Loan Attack (Scenario A)
**Detection Target**: Flash Loan Detector
**Complexity**: Low
**Description**: Simple flash loan with immediate repayment

**Expected Detection**:
- ✅ Flash Loan Detector: HIGH risk
- ❌ Price Manipulation: No large swaps
- ❌ Sandwich: No victim transactions
- ❌ Oracle Manipulation: No lending borrows

---

### 2. Price Manipulation Attack (Scenario B)
**Detection Target**: Price Manipulation Detector
**Complexity**: Medium
**Description**: Large swap causing significant price impact

**Expected Detection**:
- ❌ Flash Loan: No flash loan
- ✅ Price Manipulation: HIGH risk (>10% price impact)
- ❌ Sandwich: No victim transactions
- ❌ Oracle Manipulation: No lending activity

---

### 3. Sandwich Attack (Scenario C)
**Detection Target**: Sandwich Detector
**Complexity**: Medium
**Description**: Classic sandwich attack with front-run + victim + back-run

**Transaction Sequence**:
1. Attacker front-runs: Buy TokenA (manipulate price up)
2. Victim executes: Buy TokenA (worse price)
3. Attacker back-runs: Sell TokenA (profit from price)

**Expected Detection**:
- ❌ Flash Loan: No flash loan
- ✅ Price Manipulation: MEDIUM (front-run swap)
- ✅ Sandwich: HIGH risk (temporal correlation detected)
- ❌ Oracle Manipulation: No lending activity

---

### 4. Oracle Manipulation Attack (Scenario D) ⭐ **MOST CRITICAL**
**Detection Target**: Oracle Manipulation Detector
**Complexity**: Very High
**Description**: Cross-protocol attack exploiting oracle price feed

**Attack Flow**:
```
1. Take flash loan (100,000 USDC)
2. Swap on DEX: USDC → WETH (manipulate WETH price UP by ~50%)
3. Borrow from lending market using manipulated oracle price
   - Supply 10 WETH as collateral
   - Oracle reads inflated WETH price from DEX
   - Borrow maximum USDC against inflated collateral value
4. Repay flash loan
5. Profit from over-borrowed USDC
```

**Expected Detection**:
- ✅ Flash Loan: HIGH risk (large flash loan)
- ✅ Price Manipulation: CRITICAL (>50% price impact)
- ❌ Sandwich: No victim
- ✅ Oracle Manipulation: CRITICAL (all 5 signals detected)
  - Signal 1: Flash loan present
  - Signal 2: Large price deviation (>50%)
  - Signal 3: Significant borrow after manipulation
  - Signal 4: Temporal correlation (borrow within 1 block)
  - Signal 5: Unhealthy position (health factor < 1.0)

**Risk Level**: CRITICAL
**Protocol Loss**: High (bad debt from under-collateralized position)

---

### 5. Multi-Pool Arbitrage (Scenario E)
**Detection Target**: Price Manipulation + Flash Loan
**Complexity**: High
**Description**: Complex arbitrage across multiple DEX pools

**Attack Flow**:
```
1. Flash loan 50,000 USDC
2. Swap USDC → USDT (Pool A)
3. Swap USDT → WETH (Pool B)
4. Swap WETH → USDC (Pool C)
5. Repay flash loan + profit
```

**Expected Detection**:
- ✅ Flash Loan: MEDIUM risk
- ✅ Price Manipulation: MEDIUM (multiple swaps with cumulative impact)
- ❌ Sandwich: No victim
- ❌ Oracle Manipulation: No lending activity

---

### 6. Flash Loan + Lending (Scenario F)
**Detection Target**: Oracle Manipulation (borderline case)
**Complexity**: High
**Description**: Flash loan with legitimate lending use (edge case)

**Attack Flow**:
```
1. Flash loan 20,000 USDC
2. Supply to lending market as collateral
3. Borrow WETH against collateral (normal LTV)
4. Use WETH for arbitrage
5. Repay borrow
6. Withdraw collateral
7. Repay flash loan
```

**Expected Detection**:
- ✅ Flash Loan: MEDIUM risk
- ❌ Price Manipulation: No large swaps
- ❌ Sandwich: No victim
- ⚠️ Oracle Manipulation: LOW risk (flash loan + lending, but healthy position)

---

## Scenario Implementation

Each scenario has:
- `scenario_X.sh` - Transaction execution script
- `scenario_X_verify.sh` - Verification script (check detection output)
- `scenario_X.md` - Detailed documentation

## Running Scenarios

```bash
# Setup environment
source ../contracts/setup.sh

# Run individual scenario
./scenarios/scenario_D_oracle_manipulation.sh

# Run all scenarios
./scenarios/run_all_scenarios.sh

# Verify detection results
./scenarios/verify_all.sh
```

## Detection Metrics

After running scenarios, the detection system should report:

| Scenario | Flash Loan | Price Manip | Sandwich | Oracle Manip | Total Detections |
|----------|-----------|-------------|----------|--------------|------------------|
| A        | HIGH      | -           | -        | -            | 1                |
| B        | -         | HIGH        | -        | -            | 1                |
| C        | -         | MEDIUM      | HIGH     | -            | 2                |
| D ⭐      | HIGH      | CRITICAL    | -        | CRITICAL     | 3                |
| E        | MEDIUM    | MEDIUM      | -        | -            | 2                |
| F        | MEDIUM    | -           | -        | LOW          | 2                |

**Expected Total**: 11 risk events across 6 scenarios
