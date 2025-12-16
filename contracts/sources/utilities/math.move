// sources/utilities/math.move
module simulation::math_utils;

/// Math utilities for simulation

/// Calculate minimum of two u64 values
public fun min(a: u64, b: u64): u64 {
    if (a < b) { a } else { b }
}

/// Calculate maximum of two u64 values
public fun max(a: u64, b: u64): u64 {
    if (a > b) { a } else { b }
}

/// Calculate absolute difference
public fun abs_diff(a: u64, b: u64): u64 {
    if (a > b) {
        a - b
    } else {
        b - a
    }
}

/// Calculate percentage (result in basis points)
public fun percentage(numerator: u64, denominator: u64): u64 {
    if (denominator == 0) {
        0
    } else {
        (numerator * 10000) / denominator
    }
}

/// Calculate price impact in basis points
public fun calculate_price_impact(amount_in: u64, reserve_in: u64, reserve_out: u64): u64 {
    if (reserve_in == 0 || reserve_out == 0) {
        return 10000 // 100% impact if no liquidity
    };

    // Price impact = (amount_out / reserve_out) * 10000
    let amount_out = (amount_in * reserve_out) / (reserve_in + amount_in);
    (amount_out * 10000) / reserve_out
}

/// Safe multiplication with overflow check
public fun safe_mul(a: u64, b: u64): u64 {
    // In production, this should check for overflow
    // For simulation, we assume inputs are reasonable
    a * b
}

/// Safe division with zero check
public fun safe_div(a: u64, b: u64): u64 {
    assert!(b != 0, 0);
    a / b
}

/// Calculate basis points (bps)
/// Example: 1% = 100 bps, 0.3% = 30 bps
public fun to_basis_points(percentage_numerator: u64, percentage_denominator: u64): u64 {
    (percentage_numerator * 10000) / percentage_denominator
}

/// Apply basis points to an amount
/// Example: apply_bps(1000, 500) = 1000 * 5% = 50
public fun apply_bps(amount: u64, bps: u64): u64 {
    (amount * bps) / 10000
}

/// Calculate AMM constant product
public fun constant_product(reserve_a: u64, reserve_b: u64): u64 {
    reserve_a * reserve_b
}

/// Calculate square root using Babylonian method (simplified for u128)
/// For simulation purposes - not production-grade precision
public fun sqrt(n: u128): u64 {
    if (n == 0) {
        return 0
    };
    if (n < 4) {
        return 1
    };

    let mut x = n;
    let mut y = (x + 1) / 2;
    while (y < x) {
        x = y;
        y = (x + n / x) / 2;
    };
    (x as u64)
}
