// sources/infrastructure/test_coins/sui_coin.move
module simulation::sui_coin {
    use sui::coin;

    /// One-Time Witness for SUI_COIN
    public struct SUI_COIN has drop {}

    /// Initialize SUI_COIN currency
    #[allow(lint(share_owned))]
    fun init(witness: SUI_COIN, ctx: &mut TxContext) {
        let (treasury, metadata) = coin::create_currency(
            witness,
            9,
            b"SUI",
            b"Sui Token",
            b"Test SUI for simulation",
            std::option::none(),
            ctx
        );
        transfer::public_freeze_object(metadata);
        transfer::public_transfer(treasury, ctx.sender());
    }

    #[test_only]
    public fun test_init(ctx: &mut TxContext) {
        init(SUI_COIN {}, ctx);
    }
}
