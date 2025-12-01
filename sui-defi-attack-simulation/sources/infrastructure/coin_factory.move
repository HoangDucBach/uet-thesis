// sources/infrastructure/coin_factory.move
module simulation::coin_factory {
    use std::option;
    use sui::object::{Self, UID};
    use sui::coin::{Self, Coin, TreasuryCap};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};

    /// Test coin types for simulation
    public struct USDC has drop {}
    public struct USDT has drop {}
    public struct WETH has drop {}
    public struct BTC has drop {}
    public struct SUI_COIN has drop {}

    /// Coin factory capability - holds all treasury caps
    public struct CoinFactory has key {
        id: UID,
        usdc_treasury: TreasuryCap<USDC>,
        usdt_treasury: TreasuryCap<USDT>,
        weth_treasury: TreasuryCap<WETH>,
        btc_treasury: TreasuryCap<BTC>,
        sui_treasury: TreasuryCap<SUI_COIN>,
    }

    /// Initialize coin factory với unlimited minting cho testing
    fun init(ctx: &mut TxContext) {
        // Create USDC
        let (usdc_treasury, usdc_metadata) = coin::create_currency(
            USDC {},
            6,
            b"USDC",
            b"USD Coin",
            b"Test USDC for simulation",
            option::none(),
            ctx
        );
        transfer::public_freeze_object(usdc_metadata);

        // Create USDT
        let (usdt_treasury, usdt_metadata) = coin::create_currency(
            USDT {},
            6,
            b"USDT",
            b"Tether USD",
            b"Test USDT for simulation",
            option::none(),
            ctx
        );
        transfer::public_freeze_object(usdt_metadata);

        // Create WETH
        let (weth_treasury, weth_metadata) = coin::create_currency(
            WETH {},
            8,
            b"WETH",
            b"Wrapped ETH",
            b"Test WETH for simulation",
            option::none(),
            ctx
        );
        transfer::public_freeze_object(weth_metadata);

        // Create BTC
        let (btc_treasury, btc_metadata) = coin::create_currency(
            BTC {},
            8,
            b"BTC",
            b"Bitcoin",
            b"Test BTC for simulation",
            option::none(),
            ctx
        );
        transfer::public_freeze_object(btc_metadata);

        // Create SUI_COIN
        let (sui_treasury, sui_metadata) = coin::create_currency(
            SUI_COIN {},
            9,
            b"SUI",
            b"Sui Token",
            b"Test SUI for simulation",
            option::none(),
            ctx
        );
        transfer::public_freeze_object(sui_metadata);

        // Create and share the factory
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

    /// Utility functions - Get total supply
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
    /// Initialize for testing
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx);
    }
}
