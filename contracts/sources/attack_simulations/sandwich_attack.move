// sources/attack_simulations/sandwich_attack.move
module simulation::sandwich_attack {
    use simulation::simple_dex::{Self, Pool};
    use simulation::coin_factory::{USDC, USDT};
    use sui::coin::{Self, Coin};
    use sui::event;

    // ============================================================================
    // Structs
    // ============================================================================

    /// Sandwich attack executed event
    public struct SandwichAttackExecuted has copy, drop {
        attacker: address,
        victim: address,
        front_run_amount: u64,
        victim_amount: u64,
        victim_slippage: u64, // How much victim lost due to sandwich
        attacker_profit: u64,
        pool_id: address,
    }

    // ============================================================================
    // Public Functions
    // ============================================================================

    /// Execute sandwich attack around victim transaction
    /// This is a simplified demonstration where both attacker and victim actions
    /// happen in the same transaction for simulation purposes
    public fun execute_sandwich_attack(
        pool: &mut Pool<USDC, USDT>,
        front_run_amount: u64,
        victim_amount: u64,
        mut attacker_coins: Coin<USDC>,
        victim_coins: Coin<USDC>,
        victim_address: address,
        ctx: &mut TxContext
    ): Coin<USDC> {
        let attacker = tx_context::sender(ctx);

        // Step 1: Front-run - Buy before victim to increase price
        let front_run_coin = coin::split(&mut attacker_coins, front_run_amount, ctx);
        let usdt_received = simple_dex::swap_a_to_b(
            pool,
            front_run_coin,
            0,
            ctx
        );

        // Step 2: Victim transaction (simulated)
        // Calculate what victim would have received without front-running
        let expected_victim_out = simple_dex::calculate_amount_out(
            pool,
            victim_amount,
            true
        );

        // Execute victim's swap (price is now worse due to front-running)
        let victim_usdt = simple_dex::swap_a_to_b(
            pool,
            victim_coins,
            0, // Victim gets less due to front-running
            ctx
        );

        let actual_victim_out = coin::value(&victim_usdt);

        // Calculate victim's slippage
        let victim_slippage = if (expected_victim_out > actual_victim_out) {
            expected_victim_out - actual_victim_out
        } else {
            0
        };

        // Step 3: Back-run - Sell after victim to profit from price increase
        let usdc_back = simple_dex::swap_b_to_a(
            pool,
            usdt_received,
            0,
            ctx
        );

        // Calculate attacker profit
        let usdc_back_value = coin::value(&usdc_back);
        let profit = if (usdc_back_value > front_run_amount) {
            usdc_back_value - front_run_amount
        } else {
            0
        };

        // Merge coins back to attacker
        coin::join(&mut attacker_coins, usdc_back);

        // Transfer victim's tokens to victim
        transfer::public_transfer(victim_usdt, victim_address);

        // Emit sandwich attack event
        event::emit(SandwichAttackExecuted {
            attacker,
            victim: victim_address,
            front_run_amount,
            victim_amount,
            victim_slippage,
            attacker_profit: profit,
            pool_id: simple_dex::get_pool_id(pool),
        });

        attacker_coins
    }

    /// Front-run phase only (to be used with separate victim transaction)
    public fun front_run<TokenA, TokenB>(
        pool: &mut Pool<TokenA, TokenB>,
        amount: u64,
        mut attacker_coins: Coin<TokenA>,
        ctx: &mut TxContext
    ): (Coin<TokenB>, Coin<TokenA>) {
        let front_run_coin = coin::split(&mut attacker_coins, amount, ctx);
        let tokens_received = simple_dex::swap_a_to_b(
            pool,
            front_run_coin,
            0,
            ctx
        );

        (tokens_received, attacker_coins)
    }

    /// Back-run phase only (to be used after victim transaction)
    public fun back_run<TokenA, TokenB>(
        pool: &mut Pool<TokenA, TokenB>,
        tokens: Coin<TokenB>,
        ctx: &mut TxContext
    ): Coin<TokenA> {
        simple_dex::swap_b_to_a(
            pool,
            tokens,
            0,
            ctx
        )
    }
}
