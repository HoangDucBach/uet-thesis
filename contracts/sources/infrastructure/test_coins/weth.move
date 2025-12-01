// sources/infrastructure/test_coins/weth.move
module simulation::weth {
    use sui::coin;

    /// One-Time Witness for WETH
    public struct WETH has drop {}

    /// Initialize WETH currency
    #[allow(lint(share_owned))]
    fun init(witness: WETH, ctx: &mut TxContext) {
        let (treasury, metadata) = coin::create_currency(
            witness,
            8,
            b"WETH",
            b"Wrapped ETH",
            b"Test WETH for simulation",
            std::option::none(),
            ctx
        );
        transfer::public_freeze_object(metadata);
        transfer::public_transfer(treasury, ctx.sender());
    }

    #[test_only]
    public fun test_init(ctx: &mut TxContext) {
        init(WETH {}, ctx);
    }
}
