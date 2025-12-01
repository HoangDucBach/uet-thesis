// sources/infrastructure/test_coins/usdc.move
module simulation::usdc {
    use sui::coin;

    /// One-Time Witness for USDC
    public struct USDC has drop {}

    /// Initialize USDC currency
    #[allow(lint(share_owned))]
    fun init(witness: USDC, ctx: &mut TxContext) {
        let (treasury, metadata) = coin::create_currency(
            witness,
            6,
            b"USDC",
            b"USD Coin",
            b"Test USDC for simulation",
            std::option::none(),
            ctx
        );
        transfer::public_freeze_object(metadata);
        transfer::public_transfer(treasury, ctx.sender());
    }

    #[test_only]
    public fun test_init(ctx: &mut TxContext) {
        init(USDC {}, ctx);
    }
}
