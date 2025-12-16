// sources/infrastructure/coin_factory.move
module simulation::coin_factory {
    use sui::coin::{Self, Coin, TreasuryCap};
    use simulation::usdc::USDC;
    use simulation::usdt::USDT;
    use simulation::weth::WETH;
    use simulation::btc::BTC;
    use simulation::sui_coin::SUI_COIN;

    // ============================================================================
    // Structs
    // ============================================================================

    /// Coin factory capability - holds all treasury caps
    public struct CoinFactory has key {
        id: UID,
        usdc_treasury: TreasuryCap<USDC>,
        usdt_treasury: TreasuryCap<USDT>,
        weth_treasury: TreasuryCap<WETH>,
        btc_treasury: TreasuryCap<BTC>,
        sui_treasury: TreasuryCap<SUI_COIN>,
    }

    // ============================================================================
    // Initialization
    // ============================================================================

    /// Create coin factory with treasury caps
    public fun create_factory(
        usdc_treasury: TreasuryCap<USDC>,
        usdt_treasury: TreasuryCap<USDT>,
        weth_treasury: TreasuryCap<WETH>,
        btc_treasury: TreasuryCap<BTC>,
        sui_treasury: TreasuryCap<SUI_COIN>,
        ctx: &mut TxContext
    ) {
        let factory = CoinFactory {
            id: object::new(ctx),
            usdc_treasury,
            usdt_treasury,
            weth_treasury,
            btc_treasury,
            sui_treasury,
        };

        transfer::share_object(factory);
    }

    // ============================================================================
    // Public Functions
    // ============================================================================

    /// Mint USDC coins cho testing (unlimited amounts)
    public fun mint_usdc(
        factory: &mut CoinFactory,
        amount: u64,
        ctx: &mut TxContext
    ): Coin<USDC> {
        coin::mint(&mut factory.usdc_treasury, amount, ctx)
    }

    /// Mint USDT coins
    public fun mint_usdt(
        factory: &mut CoinFactory,
        amount: u64,
        ctx: &mut TxContext
    ): Coin<USDT> {
        coin::mint(&mut factory.usdt_treasury, amount, ctx)
    }

    /// Mint WETH coins
    public fun mint_weth(
        factory: &mut CoinFactory,
        amount: u64,
        ctx: &mut TxContext
    ): Coin<WETH> {
        coin::mint(&mut factory.weth_treasury, amount, ctx)
    }

    /// Mint BTC coins
    public fun mint_btc(
        factory: &mut CoinFactory,
        amount: u64,
        ctx: &mut TxContext
    ): Coin<BTC> {
        coin::mint(&mut factory.btc_treasury, amount, ctx)
    }

    /// Mint SUI coins
    public fun mint_sui_coin(
        factory: &mut CoinFactory,
        amount: u64,
        ctx: &mut TxContext
    ): Coin<SUI_COIN> {
        coin::mint(&mut factory.sui_treasury, amount, ctx)
    }

    /// Burn USDC coins (for cleanup)
    public fun burn_usdc(factory: &mut CoinFactory, coin: Coin<USDC>): u64 {
        coin::burn(&mut factory.usdc_treasury, coin)
    }

    /// Burn USDT coins
    public fun burn_usdt(factory: &mut CoinFactory, coin: Coin<USDT>): u64 {
        coin::burn(&mut factory.usdt_treasury, coin)
    }

    /// Burn WETH coins
    public fun burn_weth(factory: &mut CoinFactory, coin: Coin<WETH>): u64 {
        coin::burn(&mut factory.weth_treasury, coin)
    }

    // ============================================================================
    // Getters
    // ============================================================================

    /// Get USDC total supply
    public fun get_usdc_total_supply(factory: &CoinFactory): u64 {
        coin::total_supply(&factory.usdc_treasury)
    }

    public fun get_usdt_total_supply(factory: &CoinFactory): u64 {
        coin::total_supply(&factory.usdt_treasury)
    }

    public fun get_weth_total_supply(factory: &CoinFactory): u64 {
        coin::total_supply(&factory.weth_treasury)
    }

    #[test_only]
    /// Initialize for testing - init all coin modules and create factory
    public fun init_for_testing(ctx: &mut TxContext) {
        // Initialize all coin modules
        simulation::usdc::test_init(ctx);
        simulation::usdt::test_init(ctx);
        simulation::weth::test_init(ctx);
        simulation::btc::test_init(ctx);
        simulation::sui_coin::test_init(ctx);
    }
}
