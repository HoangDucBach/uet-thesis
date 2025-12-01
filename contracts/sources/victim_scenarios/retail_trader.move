// sources/victim_scenarios/retail_trader.move
module simulation::retail_trader {
    use simulation::simple_dex::{Self, Pool};
    use sui::coin::{Self, Coin};
    use sui::event;

    // ============================================================================
    // Structs
    // ============================================================================

    /// Retail trade executed event
    public struct RetailTradeExecuted has copy, drop {
        sender: address,
        amount_in: u64,
        amount_out: u64,
        expected_out: u64,
        slippage_suffered: u64, // Basis points
        pool_id: address,
    }

    // ============================================================================
    // Public Functions
    // ============================================================================

    /// Execute normal retail trade (can be victim of sandwich)
    public fun execute_normal_trade<TokenA, TokenB>(
        pool: &mut Pool<TokenA, TokenB>,
        amount: u64,
        max_slippage_bp: u64, // Basis points (500 = 5%)
        mut coins: Coin<TokenA>,
        ctx: &mut TxContext
    ): (Coin<TokenB>, Coin<TokenA>) {
        // Calculate expected output
        let expected_out = simple_dex::calculate_amount_out(pool, amount, true);
        let min_out = expected_out * (10000 - max_slippage_bp) / 10000;

        // Split trade amount
        let trade_coin = coin::split(&mut coins, amount, ctx);

        // Execute trade
        let tokens_out = simple_dex::swap_a_to_b(pool, trade_coin, min_out, ctx);
        let actual_out = coin::value(&tokens_out);

        // Calculate suffered slippage
        let slippage = if (actual_out < expected_out) {
            ((expected_out - actual_out) * 10000) / expected_out
        } else {
            0
        };

        event::emit(RetailTradeExecuted {
            sender: tx_context::sender(ctx),
            amount_in: amount,
            amount_out: actual_out,
            expected_out,
            slippage_suffered: slippage,
            pool_id: simple_dex::get_pool_id(pool),
        });

        (tokens_out, coins)
    }

    /// Execute simple trade without slippage protection (more vulnerable)
    public fun execute_simple_trade<TokenA, TokenB>(
        pool: &mut Pool<TokenA, TokenB>,
        amount: u64,
        mut coins: Coin<TokenA>,
        ctx: &mut TxContext
    ): (Coin<TokenB>, Coin<TokenA>) {
        let expected_out = simple_dex::calculate_amount_out(pool, amount, true);
        let trade_coin = coin::split(&mut coins, amount, ctx);
        let tokens_out = simple_dex::swap_a_to_b(pool, trade_coin, 0, ctx);
        let actual_out = coin::value(&tokens_out);

        let slippage = if (actual_out < expected_out) {
            ((expected_out - actual_out) * 10000) / expected_out
        } else {
            0
        };

        event::emit(RetailTradeExecuted {
            sender: tx_context::sender(ctx),
            amount_in: amount,
            amount_out: actual_out,
            expected_out,
            slippage_suffered: slippage,
            pool_id: simple_dex::get_pool_id(pool),
        });

        (tokens_out, coins)
    }

    /// Add liquidity as a retail LP
    public fun add_liquidity<TokenA, TokenB>(
        pool: &mut Pool<TokenA, TokenB>,
        token_a: Coin<TokenA>,
        token_b: Coin<TokenB>,
        min_liquidity: u64,
        ctx: &mut TxContext
    ) {
        simple_dex::add_liquidity(pool, token_a, token_b, min_liquidity, ctx);
    }

    /// Swap and transfer tokens to recipient
    public fun swap_and_transfer<TokenA, TokenB>(
        pool: &mut Pool<TokenA, TokenB>,
        amount: u64,
        mut coins: Coin<TokenA>,
        recipient: address,
        ctx: &mut TxContext
    ): Coin<TokenA> {
        let expected_out = simple_dex::calculate_amount_out(pool, amount, true);
        let trade_coin = coin::split(&mut coins, amount, ctx);
        let tokens_out = simple_dex::swap_a_to_b(pool, trade_coin, 0, ctx);
        let actual_out = coin::value(&tokens_out);

        let slippage = if (actual_out < expected_out) {
            ((expected_out - actual_out) * 10000) / expected_out
        } else {
            0
        };

        event::emit(RetailTradeExecuted {
            sender: tx_context::sender(ctx),
            amount_in: amount,
            amount_out: actual_out,
            expected_out,
            slippage_suffered: slippage,
            pool_id: simple_dex::get_pool_id(pool),
        });

        // Transfer tokens to recipient
        transfer::public_transfer(tokens_out, recipient);

        coins
    }
}
