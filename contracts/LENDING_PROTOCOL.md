# Compound-style Lending Protocol Implementation

## Overview

Full implementation of Compound Finance V2-style lending protocol in Move for Sui blockchain. This protocol enables:
- **Supply & Earn Interest**: Users deposit assets and receive cTokens
- **Borrow Against Collateral**: Use supplied assets as collateral to borrow other assets
- **Liquidations**: Underwater positions can be liquidated for protocol safety
- **Oracle Integration**: Price feeds from DEX pools (vulnerable to manipulation for research)

---

## Architecture

Based on **Compound Finance V2** architecture with these core components:

### 1. **Market (cToken equivalent)**
- Manages supply/borrow for single asset type
- Issues cTokens to represent supplied assets
- Tracks total borrows, reserves, and cash
- Implements interest rate model (Jump Rate Model)

### 2. **Position**
- Tracks user's cToken balance (supplied assets)
- Tracks borrow balance with accrued interest
- Links to specific market

### 3. **Price Oracle**
- Reads prices from DEX pools
- **Intentionally vulnerable** to manipulation for attack testing
- Used for collateral valuation and liquidation

---

## Core Features

### ✅ Supply Assets (Mint cTokens)

```move
public fun supply<T>(
    market: &mut Market<T>,
    amount: Coin<T>,
    clock: &Clock,
    ctx: &mut TxContext
): Position<T>
```

**How it works:**
1. User deposits underlying assets
2. System calculates exchange rate (underlying per cToken)
3. Mints cTokens based on exchange rate
4. cTokens automatically earn interest over time
5. Returns Position tracking cToken balance

**Example:**
```
Supply 10,000 USDC
Exchange rate: 1 cUSDC = 0.02 USDC (50:1)
Receive: 500,000 cUSDC tokens
```

---

### ✅ Withdraw Assets (Redeem cTokens)

```move
public fun withdraw<T>(
    market: &mut Market<T>,
    position: &mut Position<T>,
    c_tokens_to_burn: u64,
    clock: &Clock,
    ctx: &mut TxContext
): Coin<T>
```

**How it works:**
1. User specifies amount of cTokens to burn
2. System calculates underlying amount based on current exchange rate
3. Burns cTokens and returns underlying assets
4. Exchange rate increases over time (interest earning)

---

### ✅ Borrow Against Collateral

```move
public fun borrow<Collateral, Debt>(
    collateral_market: &mut Market<Collateral>,
    debt_market: &mut Market<Debt>,
    position: &mut Position<Collateral>,
    oracle: &Pool<Collateral, Debt>,
    borrow_amount: u64,
    clock: &Clock,
    ctx: &mut TxContext
): Coin<Debt>
```

**How it works:**
1. Reads collateral value from DEX oracle
2. Calculates max borrow = collateral_value * collateral_factor (75%)
3. Checks health factor > 1.0
4. Issues debt if safe
5. **Vulnerable to oracle manipulation**

**Attack Vector (Oracle Manipulation):**
```
Normal:
  1 WETH = $2000 → can borrow $1500 USDC (75% LTV)

After Manipulation (flash loan + large swap):
  1 WETH = $4000 → can borrow $3000 USDC

Real value: $2000 → Protocol loss: $1000
```

---

### ✅ Repay Debt

```move
public fun repay<T>(
    market: &mut Market<T>,
    position: &mut Position<T>,
    repayment: Coin<T>,
    clock: &Clock,
    ctx: &TxContext
)
```

**How it works:**
1. Accrues interest on outstanding debt
2. Accepts repayment coins
3. Updates borrow balance
4. Reduces total market borrows

---

### ✅ Liquidate Underwater Positions

```move
public fun liquidate<Collateral, Debt>(
    collateral_market: &mut Market<Collateral>,
    debt_market: &mut Market<Debt>,
    position: &mut Position<Collateral>,
    oracle: &Pool<Collateral, Debt>,
    repayment: Coin<Debt>,
    clock: &Clock,
    ctx: &mut TxContext
): Coin<Collateral>
```

**How it works:**
1. Checks if health_factor < 1.0 (underwater)
2. Liquidator repays up to 50% of debt (close factor)
3. Liquidator receives collateral + 5% bonus (liquidation incentive)
4. Position updated or closed

**Example:**
```
Position:
  - Collateral: 1 WETH ($2000)
  - Debt: $1800 USDC
  - Health factor: 0.88 (< 1.0, liquidatable)

Liquidation:
  - Liquidator repays: $900 USDC (50% close factor)
  - Liquidator receives: $945 worth of WETH (5% bonus)
  - Remaining position: $1055 collateral, $900 debt
```

---

## Interest Rate Model

### Jump Rate Model (Compound V2)

```
Utilization = Borrows / (Cash + Borrows)

If Utilization ≤ Kink (80%):
  Borrow Rate = Base Rate + (Utilization * Multiplier)

If Utilization > Kink:
  Borrow Rate = Base Rate + (Kink * Multiplier) +
                ((Utilization - Kink) * Jump Multiplier)

Supply Rate = Borrow Rate * Utilization * (1 - Reserve Factor)
```

### Parameters:
- **Base Rate**: 0% APY
- **Multiplier**: ~3% at kink
- **Jump Multiplier**: ~40% after kink
- **Kink**: 80% utilization
- **Reserve Factor**: 10% (portion to protocol reserves)

### Visual:
```
Borrow Rate (APY)
    |
40% |                    ╱
    |                  ╱
    |                ╱
3%  |            ___╱
    |        ___╱
0%  |____╱___________________
    0%   80%             100%
         Kink       Utilization
```

---

## Risk Parameters

| Parameter | Value | Description |
|-----------|-------|-------------|
| **Collateral Factor** | 75% | Max LTV ratio for borrowing |
| **Liquidation Threshold** | 80% | Health factor < 1.0 triggers liquidation |
| **Liquidation Incentive** | 5% | Bonus for liquidators |
| **Close Factor** | 50% | Max portion of debt liquidatable at once |
| **Reserve Factor** | 10% | Interest to protocol reserves |

---

## Events

### SupplyEvent
```move
public struct SupplyEvent<phantom T> has copy, drop {
    market_id: address,
    supplier: address,
    amount: u64,
    c_tokens_minted: u64,
    exchange_rate: u64,
    timestamp: u64,
}
```

### BorrowEvent
```move
public struct BorrowEvent<phantom T> has copy, drop {
    market_id: address,
    borrower: address,
    position_id: address,
    borrow_amount: u64,
    collateral_value: u64,
    oracle_price: u64,      // ← Price at borrow time
    health_factor: u64,     // ← Risk metric
    total_borrows: u64,
    timestamp: u64,
}
```

### LiquidationEvent
```move
public struct LiquidationEvent<phantom T> has copy, drop {
    market_id: address,
    liquidator: address,
    borrower: address,
    position_id: address,
    debt_repaid: u64,
    collateral_seized: u64,
    liquidation_incentive: u64,
    health_factor_before: u64,
    protocol_loss: u64,     // ← Bad debt if any
    timestamp: u64,
}
```

### AccrueInterestEvent
```move
public struct AccrueInterestEvent<phantom T> has copy, drop {
    market_id: address,
    borrow_rate: u64,
    supply_rate: u64,
    total_borrows: u64,
    total_reserves: u64,
    borrow_index: u64,
    timestamp: u64,
}
```

---

## Attack Scenarios for Detection Testing

### 1. Oracle Manipulation Attack

**Attack Flow:**
```
1. Borrow 10M USDC flash loan
2. Swap 5M USDC → WETH (push WETH price from $2000 to $4000)
3. Supply WETH to lending market
4. Borrow 3M USDC (based on inflated $4000 price)
5. Swap WETH → USDC (price returns to $2000)
6. Repay flash loan
7. Keep 3M USDC borrowed
8. Lending protocol has bad debt ($1M loss)
```

**Detection Signals:**
- Flash loan + large swap + lending borrow in same tx
- Borrow event with abnormally high oracle_price
- Large collateral_value spike
- Subsequent price drop
- Protocol_loss > 0 in liquidation event

---

### 2. Liquidation Front-running

**Attack Flow:**
```
1. Monitor mempool for liquidatable positions
2. Front-run liquidation transactions
3. Profit from 5% liquidation bonus
```

**Detection Signals:**
- Multiple liquidation attempts for same position
- Liquidations within same checkpoint
- High liquidator profit relative to position size

---

### 3. Bad Debt Accumulation

**Scenario:**
```
1. Price crashes rapidly
2. Positions become underwater before liquidation
3. Collateral value < debt
4. Protocol accumulates bad debt
```

**Detection Signals:**
- health_factor < 0.5 (critically underwater)
- Liquidation with protocol_loss > 0
- Total borrows > total collateral value

---

## Integration with Detection System

### New Analyzer: `oracle_manipulation.rs`

```rust
pub struct OracleManipulationAnalyzer;

impl OracleManipulationAnalyzer {
    pub fn analyze(tx: &ExecutedTransaction) -> Option<RiskEvent> {
        // Pattern: Flash loan → Price spike → Lending borrow

        let has_flash_loan = detect_flash_loan(tx);
        let large_swaps = extract_large_swaps(tx);
        let lending_borrows = extract_borrow_events(tx);

        // Check temporal relationship
        if has_flash_loan && !large_swaps.is_empty() && !lending_borrows.is_empty() {
            let swap_time = large_swaps[0].timestamp;
            let borrow_time = lending_borrows[0].timestamp;
            let oracle_price = lending_borrows[0].oracle_price;

            // Borrow happened after price manipulation
            if borrow_time > swap_time {
                // Calculate price deviation
                let normal_price = get_historical_price(...);
                let price_inflation = (oracle_price - normal_price) / normal_price;

                if price_inflation > 0.20 {  // > 20% inflation
                    return Some(RiskEvent {
                        risk_type: RiskType::OracleManipulation,
                        level: RiskLevel::Critical,
                        description: format!(
                            "Oracle manipulation: {}% price inflation, ${} protocol loss potential",
                            price_inflation * 100,
                            estimate_protocol_loss(...)
                        ),
                        details: json!({
                            "flash_loan_amount": ...,
                            "oracle_price": oracle_price,
                            "normal_price": normal_price,
                            "price_inflation_pct": price_inflation,
                            "borrowed_amount": lending_borrows[0].amount,
                            "health_factor": lending_borrows[0].health_factor,
                        })
                    });
                }
            }
        }

        None
    }
}
```

---

## Testing

### Unit Tests

```bash
cd contracts
sui move test --filter lending_tests
```

### Test Coverage:

1. ✅ **test_supply_and_withdraw** - Basic supply/withdraw flow
2. ✅ **test_borrow_and_repay** - Collateral-based borrowing
3. ✅ **test_oracle_manipulation_attack** - Flash loan oracle attack
4. ✅ **test_liquidation** - Liquidation mechanism

---

## Deployment Steps

### 1. Deploy Contracts

```bash
cd contracts
sui client publish --gas-budget 500000000
```

### 2. Create Markets

```bash
# Create USDC market
sui client call \
  --package $PACKAGE_ID \
  --module compound_market \
  --function create_market \
  --type-args $PACKAGE_ID::usdc::USDC \
  --args $USDC_INITIAL_LIQUIDITY $ORACLE_POOL_ID 7500 1000 \
  --gas-budget 10000000

# Create WETH market
sui client call \
  --package $PACKAGE_ID \
  --module compound_market \
  --function create_market \
  --type-args $PACKAGE_ID::weth::WETH \
  --args $WETH_INITIAL_LIQUIDITY $ORACLE_POOL_ID 7500 1000 \
  --gas-budget 10000000
```

### 3. Save Object IDs

Add to `.env`:
```bash
USDC_LENDING_MARKET=0x...
WETH_LENDING_MARKET=0x...
```

---

## Comparison with Compound V2

| Feature | Compound V2 | Our Implementation |
|---------|-------------|-------------------|
| **cToken Model** | ✅ | ✅ |
| **Supply/Borrow** | ✅ | ✅ |
| **Interest Accrual** | ✅ | ✅ |
| **Jump Rate Model** | ✅ | ✅ |
| **Liquidations** | ✅ | ✅ |
| **Price Oracle** | Chainlink | DEX pools (vulnerable) |
| **Comptroller** | Separate contract | Integrated in Market |
| **Multiple Assets** | ✅ | ✅ (via generics) |
| **Governance** | COMP token | N/A (research) |

---

## Academic Value

This implementation provides:

1. **Realistic Attack Scenarios**: Full lending protocol for testing flash loan attacks
2. **Oracle Vulnerability**: Intentionally uses DEX oracle for manipulation testing
3. **Production-Quality Code**: Based on battle-tested Compound V2 architecture
4. **Comprehensive Events**: Rich event data for detection algorithm development
5. **Research Focus**: Designed to demonstrate attacks, not production deployment

---

## Security Considerations

### ⚠️ Intentional Vulnerabilities (for research):

1. **DEX Price Oracle**: Vulnerable to manipulation via flash loans
2. **No Time-Weighted Average**: Uses spot price instead of TWAP
3. **No Oracle Deviation Check**: Doesn't validate price sanity
4. **Single Price Source**: No fallback or comparison with other sources

### ✅ Production Features Included:

1. **Liquidation Mechanism**: Proper liquidation incentives and close factors
2. **Interest Rate Model**: Jump rate model from Compound
3. **cToken Exchange Rate**: Properly tracks supply interest
4. **Health Factor Calculation**: Correct risk assessment
5. **Reserve Accumulation**: Protocol fee collection

---

## References

1. **Compound Finance Whitepaper**: https://compound.finance/documents/Compound.Whitepaper.pdf
2. **Compound V2 Docs**: https://docs.compound.finance/v2/
3. **Compound GitHub**: https://github.com/compound-finance/compound-protocol
4. **Qin et al. (2021)**: "Attacking the DeFi Ecosystem with Flash Loans"
5. **Perez et al. (2021)**: "The Decentralized Financial Crisis"

---

## License

Apache-2.0

---

## Contact

For questions about implementation or attack scenarios:
- See inline code comments for detailed explanations
- Review test cases for usage examples
- Check DETECTION_RESEARCH.md for detection algorithms
