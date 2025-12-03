// sources/infrastructure/coins.move
// All coin types in one file for easy management, but separate modules for OTW

module simulation::usdc {
    use sui::coin;

    /// USDC - USD Coin
    public struct USDC has drop {}

    /// Initialize USDC currency
    #[allow(lint(share_owned), deprecated_usage, lint(self_transfer))]
    fun init(witness: USDC, ctx: &mut TxContext) {
        let (treasury, metadata) = coin::create_currency(
            witness,
            6,
            b"USDC",
            b"USD Coin",
            b"USD Coin stablecoin",
            std::option::none(),
            ctx,
        );
        transfer::public_freeze_object(metadata);
        transfer::public_transfer(treasury, ctx.sender());
    }

    #[test_only]
    public fun test_init(ctx: &mut TxContext) {
        init(USDC {}, ctx);
    }
}

module simulation::usdt {
    use sui::coin;

    /// USDT - Tether USD
    public struct USDT has drop {}

    /// Initialize USDT currency
    #[allow(lint(share_owned), deprecated_usage, lint(self_transfer))]
    fun init(witness: USDT, ctx: &mut TxContext) {
        let (treasury, metadata) = coin::create_currency(
            witness,
            6,
            b"USDT",
            b"Tether USD",
            b"Tether USD stablecoin",
            std::option::none(),
            ctx,
        );
        transfer::public_freeze_object(metadata);
        transfer::public_transfer(treasury, ctx.sender());
    }

    #[test_only]
    public fun test_init(ctx: &mut TxContext) {
        init(USDT {}, ctx);
    }
}

module simulation::weth {
    use sui::coin;

    /// WETH - Wrapped ETH
    public struct WETH has drop {}

    /// Initialize WETH currency
    #[allow(lint(share_owned), deprecated_usage, lint(self_transfer))]
    fun init(witness: WETH, ctx: &mut TxContext) {
        let (treasury, metadata) = coin::create_currency(
            witness,
            8,
            b"WETH",
            b"Wrapped ETH",
            b"Wrapped Ethereum",
            std::option::none(),
            ctx,
        );
        transfer::public_freeze_object(metadata);
        transfer::public_transfer(treasury, ctx.sender());
    }

    #[test_only]
    public fun test_init(ctx: &mut TxContext) {
        init(WETH {}, ctx);
    }
}

module simulation::btc {
    use sui::coin;

    /// BTC - Bitcoin
    public struct BTC has drop {}

    /// Initialize BTC currency
    #[allow(lint(share_owned), deprecated_usage, lint(self_transfer))]
    fun init(witness: BTC, ctx: &mut TxContext) {
        let (treasury, metadata) = coin::create_currency(
            witness,
            8,
            b"BTC",
            b"Bitcoin",
            b"Wrapped Bitcoin",
            std::option::none(),
            ctx,
        );
        transfer::public_freeze_object(metadata);
        transfer::public_transfer(treasury, ctx.sender());
    }

    #[test_only]
    public fun test_init(ctx: &mut TxContext) {
        init(BTC {}, ctx);
    }
}

module simulation::sui_coin {
    use sui::coin;

    /// SUI_COIN - Sui Token
    public struct SUI_COIN has drop {}

    /// Initialize SUI_COIN currency
    #[allow(lint(share_owned), deprecated_usage, lint(self_transfer))]
    fun init(witness: SUI_COIN, ctx: &mut TxContext) {
        let (treasury, metadata) = coin::create_currency(
            witness,
            9,
            b"SUI",
            b"Sui Token",
            b"Sui native token",
            std::option::none(),
            ctx,
        );
        transfer::public_freeze_object(metadata);
        transfer::public_transfer(treasury, ctx.sender());
    }

    #[test_only]
    public fun test_init(ctx: &mut TxContext) {
        init(SUI_COIN {}, ctx);
    }
}
