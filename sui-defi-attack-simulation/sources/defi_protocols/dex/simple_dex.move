// sources/defi_protocols/dex/simple_dex.move
module simulation::simple_dex {
    use sui::object::{Self, UID};
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::math;
    use sui::event;

    /// Pool errors
    const E_INSUFFICIENT_LIQUIDITY: u64 = 1;
    const E_SLIPPAGE_TOO_HIGH: u64 = 2;
    const E_INVALID_AMOUNT: u64 = 3;
    const E_ZERO_LIQUIDITY: u64 = 4;

    /// LP Token for liquidity providers
    public struct LPToken<phantom TokenA, phantom TokenB> has drop {}

    /// Liquidity pool
    public struct Pool<phantom TokenA, phantom TokenB> has key {
        id: UID,
        token_a_balance: Balance<TokenA>,
        token_b_balance: Balance<TokenB>,
        lp_token_supply: u64,
        fee_rate: u64, // Basis points (30 = 0.3%)
    }

    /// Pool creation receipt
    public struct PoolCreated<phantom TokenA, phantom TokenB> has copy, drop {
        pool_id: address,
        initial_a: u64,
        initial_b: u64,
        creator: address,
    }

    /// Swap event
    public struct SwapExecuted<phantom TokenA, phantom TokenB> has copy, drop {
        pool_id: address,
        user: address,
        token_in: bool, // true = TokenA in, false = TokenB in
        amount_in: u64,
        amount_out: u64,
        fee_amount: u64,
        new_reserve_a: u64,
        new_reserve_b: u64,
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

    /// Create new liquidity pool
    public fun create_pool<TokenA, TokenB>(
        token_a: Coin<TokenA>,
        token_b: Coin<TokenB>,
        ctx: &mut TxContext
    ) {
        let amount_a = coin::value(&token_a);
        let amount_b = coin::value(&token_b);

        assert!(amount_a > 0 && amount_b > 0, E_INVALID_AMOUNT);

        // Initial LP tokens = sqrt(a * b) - minimum liquidity
        let initial_liquidity = math::sqrt(amount_a * amount_b);
        let minimum_liquidity = 1000; // Burn minimum liquidity

        assert!(initial_liquidity > minimum_liquidity, E_ZERO_LIQUIDITY);

        let pool = Pool<TokenA, TokenB> {
            id: object::new(ctx),
            token_a_balance: coin::into_balance(token_a),
            token_b_balance: coin::into_balance(token_b),
            lp_token_supply: initial_liquidity,
            fee_rate: 30, // 0.3%
        };

        let pool_address = object::uid_to_address(&pool.id);

        event::emit(PoolCreated<TokenA, TokenB> {
            pool_id: pool_address,
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
        ctx: &mut TxContext
    ): Coin<TokenB> {
        let amount_in = coin::value(&token_a);
        assert!(amount_in > 0, E_INVALID_AMOUNT);

        let reserve_a = balance::value(&pool.token_a_balance);
        let reserve_b = balance::value(&pool.token_b_balance);

        // Calculate amount out using constant product formula
        // amount_out = (amount_in * (10000-fee) * reserve_b) / (reserve_a * 10000 + amount_in * (10000-fee))
        let amount_in_with_fee = amount_in * (10000 - pool.fee_rate);
        let numerator = amount_in_with_fee * reserve_b;
        let denominator = reserve_a * 10000 + amount_in_with_fee;
        let amount_out = numerator / denominator;

        assert!(amount_out >= min_out, E_SLIPPAGE_TOO_HIGH);
        assert!(amount_out < reserve_b, E_INSUFFICIENT_LIQUIDITY);

        // Calculate price impact
        let price_impact = (amount_out * 10000) / reserve_b;

        // Execute swap
        balance::join(&mut pool.token_a_balance, coin::into_balance(token_a));
        let token_b_out = coin::from_balance(
            balance::split(&mut pool.token_b_balance, amount_out),
            ctx
        );

        // Emit swap event
        event::emit(SwapExecuted<TokenA, TokenB> {
            pool_id: object::uid_to_address(&pool.id),
            user: tx_context::sender(ctx),
            token_in: true,
            amount_in,
            amount_out,
            fee_amount: (amount_in * pool.fee_rate) / 10000,
            new_reserve_a: balance::value(&pool.token_a_balance),
            new_reserve_b: balance::value(&pool.token_b_balance),
            price_impact,
        });

        token_b_out
    }

    /// Swap TokenB for TokenA
    public fun swap_b_to_a<TokenA, TokenB>(
        pool: &mut Pool<TokenA, TokenB>,
        token_b: Coin<TokenB>,
        min_out: u64,
        ctx: &mut TxContext
    ): Coin<TokenA> {
        let amount_in = coin::value(&token_b);
        assert!(amount_in > 0, E_INVALID_AMOUNT);

        let reserve_a = balance::value(&pool.token_a_balance);
        let reserve_b = balance::value(&pool.token_b_balance);

        let amount_in_with_fee = amount_in * (10000 - pool.fee_rate);
        let numerator = amount_in_with_fee * reserve_a;
        let denominator = reserve_b * 10000 + amount_in_with_fee;
        let amount_out = numerator / denominator;

        assert!(amount_out >= min_out, E_SLIPPAGE_TOO_HIGH);
        assert!(amount_out < reserve_a, E_INSUFFICIENT_LIQUIDITY);

        let price_impact = (amount_out * 10000) / reserve_a;

        balance::join(&mut pool.token_b_balance, coin::into_balance(token_b));
        let token_a_out = coin::from_balance(
            balance::split(&mut pool.token_a_balance, amount_out),
            ctx
        );

        event::emit(SwapExecuted<TokenA, TokenB> {
            pool_id: object::uid_to_address(&pool.id),
            user: tx_context::sender(ctx),
            token_in: false,
            amount_in,
            amount_out,
            fee_amount: (amount_in * pool.fee_rate) / 10000,
            new_reserve_a: balance::value(&pool.token_a_balance),
            new_reserve_b: balance::value(&pool.token_b_balance),
            price_impact,
        });

        token_a_out
    }

    /// Add liquidity
    public fun add_liquidity<TokenA, TokenB>(
        pool: &mut Pool<TokenA, TokenB>,
        token_a: Coin<TokenA>,
        token_b: Coin<TokenB>,
        min_liquidity: u64,
        ctx: &mut TxContext
    ) {
        let amount_a = coin::value(&token_a);
        let amount_b = coin::value(&token_b);

        let reserve_a = balance::value(&pool.token_a_balance);
        let reserve_b = balance::value(&pool.token_b_balance);

        // Calculate optimal amounts
        let liquidity = if (pool.lp_token_supply == 0) {
            math::sqrt(amount_a * amount_b)
        } else {
            let liquidity_a = (amount_a * pool.lp_token_supply) / reserve_a;
            let liquidity_b = (amount_b * pool.lp_token_supply) / reserve_b;
            if (liquidity_a < liquidity_b) { liquidity_a } else { liquidity_b }
        };

        assert!(liquidity >= min_liquidity, E_INSUFFICIENT_LIQUIDITY);

        balance::join(&mut pool.token_a_balance, coin::into_balance(token_a));
        balance::join(&mut pool.token_b_balance, coin::into_balance(token_b));
        pool.lp_token_supply = pool.lp_token_supply + liquidity;

        event::emit(LiquidityAdded<TokenA, TokenB> {
            pool_id: object::uid_to_address(&pool.id),
            provider: tx_context::sender(ctx),
            amount_a,
            amount_b,
            liquidity_minted: liquidity,
        });
    }

    /// Get pool reserves (for external price calculation)
    public fun get_reserves<TokenA, TokenB>(
        pool: &Pool<TokenA, TokenB>
    ): (u64, u64) {
        (
            balance::value(&pool.token_a_balance),
            balance::value(&pool.token_b_balance)
        )
    }

    /// Calculate swap amount out (for simulation/analysis)
    public fun calculate_amount_out<TokenA, TokenB>(
        pool: &Pool<TokenA, TokenB>,
        amount_in: u64,
        token_a_to_b: bool
    ): u64 {
        let reserve_a = balance::value(&pool.token_a_balance);
        let reserve_b = balance::value(&pool.token_b_balance);

        let amount_in_with_fee = amount_in * (10000 - pool.fee_rate);

        if (token_a_to_b) {
            let numerator = amount_in_with_fee * reserve_b;
            let denominator = reserve_a * 10000 + amount_in_with_fee;
            numerator / denominator
        } else {
            let numerator = amount_in_with_fee * reserve_a;
            let denominator = reserve_b * 10000 + amount_in_with_fee;
            numerator / denominator
        }
    }

    /// Get pool fee rate
    public fun get_fee_rate<TokenA, TokenB>(pool: &Pool<TokenA, TokenB>): u64 {
        pool.fee_rate
    }

    /// Get LP token supply
    public fun get_lp_supply<TokenA, TokenB>(pool: &Pool<TokenA, TokenB>): u64 {
        pool.lp_token_supply
    }
}
