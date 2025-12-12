# Simple DEX

## Overview

The `simple_dex` module implements an Automated Market Maker (AMM) decentralized exchange using the constant product formula popularized by Uniswap V2. It enables permissionless trading between token pairs, liquidity provision, and serves as a price oracle for other DeFi protocols.

The DEX maintains liquidity pools with two token reserves and uses the `x * y = k` invariant to determine swap prices. Liquidity providers earn fees on every trade proportional to their pool share. The protocol supports:

- **Permissionless Pool Creation**: Anyone can create trading pairs
- **Automated Market Making**: Constant product formula for pricing
- **Liquidity Provision**: Earn trading fees as a liquidity provider
- **TWAP Oracle Integration**: Time-weighted average price tracking
- **Price Impact Tracking**: Monitor slippage and market impact

This implementation is designed for DeFi research and includes features for studying price manipulation, MEV (Maximal Extractable Value), and sandwich attacks.

## Key Public Functions

### Pool Creation

#### create_pool

```move
public fun create_pool<TokenA, TokenB>(
    token_a: Coin<TokenA>,
    token_b: Coin<TokenB>,
    ctx: &mut TxContext
)
```

Creates a new liquidity pool for a token pair with initial liquidity.

**Input Parameters:**

| Name | Type | Description |
|------|------|-------------|
| token_a | Coin\<TokenA\> | Initial liquidity for TokenA |
| token_b | Coin\<TokenB\> | Initial liquidity for TokenB |
| ctx | &mut TxContext | Transaction context |

**Behavior:**
- Validates both amounts are greater than zero
- Calculates initial LP tokens as `sqrt(amount_a * amount_b)`
- Burns minimum liquidity (1000 LP tokens) to prevent exploitation
- Creates a shared Pool object with 0.3% fee rate
- Emits `PoolCreated` event

**Initial LP Token Calculation:**
```
initial_liquidity = sqrt(amount_a * amount_b) - 1000
```

The first 1000 LP tokens are permanently burned to prevent attacks where a malicious actor could manipulate the pool by being the sole LP.

**Error Codes:**
- `E_INVALID_AMOUNT` (3): Token amounts must be greater than zero
- `E_ZERO_LIQUIDITY` (4): Initial liquidity too small (< 1000)

---

### Swap Functions

#### swap_a_to_b

```move
public fun swap_a_to_b<TokenA, TokenB>(
    pool: &mut Pool<TokenA, TokenB>,
    token_a: Coin<TokenA>,
    min_out: u64,
    ctx: &mut TxContext
): Coin<TokenB>
```

Swaps TokenA for TokenB using the constant product formula.

**Input Parameters:**

| Name | Type | Description |
|------|------|-------------|
| pool | &mut Pool\<TokenA, TokenB\> | The liquidity pool |
| token_a | Coin\<TokenA\> | Input tokens to swap |
| min_out | u64 | Minimum output tokens (slippage protection) |
| ctx | &mut TxContext | Transaction context |

**Return Value:**

| Type | Description |
|------|-------------|
| Coin\<TokenB\> | Output tokens received |

**Behavior:**
- Validates input amount > 0
- Calculates output using constant product formula with 0.3% fee
- Checks output meets minimum requirement (slippage protection)
- Validates sufficient pool liquidity
- Updates pool reserves
- Emits `SwapExecuted` event with price impact data

**Swap Formula (Constant Product with Fees):**
```
amount_in_with_fee = amount_in * (10000 - fee_rate)  // 9970 for 0.3% fee
numerator = amount_in_with_fee * reserve_b
denominator = reserve_a * 10000 + amount_in_with_fee
amount_out = numerator / denominator
```

**Error Codes:**
- `E_INVALID_AMOUNT` (3): Input amount must be greater than zero
- `E_SLIPPAGE_TOO_HIGH` (2): Output less than min_out
- `E_INSUFFICIENT_LIQUIDITY` (1): Output exceeds pool reserves

---

#### swap_b_to_a

```move
public fun swap_b_to_a<TokenA, TokenB>(
    pool: &mut Pool<TokenA, TokenB>,
    token_b: Coin<TokenB>,
    min_out: u64,
    ctx: &mut TxContext
): Coin<TokenA>
```

Swaps TokenB for TokenA using the constant product formula. Mirror function of `swap_a_to_b`.

**Input Parameters:**

| Name | Type | Description |
|------|------|-------------|
| pool | &mut Pool\<TokenA, TokenB\> | The liquidity pool |
| token_b | Coin\<TokenB\> | Input tokens to swap |
| min_out | u64 | Minimum output tokens (slippage protection) |
| ctx | &mut TxContext | Transaction context |

**Return Value:**

| Type | Description |
|------|-------------|
| Coin\<TokenA\> | Output tokens received |

---

#### swap_a_to_b_with_twap

```move
public fun swap_a_to_b_with_twap<TokenA, TokenB>(
    pool: &mut Pool<TokenA, TokenB>,
    oracle: &mut TWAPOracle<TokenA, TokenB>,
    token_a: Coin<TokenA>,
    min_out: u64,
    clock: &Clock,
    ctx: &mut TxContext
): Coin<TokenB>
```

Swaps TokenA for TokenB and updates the TWAP oracle with post-swap reserves.

**Input Parameters:**

| Name | Type | Description |
|------|------|-------------|
| pool | &mut Pool\<TokenA, TokenB\> | The liquidity pool |
| oracle | &mut TWAPOracle\<TokenA, TokenB\> | TWAP oracle to update |
| token_a | Coin\<TokenA\> | Input tokens to swap |
| min_out | u64 | Minimum output tokens |
| clock | &Clock | Sui clock for timestamp |
| ctx | &mut TxContext | Transaction context |

**Return Value:**

| Type | Description |
|------|-------------|
| Coin\<TokenB\> | Output tokens received |

**Behavior:**
- Executes swap using `swap_a_to_b`
- Updates TWAP oracle with new reserves after swap
- Returns output tokens

This function is useful for maintaining accurate time-weighted average prices while trading.

---

#### swap_b_to_a_with_twap

```move
public fun swap_b_to_a_with_twap<TokenA, TokenB>(
    pool: &mut Pool<TokenA, TokenB>,
    oracle: &mut TWAPOracle<TokenA, TokenB>,
    token_b: Coin<TokenB>,
    min_out: u64,
    clock: &Clock,
    ctx: &mut TxContext
): Coin<TokenA>
```

Swaps TokenB for TokenA and updates the TWAP oracle. Mirror function of `swap_a_to_b_with_twap`.

---

### Liquidity Functions

#### add_liquidity

```move
entry fun add_liquidity<TokenA, TokenB>(
    pool: &mut Pool<TokenA, TokenB>,
    token_a: Coin<TokenA>,
    token_b: Coin<TokenB>,
    min_liquidity: u64,
    ctx: &TxContext
)
```

Adds liquidity to the pool and mints LP tokens proportional to the deposit.

**Input Parameters:**

| Name | Type | Description |
|------|------|-------------|
| pool | &mut Pool\<TokenA, TokenB\> | The liquidity pool |
| token_a | Coin\<TokenA\> | TokenA to add |
| token_b | Coin\<TokenB\> | TokenB to add |
| min_liquidity | u64 | Minimum LP tokens to mint (slippage protection) |
| ctx | &TxContext | Transaction context |

**Behavior:**
- Calculates LP tokens based on proportional contribution to reserves
- For first deposit: `liquidity = sqrt(amount_a * amount_b)`
- For subsequent deposits: `liquidity = min(amount_a * lp_supply / reserve_a, amount_b * lp_supply / reserve_b)`
- Validates LP tokens meet minimum requirement
- Updates pool reserves and LP supply
- Emits `LiquidityAdded` event

**LP Token Calculation:**

First liquidity addition:
```
liquidity = sqrt(amount_a * amount_b)
```

Subsequent additions:
```
liquidity_a = (amount_a * lp_supply) / reserve_a
liquidity_b = (amount_b * lp_supply) / reserve_b
liquidity = min(liquidity_a, liquidity_b)
```

**Error Codes:**
- `E_INSUFFICIENT_LIQUIDITY` (1): Minted LP tokens less than min_liquidity

**Note:** This is an `entry` function, meaning LP tokens are not returned as objects. In production, you would typically return an LP token object for the user to hold.

---

#### remove_liquidity

```move
public fun remove_liquidity<TokenA, TokenB>(
    pool: &mut Pool<TokenA, TokenB>,
    lp_tokens: u64,
    min_a: u64,
    min_b: u64,
    ctx: &mut TxContext
): (Coin<TokenA>, Coin<TokenB>)
```

Removes liquidity from the pool by burning LP tokens and receiving proportional reserves.

**Input Parameters:**

| Name | Type | Description |
|------|------|-------------|
| pool | &mut Pool\<TokenA, TokenB\> | The liquidity pool |
| lp_tokens | u64 | Amount of LP tokens to burn |
| min_a | u64 | Minimum TokenA to receive (slippage protection) |
| min_b | u64 | Minimum TokenB to receive (slippage protection) |
| ctx | &mut TxContext | Transaction context |

**Return Values:**

| Position | Type | Description |
|----------|------|-------------|
| 0 | Coin\<TokenA\> | Withdrawn TokenA |
| 1 | Coin\<TokenB\> | Withdrawn TokenB |

**Behavior:**
- Validates LP tokens > 0 and <= pool supply
- Calculates proportional share of reserves
- Validates outputs meet minimum requirements
- Decreases pool LP supply
- Withdraws tokens from reserves
- Emits `LiquidityRemoved` event

**Withdrawal Calculation:**
```
amount_a = (lp_tokens * reserve_a) / lp_supply
amount_b = (lp_tokens * reserve_b) / lp_supply
```

**Error Codes:**
- `E_INVALID_AMOUNT` (3): LP tokens must be > 0
- `E_INSUFFICIENT_LIQUIDITY` (1): LP tokens exceed pool supply
- `E_SLIPPAGE_TOO_HIGH` (2): Withdrawn amounts less than minimums

---

## View Functions

### get_reserves

```move
public fun get_reserves<TokenA, TokenB>(
    pool: &Pool<TokenA, TokenB>
): (u64, u64)
```

Returns the current token reserves in the pool.

**Input Parameters:**

| Name | Type | Description |
|------|------|-------------|
| pool | &Pool\<TokenA, TokenB\> | The liquidity pool |

**Return Values:**

| Position | Type | Description |
|----------|------|-------------|
| 0 | u64 | Reserve amount of TokenA |
| 1 | u64 | Reserve amount of TokenB |

**Usage:** External protocols use this for price calculations and oracle implementations.

---

### calculate_amount_out

```move
public fun calculate_amount_out<TokenA, TokenB>(
    pool: &Pool<TokenA, TokenB>,
    amount_in: u64,
    token_a_to_b: bool
): u64
```

Calculates the output amount for a given input without executing the swap. Useful for price quotes and simulations.

**Input Parameters:**

| Name | Type | Description |
|------|------|-------------|
| pool | &Pool\<TokenA, TokenB\> | The liquidity pool |
| amount_in | u64 | Input token amount |
| token_a_to_b | bool | true = A to B, false = B to A |

**Return Value:**

| Type | Description |
|------|-------------|
| u64 | Expected output amount |

**Usage:**
- Price quotes for UI
- Calculating slippage before trading
- MEV bot simulations
- Arbitrage opportunity detection

---

### get_fee_rate

```move
public fun get_fee_rate<TokenA, TokenB>(
    pool: &Pool<TokenA, TokenB>
): u64
```

Returns the trading fee rate in basis points.

**Return Value:**

| Type | Description |
|------|-------------|
| u64 | Fee rate in basis points (30 = 0.3%) |

---

### get_lp_supply

```move
public fun get_lp_supply<TokenA, TokenB>(
    pool: &Pool<TokenA, TokenB>
): u64
```

Returns the total LP token supply for the pool.

---

### get_pool_id

```move
public fun get_pool_id<TokenA, TokenB>(
    pool: &Pool<TokenA, TokenB>
): address
```

Returns the unique address identifier of the pool.

---

## Events

### PoolCreated

```move
public struct PoolCreated<phantom TokenA, phantom TokenB> has copy, drop {
    pool_id: address,
    initial_a: u64,
    initial_b: u64,
    creator: address,
}
```

Emitted when a new liquidity pool is created.

**Fields:**

| Name | Type | Description |
|------|------|-------------|
| pool_id | address | Address of the created pool |
| initial_a | u64 | Initial TokenA liquidity |
| initial_b | u64 | Initial TokenB liquidity |
| creator | address | Address of pool creator |

---

### SwapExecuted

```move
public struct SwapExecuted<phantom TokenA, phantom TokenB> has copy, drop {
    pool_id: address,
    sender: address,
    token_in: bool,
    amount_in: u64,
    amount_out: u64,
    fee_amount: u64,
    reserve_a: u64,
    reserve_b: u64,
    price_impact: u64,
}
```

Emitted when a swap is executed. Contains comprehensive trade data for analytics.

**Fields:**

| Name | Type | Description |
|------|------|-------------|
| pool_id | address | Address of the pool |
| sender | address | Address of the trader |
| token_in | bool | true = TokenA in, false = TokenB in |
| amount_in | u64 | Input token amount |
| amount_out | u64 | Output token amount |
| fee_amount | u64 | Fee paid to LPs |
| reserve_a | u64 | TokenA reserve after swap |
| reserve_b | u64 | TokenB reserve after swap |
| price_impact | u64 | Price impact in basis points |

**Price Impact Calculation:**
```
price_impact = (amount_out * 10000) / reserve_out
```

---

### LiquidityAdded

```move
public struct LiquidityAdded<phantom TokenA, phantom TokenB> has copy, drop {
    pool_id: address,
    provider: address,
    amount_a: u64,
    amount_b: u64,
    liquidity_minted: u64,
}
```

Emitted when liquidity is added to a pool.

**Fields:**

| Name | Type | Description |
|------|------|-------------|
| pool_id | address | Address of the pool |
| provider | address | Address of LP |
| amount_a | u64 | TokenA deposited |
| amount_b | u64 | TokenB deposited |
| liquidity_minted | u64 | LP tokens minted |

---

### LiquidityRemoved

```move
public struct LiquidityRemoved<phantom TokenA, phantom TokenB> has copy, drop {
    pool_id: address,
    provider: address,
    amount_a: u64,
    amount_b: u64,
    liquidity_burned: u64,
}
```

Emitted when liquidity is removed from a pool.

**Fields:**

| Name | Type | Description |
|------|------|-------------|
| pool_id | address | Address of the pool |
| provider | address | Address of LP |
| amount_a | u64 | TokenA withdrawn |
| amount_b | u64 | TokenB withdrawn |
| liquidity_burned | u64 | LP tokens burned |

---

## Core Data Structures

### Pool

```move
public struct Pool<phantom TokenA, phantom TokenB> has key {
    id: UID,
    reserve_a: Balance<TokenA>,
    reserve_b: Balance<TokenB>,
    lp_supply: u64,
    fee_rate: u64,
}
```

Represents a liquidity pool for a token pair.

**Fields:**

| Field | Type | Description |
|-------|------|-------------|
| id | UID | Unique identifier |
| reserve_a | Balance\<TokenA\> | TokenA reserve balance |
| reserve_b | Balance\<TokenB\> | TokenB reserve balance |
| lp_supply | u64 | Total LP tokens in circulation |
| fee_rate | u64 | Trading fee in basis points (30 = 0.3%) |

---

### LPToken

```move
public struct LPToken<phantom TokenA, phantom TokenB> has drop {}
```

Phantom type representing LP tokens. Currently used as a type marker.

**Note:** In a production implementation, this should be a proper object with balance tracking and transfer capabilities.

---

## AMM Mechanics

### Constant Product Formula

The DEX uses the constant product invariant:

```
reserve_a * reserve_b = k (constant)
```

When a swap occurs:
```
(reserve_a + amount_in) * (reserve_b - amount_out) = k
```

Solving for `amount_out`:
```
amount_out = (amount_in * reserve_b) / (reserve_a + amount_in)
```

### Fee Integration

The 0.3% fee is applied to the input amount:

```
amount_in_with_fee = amount_in * (10000 - 30) / 10000 = amount_in * 0.997
```

Final formula with fees:
```
amount_out = (amount_in_with_fee * reserve_b) / (reserve_a + amount_in_with_fee)
```

### Price Calculation

The spot price is the ratio of reserves:

```
price_a_in_b = reserve_b / reserve_a
price_b_in_a = reserve_a / reserve_b
```

### Price Impact

Large trades cause price impact (slippage):

```
price_impact = (amount_out / reserve_b) * 10000  // in basis points
```

Higher price impact = worse execution price for the trader.

---

## Liquidity Provider Economics

### Earning Fees

LPs earn a proportional share of all trading fees based on their pool ownership:

```
lp_share = lp_tokens / lp_supply
fee_earnings = total_fees * lp_share
```

Fees accumulate in the pool reserves, increasing the value of LP tokens over time.

### Impermanent Loss

LPs face impermanent loss when token prices diverge from the initial ratio. This occurs because the AMM automatically rebalances reserves.

**Example:**
- Initial: 100 TokenA @ $1, 100 TokenB @ $1 → $200 total
- After price change: TokenA = $2
- AMM rebalances to: ~70.7 TokenA, ~141.4 TokenB → $282.8 total
- Hold value: 100 TokenA @ $2 + 100 TokenB @ $1 → $300 total
- **Impermanent loss**: $300 - $282.8 = $17.2 (5.7%)

Impermanent loss is "impermanent" because it only becomes permanent if you withdraw at that price ratio.

### Fee APR Calculation

```
daily_volume = Σ(swap amounts)
daily_fees = daily_volume * 0.003
yearly_fees = daily_fees * 365
fee_apr = (yearly_fees / total_liquidity) * 100
```

---

## Security Considerations

### Price Manipulation

The DEX is vulnerable to price manipulation when used as an oracle:

**Attack Vector:**
1. Flash loan large amount of TokenA
2. Swap massive amount on the DEX (price spikes)
3. Use manipulated price in lending protocol to borrow
4. Swap back and repay flash loan

**Mitigation:** Use TWAP oracles instead of spot prices for critical operations.

### Front-Running & MEV

Traders are vulnerable to:

- **Front-running**: Bots see pending transactions and execute before them
- **Sandwich attacks**: Place trades before and after victim's trade
- **Just-In-Time (JIT) liquidity**: Add liquidity right before large trade, remove after

**Mitigation:**
- Set appropriate `min_out` slippage protection
- Use private mempools (e.g., Flashbots on Ethereum)
- Break large trades into smaller chunks

### Reentrancy

Move's execution model prevents classic reentrancy attacks that plague Solidity AMMs.

### Flash Loan Integration

The DEX can be combined with flash loans for:
- **Arbitrage**: Exploit price differences across DEXs
- **Price manipulation**: Attack vulnerable lending protocols
- **Liquidity provision**: JIT liquidity for specific trades

---

## Comparison to Uniswap V2

### Similarities

| Feature | Uniswap V2 | This Implementation |
|---------|------------|---------------------|
| Constant Product | ✅ x * y = k | ✅ x * y = k |
| Fee Rate | 0.3% | 0.3% |
| LP Tokens | ✅ | ✅ (conceptual) |
| Minimum Liquidity | 1000 burned | 1000 burned |
| Permissionless Pools | ✅ | ✅ |

### Key Differences

| Feature | Uniswap V2 | This Implementation |
|---------|------------|---------------------|
| Language | Solidity | Move |
| Blockchain | Ethereum | Sui |
| LP Token Transfer | ERC-20 | Not implemented |
| Price Oracle | TWAP built-in | Optional external TWAP |
| Flash Swaps | ✅ | ❌ |
| Protocol Fee | Optional | Not implemented |

### Move-Specific Features

1. **Type Safety**: Token types enforced at compile time
2. **No Reentrancy**: Move's execution model prevents reentrancy
3. **Explicit Ownership**: Pool ownership is explicit in the type system
4. **Generic Pools**: Single implementation works for all token pairs

---

## Use Cases

### Trading

Users can swap tokens without an order book or counterparty:

```move
let usdc_out = swap_a_to_b(
    &mut eth_usdc_pool,
    eth_coins,
    min_usdc_out,  // 1% slippage tolerance
    ctx
);
```

### Liquidity Provision

Earn trading fees by providing liquidity:

```move
add_liquidity(
    &mut pool,
    token_a_coins,
    token_b_coins,
    min_lp_tokens,
    ctx
);

// Later...
let (token_a_back, token_b_back) = remove_liquidity(
    &mut pool,
    lp_tokens,
    min_a,
    min_b,
    ctx
);
```

### Arbitrage

Exploit price differences across markets:

```move
// Buy on DEX 1 (cheaper)
let tokens = swap_a_to_b(&mut dex1_pool, usdc, 0, ctx);

// Sell on DEX 2 (higher price)
let usdc_profit = swap_b_to_a(&mut dex2_pool, tokens, 0, ctx);
```

### Price Oracle

Other protocols can use the DEX for price feeds:

```move
let (reserve_a, reserve_b) = get_reserves(&pool);
let price = (reserve_b * PRECISION) / reserve_a;
```

**⚠️ Warning:** Spot prices are manipulable. Use TWAP for production.

---

## Integration Examples

### Basic Swap Integration

```move
public fun perform_swap<TokenA, TokenB>(
    pool: &mut Pool<TokenA, TokenB>,
    input: Coin<TokenA>,
    max_slippage_bps: u64,
    ctx: &mut TxContext
): Coin<TokenB> {
    let amount_in = coin::value(&input);

    // Calculate expected output
    let expected_out = calculate_amount_out(pool, amount_in, true);

    // Apply slippage tolerance
    let min_out = (expected_out * (10000 - max_slippage_bps)) / 10000;

    // Execute swap
    swap_a_to_b(pool, input, min_out, ctx)
}
```

### Multi-Hop Swap

```move
public fun swap_a_to_c_via_b<A, B, C>(
    pool_ab: &mut Pool<A, B>,
    pool_bc: &mut Pool<B, C>,
    input: Coin<A>,
    min_out: u64,
    ctx: &mut TxContext
): Coin<C> {
    // Swap A to B
    let b_tokens = swap_a_to_b(pool_ab, input, 0, ctx);

    // Swap B to C
    let c_tokens = swap_a_to_b(pool_bc, b_tokens, min_out, ctx);

    c_tokens
}
```

### Providing Liquidity with Optimal Ratio

```move
public fun add_liquidity_optimal<TokenA, TokenB>(
    pool: &mut Pool<TokenA, TokenB>,
    mut token_a: Coin<TokenA>,
    mut token_b: Coin<TokenB>,
    ctx: &mut TxContext
): (Coin<TokenA>, Coin<TokenB>) {
    let (reserve_a, reserve_b) = get_reserves(pool);

    let amount_a = coin::value(&token_a);
    let amount_b = coin::value(&token_b);

    // Calculate optimal ratio
    let optimal_b = (amount_a * reserve_b) / reserve_a;

    if (optimal_b <= amount_b) {
        // Use all TokenA, return excess TokenB
        let b_to_use = coin::split(&mut token_b, optimal_b, ctx);
        add_liquidity(pool, token_a, b_to_use, 0, ctx);
        (coin::zero(ctx), token_b)
    } else {
        // Use all TokenB, return excess TokenA
        let optimal_a = (amount_b * reserve_a) / reserve_b;
        let a_to_use = coin::split(&mut token_a, optimal_a, ctx);
        add_liquidity(pool, a_to_use, token_b, 0, ctx);
        (token_a, coin::zero(ctx))
    }
}
```

---

## Error Codes

| Code | Constant | Description |
|------|----------|-------------|
| 1 | E_INSUFFICIENT_LIQUIDITY | Pool lacks sufficient reserves |
| 2 | E_SLIPPAGE_TOO_HIGH | Output below minimum acceptable amount |
| 3 | E_INVALID_AMOUNT | Amount is zero or invalid |
| 4 | E_ZERO_LIQUIDITY | Initial liquidity too small |

---

## Constants

| Constant | Value | Description |
|----------|-------|-------------|
| Default Fee Rate | 30 | 0.3% trading fee in basis points |
| Minimum Liquidity | 1000 | LP tokens burned on first deposit |

---

## Best Practices

### For Traders

1. **Always set slippage protection**: Use `min_out` parameter
2. **Check price impact**: Use `calculate_amount_out` before trading
3. **Avoid large single trades**: Break into smaller chunks
4. **Monitor MEV**: Large trades attract sandwich attacks

### For Liquidity Providers

1. **Understand impermanent loss**: Study the risk before providing
2. **Provide balanced liquidity**: Match pool ratio to minimize remainder
3. **Monitor fee earnings**: Track accumulated fees in LP token value
4. **Consider price volatility**: High volatility = higher impermanent loss

### For Integrators

1. **Never use spot price as oracle**: Implement TWAP for security
2. **Handle rounding**: Account for precision loss in calculations
3. **Validate pool existence**: Check pool is initialized before use
4. **Test price impact**: Simulate trades to ensure acceptable slippage

---

## References

- [Uniswap V2 Whitepaper](https://uniswap.org/whitepaper.pdf)
- [Uniswap V2 Docs](https://docs.uniswap.org/protocol/V2/introduction)
- [Constant Product AMM Explanation](https://medium.com/bollinger-investment-group/constant-function-market-makers-defis-zero-to-one-innovation-968f77022159)
- [Impermanent Loss Explained](https://finematics.com/impermanent-loss-explained/)
- [Move Language Book](https://move-language.github.io/move/)
