// sources/defi_protocols/dex/simple_dex.move
module simulation::simple_dex;

use simulation::math_utils;
use simulation::twap_oracle::{Self, TWAPOracle};
use sui::balance::{Self, Balance};
use sui::clock::Clock;
use sui::coin::{Self, Coin};
use sui::event;

// ============================================================================
// Constants & Errors
// ============================================================================

const E_INSUFFICIENT_LIQUIDITY: u64 = 1;
const E_SLIPPAGE_TOO_HIGH: u64 = 2;
const E_INVALID_AMOUNT: u64 = 3;
const E_ZERO_LIQUIDITY: u64 = 4;

// ============================================================================
// Structs
// ============================================================================

/// LP Token for liquidity providers
public struct LPToken<phantom TokenA, phantom TokenB> has drop {}

/// Liquidity pool
public struct Pool<phantom TokenA, phantom TokenB> has key {
    id: UID,
    reserve_a: Balance<TokenA>,
    reserve_b: Balance<TokenB>,
    lp_supply: u64,
    fee_rate: u64, // Basis points (30 = 0.3%)
}

/// Pool creation event
public struct PoolCreated<phantom TokenA, phantom TokenB> has copy, drop {
    pool_id: address,
    initial_a: u64,
    initial_b: u64,
    creator: address,
}

/// Swap execution event
public struct SwapExecuted<phantom TokenA, phantom TokenB> has copy, drop {
    pool_id: address,
    sender: address,
    token_in: bool, // true = TokenA in, false = TokenB in
    amount_in: u64,
    amount_out: u64,
    fee_amount: u64,
    reserve_a: u64,
    reserve_b: u64,
    price_impact: u64, // Basis points
}

/// Liquidity added event
public struct LiquidityAdded<phantom TokenA, phantom TokenB> has copy, drop {
    pool_id: address,
    provider: address,
    amount_a: u64,
    amount_b: u64,
    liquidity_minted: u64,
}

/// Liquidity removed event
public struct LiquidityRemoved<phantom TokenA, phantom TokenB> has copy, drop {
    pool_id: address,
    provider: address,
    amount_a: u64,
    amount_b: u64,
    liquidity_burned: u64,
}

// ============================================================================
// Public Functions
// ============================================================================

/// Create new liquidity pool
public fun create_pool<TokenA, TokenB>(
    token_a: Coin<TokenA>,
    token_b: Coin<TokenB>,
    ctx: &mut TxContext,
) {
    let amount_a = coin::value(&token_a);
    let amount_b = coin::value(&token_b);

    assert!(amount_a > 0 && amount_b > 0, E_INVALID_AMOUNT);

    // Initial LP tokens = sqrt(a * b) - minimum liquidity
    let initial_liquidity = math_utils::sqrt((amount_a as u128) * (amount_b as u128));
    let minimum_liquidity = 1000; // Burn minimum liquidity

    assert!(initial_liquidity > minimum_liquidity, E_ZERO_LIQUIDITY);

    let pool = Pool<TokenA, TokenB> {
        id: object::new(ctx),
        reserve_a: coin::into_balance(token_a),
        reserve_b: coin::into_balance(token_b),
        lp_supply: initial_liquidity - minimum_liquidity,
        fee_rate: 30, // 0.3%
    };

    let pool_id = object::uid_to_address(&pool.id);

    event::emit(PoolCreated<TokenA, TokenB> {
        pool_id,
        initial_a: amount_a,
        initial_b: amount_b,
        creator: tx_context::sender(ctx),
    });

    transfer::share_object(pool);
}

/// Swap TokenA for TokenB
public fun swap_a_to_b<TokenA, TokenB>(
    pool: &mut Pool<TokenA, TokenB>,
    token_a: Coin<TokenA>,
    min_out: u64,
    ctx: &mut TxContext,
): Coin<TokenB> {
    let amount_in = coin::value(&token_a);
    assert!(amount_in > 0, E_INVALID_AMOUNT);

    let reserve_a_val = balance::value(&pool.reserve_a);
    let reserve_b_val = balance::value(&pool.reserve_b);

    // Calculate amount out using constant product formula (use u128 to avoid overflow)
    // amount_out = (amount_in * (10000-fee) * reserve_b) / (reserve_a * 10000 + amount_in * (10000-fee))
    let amount_in_with_fee = (amount_in as u128) * ((10000 - pool.fee_rate) as u128);
    let numerator = amount_in_with_fee * (reserve_b_val as u128);
    let denominator = (reserve_a_val as u128) * 10000 + amount_in_with_fee;
    let amount_out = (numerator / denominator) as u64;

    assert!(amount_out >= min_out, E_SLIPPAGE_TOO_HIGH);
    assert!(amount_out < reserve_b_val, E_INSUFFICIENT_LIQUIDITY);

    // Calculate price impact
    let price_impact = (amount_out * 10000) / reserve_b_val;

    // Execute swap
    balance::join(&mut pool.reserve_a, coin::into_balance(token_a));
    let token_b_out = coin::from_balance(
        balance::split(&mut pool.reserve_b, amount_out),
        ctx,
    );

    // Emit swap event
    event::emit(SwapExecuted<TokenA, TokenB> {
        pool_id: object::uid_to_address(&pool.id),
        sender: tx_context::sender(ctx),
        token_in: true,
        amount_in,
        amount_out,
        fee_amount: (amount_in * pool.fee_rate) / 10000,
        reserve_a: balance::value(&pool.reserve_a),
        reserve_b: balance::value(&pool.reserve_b),
        price_impact,
    });

    token_b_out
}

/// Swap TokenB for TokenA
public fun swap_b_to_a<TokenA, TokenB>(
    pool: &mut Pool<TokenA, TokenB>,
    token_b: Coin<TokenB>,
    min_out: u64,
    ctx: &mut TxContext,
): Coin<TokenA> {
    let amount_in = coin::value(&token_b);
    assert!(amount_in > 0, E_INVALID_AMOUNT);

    let reserve_a_val = balance::value(&pool.reserve_a);
    let reserve_b_val = balance::value(&pool.reserve_b);

    // Use u128 to avoid overflow
    let amount_in_with_fee = (amount_in as u128) * ((10000 - pool.fee_rate) as u128);
    let numerator = amount_in_with_fee * (reserve_a_val as u128);
    let denominator = (reserve_b_val as u128) * 10000 + amount_in_with_fee;
    let amount_out = (numerator / denominator) as u64;

    assert!(amount_out >= min_out, E_SLIPPAGE_TOO_HIGH);
    assert!(amount_out < reserve_a_val, E_INSUFFICIENT_LIQUIDITY);

    let price_impact = (amount_out * 10000) / reserve_a_val;

    balance::join(&mut pool.reserve_b, coin::into_balance(token_b));
    let token_a_out = coin::from_balance(
        balance::split(&mut pool.reserve_a, amount_out),
        ctx,
    );

    event::emit(SwapExecuted<TokenA, TokenB> {
        pool_id: object::uid_to_address(&pool.id),
        sender: tx_context::sender(ctx),
        token_in: false,
        amount_in,
        amount_out,
        fee_amount: (amount_in * pool.fee_rate) / 10000,
        reserve_a: balance::value(&pool.reserve_a),
        reserve_b: balance::value(&pool.reserve_b),
        price_impact,
    });

    token_a_out
}

/// Swap TokenA for TokenB with TWAP oracle update
public fun swap_a_to_b_with_twap<TokenA, TokenB>(
    pool: &mut Pool<TokenA, TokenB>,
    oracle: &mut TWAPOracle<TokenA, TokenB>,
    token_a: Coin<TokenA>,
    min_out: u64,
    clock: &Clock,
    ctx: &mut TxContext,
): Coin<TokenB> {
    // Execute swap
    let token_b_out = swap_a_to_b(pool, token_a, min_out, ctx);

    // Update TWAP oracle after swap
    let (reserve_a, reserve_b) = get_reserves(pool);
    twap_oracle::update_observation(oracle, reserve_a, reserve_b, clock);

    token_b_out
}

/// Swap TokenB for TokenA with TWAP oracle update
public fun swap_b_to_a_with_twap<TokenA, TokenB>(
    pool: &mut Pool<TokenA, TokenB>,
    oracle: &mut TWAPOracle<TokenA, TokenB>,
    token_b: Coin<TokenB>,
    min_out: u64,
    clock: &Clock,
    ctx: &mut TxContext,
): Coin<TokenA> {
    // Execute swap
    let token_a_out = swap_b_to_a(pool, token_b, min_out, ctx);

    // Update TWAP oracle after swap
    let (reserve_a, reserve_b) = get_reserves(pool);
    twap_oracle::update_observation(oracle, reserve_a, reserve_b, clock);

    token_a_out
}

/// Add liquidity
entry fun add_liquidity<TokenA, TokenB>(
    pool: &mut Pool<TokenA, TokenB>,
    token_a: Coin<TokenA>,
    token_b: Coin<TokenB>,
    min_liquidity: u64,
    ctx: &TxContext,
) {
    let amount_a = coin::value(&token_a);
    let amount_b = coin::value(&token_b);

    let reserve_a_val = balance::value(&pool.reserve_a);
    let reserve_b_val = balance::value(&pool.reserve_b);

    // Calculate optimal amounts
    let liquidity = if (pool.lp_supply == 0) {
        math_utils::sqrt((amount_a as u128) * (amount_b as u128))
    } else {
        let liquidity_a = (amount_a * pool.lp_supply) / reserve_a_val;
        let liquidity_b = (amount_b * pool.lp_supply) / reserve_b_val;
        if (liquidity_a < liquidity_b) { liquidity_a } else { liquidity_b }
    };

    assert!(liquidity >= min_liquidity, E_INSUFFICIENT_LIQUIDITY);

    balance::join(&mut pool.reserve_a, coin::into_balance(token_a));
    balance::join(&mut pool.reserve_b, coin::into_balance(token_b));
    pool.lp_supply = pool.lp_supply + liquidity;

    event::emit(LiquidityAdded<TokenA, TokenB> {
        pool_id: object::uid_to_address(&pool.id),
        provider: tx_context::sender(ctx),
        amount_a,
        amount_b,
        liquidity_minted: liquidity,
    });
}

// ============================================================================
// Getters
// ============================================================================

/// Get pool reserves (for external price calculation)
public fun get_reserves<TokenA, TokenB>(pool: &Pool<TokenA, TokenB>): (u64, u64) {
    (balance::value(&pool.reserve_a), balance::value(&pool.reserve_b))
}

/// Calculate swap amount out (for simulation/analysis)
public fun calculate_amount_out<TokenA, TokenB>(
    pool: &Pool<TokenA, TokenB>,
    amount_in: u64,
    token_a_to_b: bool,
): u64 {
    let reserve_a_val = balance::value(&pool.reserve_a);
    let reserve_b_val = balance::value(&pool.reserve_b);

    // Use u128 to avoid overflow
    let amount_in_with_fee = (amount_in as u128) * ((10000 - pool.fee_rate) as u128);

    if (token_a_to_b) {
        let numerator = amount_in_with_fee * (reserve_b_val as u128);
        let denominator = (reserve_a_val as u128) * 10000 + amount_in_with_fee;
        (numerator / denominator) as u64
    } else {
        let numerator = amount_in_with_fee * (reserve_a_val as u128);
        let denominator = (reserve_b_val as u128) * 10000 + amount_in_with_fee;
        (numerator / denominator) as u64
    }
}

/// Get pool fee rate
public fun get_fee_rate<TokenA, TokenB>(pool: &Pool<TokenA, TokenB>): u64 {
    pool.fee_rate
}

/// Remove liquidity from pool
public fun remove_liquidity<TokenA, TokenB>(
    pool: &mut Pool<TokenA, TokenB>,
    lp_tokens: u64,  // Amount of LP tokens to burn
    min_a: u64,      // Minimum TokenA to receive
    min_b: u64,      // Minimum TokenB to receive
    ctx: &mut TxContext,
): (Coin<TokenA>, Coin<TokenB>) {
    assert!(lp_tokens > 0, E_INVALID_AMOUNT);
    assert!(lp_tokens <= pool.lp_supply, E_INSUFFICIENT_LIQUIDITY);
    
    let reserve_a = balance::value(&pool.reserve_a);
    let reserve_b = balance::value(&pool.reserve_b);
    
    // Calculate proportional share
    let amount_a = (lp_tokens as u128) * (reserve_a as u128) / (pool.lp_supply as u128);
    let amount_b = (lp_tokens as u128) * (reserve_b as u128) / (pool.lp_supply as u128);
    let amount_a = (amount_a as u64);
    let amount_b = (amount_b as u64);
    
    // Slippage protection
    assert!(amount_a >= min_a, E_SLIPPAGE_TOO_HIGH);
    assert!(amount_b >= min_b, E_SLIPPAGE_TOO_HIGH);
    
    // Update pool state
    pool.lp_supply = pool.lp_supply - lp_tokens;
    
    // Withdraw tokens
    let token_a_out = coin::from_balance(
        balance::split(&mut pool.reserve_a, amount_a),
        ctx,
    );
    let token_b_out = coin::from_balance(
        balance::split(&mut pool.reserve_b, amount_b),
        ctx,
    );
    
    event::emit(LiquidityRemoved<TokenA, TokenB> {
        pool_id: object::uid_to_address(&pool.id),
        provider: tx_context::sender(ctx),
        amount_a,
        amount_b,
        liquidity_burned: lp_tokens,
    });
    
    (token_a_out, token_b_out)
}

/// Get LP token supply
public fun get_lp_supply<TokenA, TokenB>(pool: &Pool<TokenA, TokenB>): u64 {
    pool.lp_supply
}

/// Get pool ID (address)
public fun get_pool_id<TokenA, TokenB>(pool: &Pool<TokenA, TokenB>): address {
    object::uid_to_address(&pool.id)
}
