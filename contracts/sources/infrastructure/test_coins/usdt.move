// sources/infrastructure/test_coins/usdt.move
module simulation::usdt {
    use sui::coin;

    /// One-Time Witness for USDT
    public struct USDT has drop {}

    /// Initialize USDT currency
    #[allow(lint(share_owned))]
    fun init(witness: USDT, ctx: &mut TxContext) {
        let (treasury, metadata) = coin::create_currency(
            witness,
            6,
            b"USDT",
            b"Tether USD",
            b"Test USDT for simulation",
            std::option::none(),
            ctx
        );
        transfer::public_freeze_object(metadata);
        transfer::public_transfer(treasury, ctx.sender());
    }

    #[test_only]
    public fun test_init(ctx: &mut TxContext) {
        init(USDT {}, ctx);
    }
}
