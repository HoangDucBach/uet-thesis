// sources/infrastructure/price_oracle.move
module simulation::price_oracle {
    use sui::object::{Self, UID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::clock::{Self, Clock};
    use sui::event;
    use sui::table::{Self, Table};
    use sui::vec_set::{Self, VecSet};
    use std::type_name::{Self, TypeName};

    /// Oracle errors
    const E_STALE_PRICE: u64 = 1;
    const E_INVALID_PRICE: u64 = 2;
    const E_NOT_AUTHORIZED: u64 = 3;

    /// Price feed entry
    public struct PriceFeed has copy, drop, store {
        price: u64,          // Price in USD with 8 decimals
        confidence: u64,     // Confidence interval
        timestamp: u64,      // Last update timestamp
        source: address,     // Price source/updater
    }

    /// Global price oracle
    public struct PriceOracle has key {
        id: UID,
        feeds: Table<TypeName, PriceFeed>,
        authorized_sources: VecSet<address>,
        admin: address,
    }

    /// Events
    public struct PriceUpdated has copy, drop {
        token_type: TypeName,
        old_price: u64,
        new_price: u64,
        price_change_pct: u64, // Basis points (10000 = 100%)
        timestamp: u64,
    }

    public struct PriceManipulationDetected has copy, drop {
        token_type: TypeName,
        price_change_pct: u64,
        manipulator: address,
        timestamp: u64,
    }

    /// Initialize oracle
    fun init(ctx: &mut TxContext) {
        let oracle = PriceOracle {
            id: object::new(ctx),
            feeds: table::new(ctx),
            authorized_sources: vec_set::empty(),
            admin: tx_context::sender(ctx),
        };

        transfer::share_object(oracle);
    }

    /// Update price (can be manipulated for testing)
    public fun update_price<T>(
        oracle: &mut PriceOracle,
        price: u64,
        confidence: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        let token_type = type_name::get<T>();
        let timestamp = clock::timestamp_ms(clock);

        // Get old price for event
        let old_price = if (table::contains(&oracle.feeds, token_type)) {
            table::borrow(&oracle.feeds, token_type).price
        } else {
            0
        };

        let new_feed = PriceFeed {
            price,
            confidence,
            timestamp,
            source: sender,
        };

        // Calculate price change percentage
        let price_change_pct = if (old_price > 0) {
            if (price > old_price) {
                ((price - old_price) * 10000) / old_price
            } else {
                ((old_price - price) * 10000) / old_price
            }
        } else {
            0
        };

        // Detect potential manipulation (>10% change)
        if (price_change_pct > 1000) { // 10%
            event::emit(PriceManipulationDetected {
                token_type,
                price_change_pct,
                manipulator: sender,
                timestamp,
            });
        };

        // Update price feed
        if (table::contains(&oracle.feeds, token_type)) {
            let feed_ref = table::borrow_mut(&mut oracle.feeds, token_type);
            *feed_ref = new_feed;
        } else {
            table::add(&mut oracle.feeds, token_type, new_feed);
        };

        // Emit price update event
        event::emit(PriceUpdated {
            token_type,
            old_price,
            new_price: price,
            price_change_pct,
            timestamp,
        });
    }

    /// Get current price (with staleness check)
    public fun get_price<T>(
        oracle: &PriceOracle,
        clock: &Clock
    ): (u64, u64) { // (price, confidence)
        let token_type = type_name::get<T>();
        assert!(table::contains(&oracle.feeds, token_type), E_STALE_PRICE);

        let feed = table::borrow(&oracle.feeds, token_type);
        let current_time = clock::timestamp_ms(clock);

        // Check staleness (5 minutes)
        assert!(current_time - feed.timestamp < 300_000, E_STALE_PRICE);

        (feed.price, feed.confidence)
    }

    /// Force price update (for manipulation testing)
    public fun manipulate_price<T>(
        oracle: &mut PriceOracle,
        new_price: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        // Anyone can manipulate price in simulation environment
        update_price<T>(oracle, new_price, 1000000, clock, ctx);
    }

    /// Get price without staleness check (for historical analysis)
    public fun get_price_unsafe<T>(oracle: &PriceOracle): u64 {
        let token_type = type_name::get<T>();
        if (table::contains(&oracle.feeds, token_type)) {
            table::borrow(&oracle.feeds, token_type).price
        } else {
            0
        }
    }

    /// Add authorized source
    public fun add_authorized_source(
        oracle: &mut PriceOracle,
        source: address,
        ctx: &TxContext
    ) {
        assert!(tx_context::sender(ctx) == oracle.admin, E_NOT_AUTHORIZED);
        vec_set::insert(&mut oracle.authorized_sources, source);
    }

    /// Remove authorized source
    public fun remove_authorized_source(
        oracle: &mut PriceOracle,
        source: address,
        ctx: &TxContext
    ) {
        assert!(tx_context::sender(ctx) == oracle.admin, E_NOT_AUTHORIZED);
        vec_set::remove(&mut oracle.authorized_sources, &source);
    }

    /// Check if source is authorized
    public fun is_authorized(oracle: &PriceOracle, source: address): bool {
        vec_set::contains(&oracle.authorized_sources, &source)
    }

    #[test_only]
    /// Initialize for testing
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx);
    }
}
