# Compound Market

## Overview

The `compound_market` module implements a Compound V2-style lending and borrowing protocol on Sui. It enables users to supply assets to earn interest, borrow against collateral, and participate in liquidations of undercollateralized positions. The protocol uses a cToken model where suppliers receive interest-bearing tokens representing their share of the pool.

This implementation is designed for DeFi attack simulation and research, featuring a **vulnerable oracle design** that uses DEX spot prices for collateral valuation. This intentional vulnerability allows researchers to study price manipulation attacks, oracle manipulation, and flash loan attacks in a controlled environment.

The module maintains interest rate calculations based on utilization, implements a liquidation mechanism with incentives, and tracks both supply and borrow positions through the `Position` object.

## Key Public Functions

### Market Creation & Configuration

#### create_market

```move
public fun create_market<T>(
    initial_liquidity: Coin<T>,
    oracle_pool_id: address,
    collateral_factor: u64,
    reserve_factor: u64,
    clock: &Clock,
    ctx: &mut TxContext
): Market<T>
```

Creates a new lending market for a specific asset type with initial liquidity and configuration parameters.

**Input Parameters:**

| Name | Type | Description |
|------|------|-------------|
| initial_liquidity | Coin\<T\> | Initial assets to seed the market |
| oracle_pool_id | address | DEX pool address for price oracle (VULNERABLE) |
| collateral_factor | u64 | Maximum LTV ratio in bps (e.g., 7500 = 75%) |
| reserve_factor | u64 | Portion of interest to reserves in bps (e.g., 1000 = 10%) |
| clock | &Clock | Sui clock for timestamp |
| ctx | &mut TxContext | Transaction context |

**Return Value:**

| Type | Description |
|------|-------------|
| Market\<T\> | Newly created market object |

**Default Parameters:**
- Liquidation threshold: 8000 bps (80%)
- Base rate: 0% APY
- Kink point: 8000 bps (80% utilization)
- Initial exchange rate: 0.02 (50 cTokens per 1 underlying)

---

### Supply Functions

#### supply

```move
public fun supply<T>(
    market: &mut Market<T>,
    amount: Coin<T>,
    clock: &Clock,
    ctx: &mut TxContext
): Position<T>
```

Supply assets to the market and receive a position with cTokens representing the supplied amount plus accrued interest.

**Input Parameters:**

| Name | Type | Description |
|------|------|-------------|
| market | &mut Market\<T\> | The lending market |
| amount | Coin\<T\> | Assets to supply |
| clock | &Clock | Sui clock for interest accrual |
| ctx | &mut TxContext | Transaction context |

**Return Value:**

| Type | Description |
|------|-------------|
| Position\<T\> | Position object tracking cTokens and borrows |

**Behavior:**
- Accrues interest before calculating exchange rate
- Calculates cTokens to mint based on current exchange rate
- Updates market total supply and total cash
- Creates a new position with cToken balance
- Emits `SupplyEvent`

**Exchange Rate Calculation:**
```
cTokens = (supply_amount * PRECISION) / exchange_rate
exchange_rate = (total_cash + total_borrows - total_reserves) / total_supply
```

**Error Codes:**
- `E_INVALID_AMOUNT` (4): Supply amount must be greater than zero

---

#### withdraw

```move
public fun withdraw<T>(
    market: &mut Market<T>,
    position: &mut Position<T>,
    c_tokens_to_burn: u64,
    clock: &Clock,
    ctx: &mut TxContext
): Coin<T>
```

Withdraw supplied assets by burning cTokens from a position.

**Input Parameters:**

| Name | Type | Description |
|------|------|-------------|
| market | &mut Market\<T\> | The lending market |
| position | &mut Position\<T\> | User's position |
| c_tokens_to_burn | u64 | Amount of cTokens to redeem |
| clock | &Clock | Sui clock for interest accrual |
| ctx | &mut TxContext | Transaction context |

**Return Value:**

| Type | Description |
|------|-------------|
| Coin\<T\> | Underlying assets withdrawn |

**Behavior:**
- Accrues interest to update exchange rate
- Calculates underlying amount based on exchange rate
- Checks market has sufficient liquidity
- Burns cTokens from position
- Transfers underlying assets to user

**Error Codes:**
- `E_INVALID_AMOUNT` (4): Burn amount exceeds position balance
- `E_INSUFFICIENT_LIQUIDITY` (1): Market does not have enough cash

---

### Borrow Functions

#### borrow

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

Borrow assets against collateral using a DEX pool as price oracle. **This function is vulnerable to price manipulation attacks by design.**

**Input Parameters:**

| Name | Type | Description |
|------|------|-------------|
| collateral_market | &mut Market\<Collateral\> | Market of collateral asset |
| debt_market | &mut Market\<Debt\> | Market of asset to borrow |
| position | &mut Position\<Collateral\> | User's collateral position |
| oracle | &Pool\<Collateral, Debt\> | DEX pool for price (VULNERABLE) |
| borrow_amount | u64 | Amount of debt asset to borrow |
| clock | &Clock | Sui clock for interest accrual |
| ctx | &mut TxContext | Transaction context |

**Return Value:**

| Type | Description |
|------|-------------|
| Coin\<Debt\> | Borrowed assets |

**Behavior:**
- Accrues interest on both collateral and debt markets
- Retrieves spot price from DEX pool (**VULNERABLE to manipulation**)
- Calculates collateral value using oracle price
- Validates borrow does not exceed collateral factor limit
- Updates position borrow balance and index
- Updates market total borrows
- Calculates and emits health factor
- Transfers borrowed assets to user

**Collateral Calculation:**
```
underlying_collateral = (c_token_balance * exchange_rate) / PRECISION
collateral_value = (underlying_collateral * oracle_price) / PRECISION
max_borrow = (collateral_value * collateral_factor) / 10000
```

**Health Factor:**
```
health_factor = (collateral_value * liquidation_threshold / 10000) / debt
```

**Error Codes:**
- `E_INVALID_AMOUNT` (4): Borrow amount must be greater than zero
- `E_INSUFFICIENT_COLLATERAL` (2): Borrow exceeds collateral capacity
- `E_INSUFFICIENT_LIQUIDITY` (1): Market does not have enough cash

---

#### repay

```move
public fun repay<Collateral, Debt>(
    market: &mut Market<Debt>,
    position: &mut Position<Collateral>,
    repayment: Coin<Debt>,
    clock: &Clock,
    ctx: &TxContext
)
```

Repay borrowed assets with accrued interest.

**Input Parameters:**

| Name | Type | Description |
|------|------|-------------|
| market | &mut Market\<Debt\> | The debt market |
| position | &mut Position\<Collateral\> | User's position with debt |
| repayment | Coin\<Debt\> | Assets to repay |
| clock | &Clock | Sui clock for interest accrual |
| ctx | &TxContext | Transaction context |

**Behavior:**
- Accrues interest to update borrow index
- Calculates total debt including accrued interest
- Repays up to total debt (excess is still consumed)
- Updates position borrow balance and index
- Reduces market total borrows
- Adds repayment to market cash
- Emits `RepayEvent`

**Interest Calculation:**
```
accrued_interest = principal * (new_index - old_index) / old_index
total_debt = borrow_balance + accrued_interest
```

---

### Liquidation Functions

#### liquidate

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

Liquidate an undercollateralized position by repaying debt and seizing collateral with a liquidation bonus.

**Input Parameters:**

| Name | Type | Description |
|------|------|-------------|
| collateral_market | &mut Market\<Collateral\> | Market of collateral to seize |
| debt_market | &mut Market\<Debt\> | Market of debt to repay |
| position | &mut Position\<Collateral\> | Position to liquidate |
| oracle | &Pool\<Collateral, Debt\> | DEX pool for price |
| repayment | Coin\<Debt\> | Debt assets to repay |
| clock | &Clock | Sui clock for interest accrual |
| ctx | &mut TxContext | Transaction context |

**Return Value:**

| Type | Description |
|------|-------------|
| Coin\<Collateral\> | Seized collateral including liquidation bonus |

**Behavior:**
- Accrues interest on both markets
- Retrieves oracle price from DEX pool
- Calculates collateral value and total debt
- Validates health factor < 1.0 (position is underwater)
- Applies close factor (max 50% of debt can be repaid)
- Calculates collateral to seize with 5% liquidation incentive
- Updates position balances
- Updates market states
- Emits `LiquidationEvent` with protocol loss tracking

**Liquidation Calculations:**
```
max_close = total_debt * CLOSE_FACTOR / 10000  // 50% max
seize_value = repay_amount * 1.05  // 5% liquidation incentive
seize_amount = seize_value / oracle_price
c_tokens_to_seize = seize_amount / exchange_rate
```

**Error Codes:**
- `E_POSITION_HEALTHY` (3): Health factor >= 1.0, position is not liquidatable

**Constants:**
- `LIQUIDATION_INCENTIVE`: 500 bps (5%)
- `CLOSE_FACTOR`: 5000 bps (50%)

---

## View Functions

### get_exchange_rate

```move
public fun get_exchange_rate<T>(market: &Market<T>): u64
```

Returns the current exchange rate of underlying assets per cToken.

**Input Parameters:**

| Name | Type | Description |
|------|------|-------------|
| market | &Market\<T\> | The lending market |

**Return Value:**

| Type | Description |
|------|-------------|
| u64 | Exchange rate (underlying per cToken) with PRECISION (1e9) |

**Formula:**
```
exchange_rate = (total_cash + total_borrows - total_reserves) / total_supply
```

Initial rate is 0.02 (20_000_000 with 1e9 precision).

---

### get_oracle_price

```move
public fun get_oracle_price<C, D>(oracle: &Pool<C, D>): u64
```

**VULNERABLE FUNCTION**: Returns the spot price from a DEX pool. Susceptible to price manipulation attacks.

**Input Parameters:**

| Name | Type | Description |
|------|------|-------------|
| oracle | &Pool\<C, D\> | DEX pool used as oracle |

**Return Value:**

| Type | Description |
|------|-------------|
| u64 | Spot price (debt per unit of collateral) with PRECISION |

**Formula:**
```
price = reserve_debt / reserve_collateral
```

**⚠️ Security Warning**: This oracle design is intentionally vulnerable for research purposes. In production:
- Use TWAP (Time-Weighted Average Price) oracles
- Implement price deviation limits
- Use multiple oracle sources
- Add manipulation detection mechanisms

---

### calculate_health_factor

```move
public fun calculate_health_factor(
    collateral_value: u64,
    debt: u64,
    liquidation_threshold: u64
): u64
```

Calculates the health factor of a position.

**Input Parameters:**

| Name | Type | Description |
|------|------|-------------|
| collateral_value | u64 | Total collateral value in debt asset |
| debt | u64 | Total debt amount |
| liquidation_threshold | u64 | Liquidation threshold in bps |

**Return Value:**

| Type | Description |
|------|-------------|
| u64 | Health factor in bps (< 10000 = liquidatable) |

**Formula:**
```
health_factor = (collateral_value * liquidation_threshold / 10000) / debt
```

**Interpretation:**
- health_factor >= 10000 (1.0): Position is healthy
- health_factor < 10000 (1.0): Position is liquidatable
- health_factor == 0: No debt (very healthy)

---

### get_total_borrows

```move
public fun get_total_borrows<T>(market: &Market<T>): u64
```

Returns the total amount borrowed from the market.

---

### get_total_cash

```move
public fun get_total_cash<T>(market: &Market<T>): u64
```

Returns the total cash available in the market.

---

### get_position_collateral

```move
public fun get_position_collateral<T>(position: &Position<T>): u64
```

Returns the cToken balance (collateral) in a position.

---

### get_position_debt

```move
public fun get_position_debt<T>(position: &Position<T>): u64
```

Returns the borrow balance (debt) in a position.

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

Emitted when a user supplies assets to the market.

---

### BorrowEvent

```move
public struct BorrowEvent<phantom T> has copy, drop {
    market_id: address,
    borrower: address,
    position_id: address,
    borrow_amount: u64,
    collateral_value: u64,
    oracle_price: u64,
    health_factor: u64,
    total_borrows: u64,
    timestamp: u64,
}
```

Emitted when a user borrows assets. Includes critical risk metrics.

---

### RepayEvent

```move
public struct RepayEvent<phantom T> has copy, drop {
    market_id: address,
    borrower: address,
    position_id: address,
    repay_amount: u64,
    remaining_debt: u64,
    timestamp: u64,
}
```

Emitted when debt is repaid.

---

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
    protocol_loss: u64,
    timestamp: u64,
}
```

Emitted when a position is liquidated. Tracks protocol losses from bad debt.

---

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

Emitted when interest is accrued to the market.

---

## Core Data Structures

### Market

```move
public struct Market<phantom T> has key, store {
    id: UID,
    total_cash: Balance<T>,
    total_borrows: u64,
    total_reserves: Balance<T>,
    total_supply: u64,
    reserve_factor: u64,
    collateral_factor: u64,
    liquidation_threshold: u64,
    base_rate_per_second: u64,
    multiplier_per_second: u64,
    jump_multiplier_per_second: u64,
    kink: u64,
    accrual_block_timestamp: u64,
    borrow_index: u64,
    oracle_pool_id: address,
}
```

Represents a lending market for a specific asset.

**Key Fields:**

| Field | Description |
|-------|-------------|
| collateral_factor | Max LTV (e.g., 7500 = 75%) |
| liquidation_threshold | Liquidation trigger (e.g., 8000 = 80%) |
| kink | Optimal utilization rate (e.g., 8000 = 80%) |
| borrow_index | Cumulative interest index for debt tracking |
| oracle_pool_id | DEX pool address for price oracle |

---

### Position

```move
public struct Position<phantom T> has key, store {
    id: UID,
    market_id: address,
    owner: address,
    c_token_balance: u64,
    borrow_balance: u64,
    borrow_index: u64,
}
```

Represents a user's position in a market.

**Fields:**

| Field | Description |
|-------|-------------|
| c_token_balance | Amount of cTokens (collateral) owned |
| borrow_balance | Amount borrowed (debt) |
| borrow_index | Borrow index at last interaction (for interest calc) |

---

## Interest Rate Model

The protocol uses Compound's Jump Rate Model for dynamic interest rates based on utilization.

### Utilization Rate

```
utilization = total_borrows / (total_cash + total_borrows)
```

### Borrow Rate

Below kink (< 80% utilization):
```
borrow_rate = base_rate + (utilization * multiplier)
```

Above kink (>= 80% utilization):
```
borrow_rate = base_rate + (kink * multiplier) + (excess_util * jump_multiplier)
```

### Supply Rate

```
supply_rate = borrow_rate * utilization * (1 - reserve_factor)
```

### Default Parameters

| Parameter | Value | Description |
|-----------|-------|-------------|
| Base Rate | 0% | Minimum borrow rate |
| Multiplier | ~3% at kink | Rate increase below kink |
| Jump Multiplier | ~40% after kink | Steep rate increase above kink |
| Kink | 80% | Optimal utilization point |
| Reserve Factor | 10% | Portion of interest to reserves |

---

## Interest Accrual

Interest accrues per second since the last update:

```
time_delta = current_time - last_accrual_time
interest_factor = borrow_rate * time_delta
interest_accumulated = total_borrows * interest_factor / PRECISION
new_total_borrows = total_borrows + interest_accumulated
new_borrow_index = old_index + (old_index * interest_factor / PRECISION)
```

Interest is accrued automatically on every operation (supply, borrow, repay, liquidate).

---

## Liquidation Mechanism

### Liquidation Conditions

A position can be liquidated when:
```
health_factor < 1.0 (10000 bps)
```

### Liquidation Incentive

Liquidators receive a 5% bonus:
```
collateral_seized = debt_repaid * 1.05 * (1 / oracle_price)
```

### Close Factor

Maximum 50% of debt can be repaid in a single liquidation:
```
max_repay = total_debt * 0.5
```

### Bad Debt Handling

If collateral is insufficient to cover debt + incentive, the protocol tracks the loss in `LiquidationEvent.protocol_loss`.

---

## Security Considerations

### ⚠️ Intentional Vulnerabilities (For Research)

This implementation contains intentional vulnerabilities for DeFi attack simulation:

1. **Spot Price Oracle**: Uses DEX spot price instead of TWAP
   - Vulnerable to flash loan price manipulation
   - Can be exploited for undercollateralized borrowing
   - Enables liquidation attacks

2. **No Price Deviation Limits**: No maximum price change protection

3. **Single Oracle Source**: No redundancy or fallback oracles

### Attack Scenarios to Study

1. **Flash Loan Attack**:
   - Manipulate DEX price with flash loan
   - Borrow maximum against inflated collateral
   - Default on loan

2. **Liquidation Manipulation**:
   - Manipulate price to trigger false liquidations
   - Seize collateral at unfair prices

3. **Oracle Front-Running**:
   - Monitor pending price-moving transactions
   - Front-run with borrow/liquidate operations

### Production Recommendations

For production deployments, implement:

- **TWAP Oracles**: Time-weighted average prices
- **Chainlink Integration**: Decentralized oracle networks
- **Price Deviation Caps**: Maximum acceptable price changes
- **Circuit Breakers**: Pause functionality for anomalies
- **Multi-Oracle Redundancy**: Multiple price sources
- **Sanity Checks**: Validate prices against reasonable bounds

---

## Comparison to Compound V2

### Similarities

| Feature | Compound V2 | This Implementation |
|---------|-------------|---------------------|
| cToken Model | ✅ | ✅ (via Position object) |
| Exchange Rate | ✅ | ✅ |
| Jump Rate Model | ✅ | ✅ |
| Liquidation Incentive | ✅ 8% | ✅ 5% |
| Close Factor | ✅ 50% | ✅ 50% |
| Reserve Factor | ✅ | ✅ |

### Key Differences

| Feature | Compound V2 | This Implementation |
|---------|-------------|---------------------|
| Language | Solidity | Move |
| Blockchain | Ethereum | Sui |
| Oracle | Chainlink/Uniswap TWAP | DEX Spot (VULNERABLE) |
| cToken Transfer | ERC-20 transfers | Position object ownership |
| Comptroller | Separate contract | Integrated in Market |
| Multi-Asset Collateral | Yes | No (single market) |

### Move-Specific Features

1. **Object-Centric Design**: Positions are objects, not just balance mappings
2. **Explicit Ownership**: Move's ownership system prevents unauthorized access
3. **No Reentrancy**: Move's execution model eliminates reentrancy risks
4. **Type Safety**: Generics ensure type correctness at compile time

---

## Usage Examples

### Supply and Borrow Flow

```move
// 1. Supply collateral
let usdc_coins = /* obtain USDC */;
let position = supply(&mut usdc_market, usdc_coins, clock, ctx);

// 2. Borrow against collateral
let eth_borrowed = borrow(
    &mut usdc_market,  // collateral market
    &mut eth_market,   // debt market
    &mut position,     // collateral position
    &oracle_pool,      // DEX pool oracle
    1000,              // borrow amount
    clock,
    ctx
);

// 3. Use borrowed ETH...

// 4. Repay debt
let eth_repayment = /* obtain ETH for repayment */;
repay(&mut eth_market, &mut position, eth_repayment, clock, ctx);

// 5. Withdraw collateral
let usdc_back = withdraw(&mut usdc_market, &mut position, c_tokens, clock, ctx);
```

### Liquidation Example

```move
// Monitor positions for health_factor < 1.0
if (health_factor < 10000) {
    // Prepare repayment (up to 50% of debt)
    let debt_repayment = /* obtain debt asset */;

    // Liquidate and receive collateral + 5% bonus
    let collateral_seized = liquidate(
        &mut collateral_market,
        &mut debt_market,
        &mut underwater_position,
        &oracle_pool,
        debt_repayment,
        clock,
        ctx
    );

    // Profit = 5% liquidation bonus
}
```

---

## Error Codes

| Code | Constant | Description |
|------|----------|-------------|
| 1 | E_INSUFFICIENT_LIQUIDITY | Market does not have enough cash |
| 2 | E_INSUFFICIENT_COLLATERAL | Borrow exceeds collateral capacity |
| 3 | E_POSITION_HEALTHY | Position is healthy, cannot liquidate |
| 4 | E_INVALID_AMOUNT | Invalid amount (zero or exceeds balance) |

---

## Constants

| Constant | Value | Description |
|----------|-------|-------------|
| PRECISION | 1_000_000_000 | 1e9 for calculations |
| BPS_PRECISION | 10000 | Basis points (100%) |
| INITIAL_EXCHANGE_RATE | 20_000_000 | 0.02 * 1e9 (1:0.02 = 50:1) |
| LIQUIDATION_INCENTIVE | 500 | 5% in bps |
| CLOSE_FACTOR | 5000 | 50% in bps |

---

## References

- [Compound V2 Whitepaper](https://compound.finance/documents/Compound.Whitepaper.pdf)
- [Compound V2 Docs](https://docs.compound.finance/)
- [Move Language Book](https://move-language.github.io/move/)
- [Sui Documentation](https://docs.sui.io/)
