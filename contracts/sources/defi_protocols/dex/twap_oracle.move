// sources/defi_protocols/dex/twap_oracle.move
// Time-Weighted Average Price (TWAP) Oracle - Uniswap V2 style
#[allow(deprecated_usage)]
module simulation::twap_oracle;

use std::type_name::{Self, TypeName};
use sui::clock::{Self, Clock};
use sui::event;

// ============================================================================
// Constants & Errors
// ============================================================================

const E_INSUFFICIENT_OBSERVATIONS: u64 = 1;
const E_INVALID_WINDOW: u64 = 2;
const E_STALE_PRICE: u64 = 3;
const E_ZERO_RESERVES: u64 = 4;

// Minimum observations required for TWAP
const MIN_OBSERVATIONS: u64 = 2;

// Maximum staleness in milliseconds (30 minutes)
const MAX_STALENESS_MS: u64 = 1800000;

// ============================================================================
// Structs
// ============================================================================

/// Single price observation with cumulative price
public struct PriceObservation has copy, drop, store {
    timestamp: u64, // Block timestamp in ms
    price_cumulative_a: u128, // Cumulative TokenA/TokenB price
    price_cumulative_b: u128, // Cumulative TokenB/TokenA price
    reserve_a: u64, // Reserve A at observation
    reserve_b: u64, // Reserve B at observation
}

/// TWAP Oracle for a specific pool pair
public struct TWAPOracle<phantom TokenA, phantom TokenB> has key {
    id: UID,
    pool_id: address, // Pool being tracked
    observations: vector<PriceObservation>, // Circular buffer of observations
    max_observations: u64, // Maximum observations to store
    window_size_ms: u64, // TWAP window in milliseconds
    last_update: u64, // Last update timestamp
    update_interval_ms: u64, // Minimum time between updates
}

/// TWAP updated event
public struct TWAPUpdated has copy, drop {
    pool_id: address,
    token_a: TypeName,
    token_b: TypeName,
    twap_price_a: u64, // TWAP for TokenA/TokenB (scaled by 1e9)
    twap_price_b: u64, // TWAP for TokenB/TokenA (scaled by 1e9)
    spot_price_a: u64, // Current spot price
    spot_price_b: u64, // Current spot price
    price_deviation: u64, // Deviation % (basis points)
    timestamp: u64,
}

/// Price manipulation detected event (emitted when deviation is high)
public struct PriceDeviationDetected has copy, drop {
    pool_id: address,
    token_a: TypeName,
    token_b: TypeName,
    twap_price: u64,
    spot_price: u64,
    deviation_bps: u64, // Deviation in basis points (10000 = 100%)
    timestamp: u64,
}

// ============================================================================
// Public Functions
// ============================================================================

/// Create TWAP oracle for a pool
public fun create_oracle<TokenA, TokenB>(
    pool_id: address,
    window_size_ms: u64, // e.g., 1800000 for 30 minutes
    update_interval_ms: u64, // e.g., 60000 for 1 minute
    ctx: &mut TxContext,
) {
    assert!(window_size_ms > 0, E_INVALID_WINDOW);

    let oracle = TWAPOracle<TokenA, TokenB> {
        id: object::new(ctx),
        pool_id,
        observations: vector::empty(),
        max_observations: 30, // Store 30 observations max
        window_size_ms,
        last_update: 0,
        update_interval_ms,
    };

    transfer::share_object(oracle);
}

/// Update oracle with new price observation (called after swaps)
public fun update_observation<TokenA, TokenB>(
    oracle: &mut TWAPOracle<TokenA, TokenB>,
    reserve_a: u64,
    reserve_b: u64,
    clock: &Clock,
) {
    assert!(reserve_a > 0 && reserve_b > 0, E_ZERO_RESERVES);

    let current_time = clock::timestamp_ms(clock);

    // Check if enough time has passed since last update
    if (
        oracle.last_update > 0 &&
            current_time - oracle.last_update < oracle.update_interval_ms
    ) {
        return // Skip update if too soon
    };

    // Calculate cumulative prices
    let (price_cum_a, price_cum_b) = if (vector::length(&oracle.observations) > 0) {
        let last_obs = vector::borrow(
            &oracle.observations,
            vector::length(&oracle.observations) - 1,
        );
        let time_elapsed = current_time - last_obs.timestamp;

        // Price = reserve_b / reserve_a (scaled by 1e18 for precision)
        let price_a = ((reserve_b as u128) * 1000000000) / (reserve_a as u128);
        let price_b = ((reserve_a as u128) * 1000000000) / (reserve_b as u128);

        // Cumulative price += price * time_elapsed
        (
            last_obs.price_cumulative_a + (price_a * (time_elapsed as u128)),
            last_obs.price_cumulative_b + (price_b * (time_elapsed as u128)),
        )
    } else {
        // First observation
        (0u128, 0u128)
    };

    // Create new observation
    let observation = PriceObservation {
        timestamp: current_time,
        price_cumulative_a: price_cum_a,
        price_cumulative_b: price_cum_b,
        reserve_a,
        reserve_b,
    };

    // Add observation (circular buffer)
    vector::push_back(&mut oracle.observations, observation);

    if (vector::length(&oracle.observations) > oracle.max_observations) {
        vector::remove(&mut oracle.observations, 0); // Remove oldest
    };

    oracle.last_update = current_time;

    // Emit TWAP update event with deviation detection
    emit_twap_update<TokenA, TokenB>(oracle, reserve_a, reserve_b, clock);
}

/// Get TWAP price for TokenA/TokenB over the configured window
public fun get_twap<TokenA, TokenB>(
    oracle: &TWAPOracle<TokenA, TokenB>,
    clock: &Clock,
): (u64, u64) {
    let obs_count = vector::length(&oracle.observations);
    assert!(obs_count >= MIN_OBSERVATIONS, E_INSUFFICIENT_OBSERVATIONS);

    let current_time = clock::timestamp_ms(clock);
    let latest_obs = vector::borrow(&oracle.observations, obs_count - 1);

    // Check staleness
    assert!(current_time - latest_obs.timestamp < MAX_STALENESS_MS, E_STALE_PRICE);

    // Find observation at window start
    let window_start = if (current_time > oracle.window_size_ms) {
        current_time - oracle.window_size_ms
    } else {
        0
    };

    // Find closest observation to window start
    let start_index = find_observation_index(&oracle.observations, window_start);
    let start_obs = vector::borrow(&oracle.observations, start_index);

    // Calculate TWAP
    let time_diff = latest_obs.timestamp - start_obs.timestamp;
    if (time_diff == 0) {
        // Fallback to spot price
        let spot_a = (latest_obs.reserve_b * 1000000000) / latest_obs.reserve_a;
        let spot_b = (latest_obs.reserve_a * 1000000000) / latest_obs.reserve_b;
        return ((spot_a as u64), (spot_b as u64))
    };

    let price_cum_diff_a = latest_obs.price_cumulative_a - start_obs.price_cumulative_a;
    let price_cum_diff_b = latest_obs.price_cumulative_b - start_obs.price_cumulative_b;

    let twap_a = (price_cum_diff_a / (time_diff as u128)) as u64;
    let twap_b = (price_cum_diff_b / (time_diff as u128)) as u64;

    (twap_a, twap_b)
}

/// Get current spot price from latest observation
public fun get_spot_price<TokenA, TokenB>(oracle: &TWAPOracle<TokenA, TokenB>): (u64, u64) {
    let obs_count = vector::length(&oracle.observations);
    assert!(obs_count > 0, E_INSUFFICIENT_OBSERVATIONS);

    let latest = vector::borrow(&oracle.observations, obs_count - 1);
    let spot_a = (latest.reserve_b * 1000000000) / latest.reserve_a;
    let spot_b = (latest.reserve_a * 1000000000) / latest.reserve_b;

    ((spot_a as u64), (spot_b as u64))
}

// ============================================================================
// Internal Functions
// ============================================================================

/// Find observation index closest to target timestamp
fun find_observation_index(observations: &vector<PriceObservation>, target_time: u64): u64 {
    let len = vector::length(observations);
    let mut i = 0;
    let mut closest_index = 0;

    while (i < len) {
        let obs = vector::borrow(observations, i);
        if (obs.timestamp <= target_time) {
            closest_index = i;
        };
        i = i + 1;
    };

    closest_index
}

/// Emit TWAP update with deviation detection
fun emit_twap_update<TokenA, TokenB>(
    oracle: &TWAPOracle<TokenA, TokenB>,
    _reserve_a: u64,
    _reserve_b: u64,
    clock: &Clock,
) {
    let obs_count = vector::length(&oracle.observations);

    if (obs_count < MIN_OBSERVATIONS) {
        return // Not enough data yet
    };

    // Get TWAP and spot prices
    let (twap_a, twap_b) = get_twap<TokenA, TokenB>(oracle, clock);
    let (spot_a, spot_b) = get_spot_price<TokenA, TokenB>(oracle);

    // Calculate deviation (basis points)
    let deviation_a = if (twap_a > 0) {
        let diff = if (spot_a > twap_a) {
            spot_a - twap_a
        } else {
            twap_a - spot_a
        };
        (diff * 10000) / twap_a
    } else {
        0
    };

    event::emit(TWAPUpdated {
        pool_id: oracle.pool_id,
        token_a: type_name::get_with_original_ids<TokenA>(),
        token_b: type_name::get_with_original_ids<TokenB>(),
        twap_price_a: twap_a,
        twap_price_b: twap_b,
        spot_price_a: spot_a,
        spot_price_b: spot_b,
        price_deviation: deviation_a,
        timestamp: clock::timestamp_ms(clock),
    });

    // Emit deviation alert if > 10%
    if (deviation_a > 1000) {
        event::emit(PriceDeviationDetected {
            pool_id: oracle.pool_id,
            token_a: type_name::get_with_original_ids<TokenA>(),
            token_b: type_name::get_with_original_ids<TokenB>(),
            twap_price: twap_a,
            spot_price: spot_a,
            deviation_bps: deviation_a,
            timestamp: clock::timestamp_ms(clock),
        });
    };
}

// ============================================================================
// Getters
// ============================================================================

/// Get oracle pool ID
public fun get_pool_id<TokenA, TokenB>(oracle: &TWAPOracle<TokenA, TokenB>): address {
    oracle.pool_id
}

/// Get number of observations
public fun get_observation_count<TokenA, TokenB>(oracle: &TWAPOracle<TokenA, TokenB>): u64 {
    vector::length(&oracle.observations)
}

/// Get oracle window size
public fun get_window_size<TokenA, TokenB>(oracle: &TWAPOracle<TokenA, TokenB>): u64 {
    oracle.window_size_ms
}
