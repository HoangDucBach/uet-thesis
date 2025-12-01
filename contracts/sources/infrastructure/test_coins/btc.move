// sources/infrastructure/test_coins/btc.move
module simulation::btc {
    use sui::coin;

    /// One-Time Witness for BTC
    public struct BTC has drop {}

    /// Initialize BTC currency
    #[allow(lint(share_owned))]
    fun init(witness: BTC, ctx: &mut TxContext) {
        let (treasury, metadata) = coin::create_currency(
            witness,
            8,
            b"BTC",
            b"Bitcoin",
            b"Test BTC for simulation",
            std::option::none(),
            ctx
        );
        transfer::public_freeze_object(metadata);
        transfer::public_transfer(treasury, ctx.sender());
    }

    #[test_only]
    public fun test_init(ctx: &mut TxContext) {
        init(BTC {}, ctx);
    }
}
