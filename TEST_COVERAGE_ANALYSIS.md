# Test Coverage Analysis

## 📊 Current Test Coverage Summary

**Total Test Cases:** 5/5 passing ✅
**Module Coverage:** ~30% (Basic functionality only)

---

## ✅ What's Currently Tested

### 1. Coin Factory (`coin_factory.move`)
- ✅ Coin minting (USDC, USDT)
- ✅ Coin burning
- ✅ Factory creation with treasury caps

### 2. DEX (`simple_dex.move`)
- ✅ Pool creation
- ✅ Basic swap A→B (USDC→USDT)
- ✅ Reserve checking

### 3. Flash Loan Pool (`flash_loan_pool.move`)
- ✅ Pool creation
- ✅ Borrow flash loan
- ✅ Repay flash loan (successful case)

### 4. Price Oracle (`price_oracle.move`)
- ✅ Price update
- ✅ Get price with clock

---

## ❌ Critical Missing Test Cases

### 1. DEX (`simple_dex.move`) - Missing 70%

#### High Priority:
- ❌ **add_liquidity** - Chức năng quan trọng cho LP, chưa test
- ❌ **swap_b_to_a** - Chỉ test 1 chiều swap
- ❌ **Slippage protection** - Test với `min_out` parameter khác 0
- ❌ **Edge cases:**
  - Insufficient liquidity error
  - Zero amount error
  - Large trades causing high price impact (>10%)
  - Multiple consecutive swaps

#### Medium Priority:
- ❌ calculate_amount_out accuracy
- ❌ Fee calculation verification (0.3%)
- ❌ LP token supply changes
- ❌ Pool state after multiple operations

---

### 2. Flash Loan Pool (`flash_loan_pool.move`) - Missing 60%

#### High Priority:
- ❌ **Repayment failure** - Test khi không repay đủ (amount + fee)
- ❌ **Wrong pool error** - Test khi dùng receipt từ pool khác
- ❌ **Multiple flash loans** - Test concurrent loans
- ❌ **add_liquidity** to existing pool

#### Medium Priority:
- ❌ get_stats function
- ❌ get_available_liquidity
- ❌ Fee calculation (0.09%)
- ❌ Insufficient balance error

---

### 3. Attack Simulations - Missing 100% ⚠️

#### Critical:
- ❌ **sandwich_attack.move** - CHƯA TEST GÌ CẢ
  - execute_sandwich_attack
  - front_run + back_run phases
  - Victim slippage calculation
  - Attacker profit calculation

- ❌ **flash_loan_attack.move** - CHƯA TEST GÌ CẢ
  - execute_arbitrage_attack
  - execute_simple_arbitrage
  - Oracle manipulation attack
  - Multi-pool arbitrage

---

### 4. Victim Scenarios (`retail_trader.move`) - Missing 100%

#### High Priority:
- ❌ **execute_normal_trade** - Normal trading behavior
- ❌ **execute_simple_trade** - Trade without slippage protection
- ❌ **Slippage suffered** calculation
- ❌ **add_liquidity** as retail LP
- ❌ **swap_and_transfer** function

---

### 5. Price Oracle (`price_oracle.move`) - Missing 70%

#### High Priority:
- ❌ **Stale price check** - Test after 5+ minutes
- ❌ **manipulate_price** - Oracle manipulation for attacks
- ❌ **PriceManipulationDetected event** - Test >10% price change
- ❌ **Multiple price updates**
- ❌ **get_price_unsafe**

#### Medium Priority:
- ❌ add_authorized_source / remove_authorized_source
- ❌ is_authorized check
- ❌ Price change percentage calculation
- ❌ Confidence interval handling

---

## 🎯 Recommended Test Additions for MEV Simulation

### Phase 1: Core Functionality (Must Have)
```
1. test_add_liquidity - Test LP provision
2. test_swap_both_directions - Test swap A→B and B→A
3. test_flash_loan_repayment_failure - Test security
4. test_multiple_swaps - Test sequential operations
5. test_slippage_protection - Test min_out enforcement
```

### Phase 2: Attack Scenarios (Critical for Thesis)
```
6. test_sandwich_attack_basic - Simple sandwich attack
7. test_sandwich_attack_with_victim - Full sandwich scenario
8. test_flash_loan_arbitrage - Basic arbitrage attack
9. test_flash_loan_price_manipulation - Oracle manipulation attack
10. test_retail_trader_behavior - Victim behavior simulation
```

### Phase 3: Edge Cases & Security
```
11. test_high_price_impact_swap - Large trade impact
12. test_stale_oracle_price - Price freshness check
13. test_oracle_manipulation_detection - >10% change detection
14. test_concurrent_flash_loans - Multiple loans
15. test_insufficient_liquidity_errors - Error handling
```

### Phase 4: Complex Scenarios (For Analysis)
```
16. test_multi_hop_sandwich - Sandwich across multiple pools
17. test_cascading_liquidations - Chain reaction attacks
18. test_jit_liquidity_attack - Just-in-time LP attacks
19. test_mev_extraction_sequence - Multiple MEV strategies
20. test_victim_loss_calculation - Quantify victim losses
```

---

## 📈 Test Coverage Metrics

| Module | Current Coverage | Target Coverage | Priority |
|--------|------------------|-----------------|----------|
| coin_factory | 80% | 90% | Low |
| simple_dex | 30% | 95% | **HIGH** |
| flash_loan_pool | 40% | 95% | **HIGH** |
| price_oracle | 30% | 90% | **HIGH** |
| sandwich_attack | 0% | 100% | **CRITICAL** |
| flash_loan_attack | 0% | 100% | **CRITICAL** |
| retail_trader | 0% | 100% | **CRITICAL** |

---

## 🚀 Next Steps

1. **Immediate:** Add Phase 1 tests (core functionality)
2. **Critical:** Add Phase 2 tests (attack scenarios) - REQUIRED FOR THESIS
3. **Important:** Add Phase 3 tests (edge cases & security)
4. **Optional:** Add Phase 4 tests (complex analysis)

## ⚠️ Gaps for MEV Research

Để có thể giả lập MEV attacks cho thesis, **BẮT BUỘC** phải có:

1. ✅ Basic swap functionality (ĐÃ CÓ)
2. ✅ Flash loan borrow/repay (ĐÃ CÓ)
3. ❌ **Sandwich attack test** (THIẾU - CRITICAL)
4. ❌ **Flash loan arbitrage test** (THIẾU - CRITICAL)
5. ❌ **Victim behavior test** (THIẾU - CRITICAL)
6. ❌ **Oracle manipulation test** (THIẾU - HIGH)
7. ❌ **Profit/Loss calculation** (THIẾU - HIGH)

**Kết luận:** Test coverage hiện tại CHỈ ĐỦ cho basic functionality testing, CHƯA ĐỦ để chạy MEV simulation cho thesis. Cần bổ sung ít nhất 10-15 test cases nữa, đặc biệt là attack scenarios.
