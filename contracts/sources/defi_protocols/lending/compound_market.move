// Copyright (c) 2024 DeFi Protocol
// SPDX-License-Identifier: Apache-2.0

/// Compound-style lending market implementation
///
/// Based on Compound Finance V2 architecture:
/// - Supply assets to earn interest
/// - Borrow against collateral
/// - Liquidation mechanism for underwater positions
/// - cToken model for representing supplied assets
///
/// References:
/// - Compound V2 Whitepaper: https://compound.finance/documents/Compound.Whitepaper.pdf
/// - Compound Docs: https://docs.compound.finance/

module simulation::compound_market;

use simulation::simple_dex::{Self, Pool};
use sui::balance::{Self, Balance};
use sui::clock::{Self, Clock};
use sui::coin::{Self, Coin};
use sui::event;

// ============================================================================
// Constants
// ============================================================================

/// Precision for calculations (1e9)
const PRECISION: u64 = 1_000_000_000;

/// Basis points precision (10000 = 100%)
const BPS_PRECISION: u64 = 10000;

/// Initial exchange rate: 1 cToken = 0.02 underlying (1:0.02 = 50:1)
const INITIAL_EXCHANGE_RATE: u64 = 20_000_000; // 0.02 * 1e9

/// Liquidation incentive (5% = 500 bps)
const LIQUIDATION_INCENTIVE: u64 = 500;

/// Close factor (50% = 5000 bps) - max portion that can be liquidated
const CLOSE_FACTOR: u64 = 5000;

// ============================================================================
// Error Codes
// ============================================================================

const E_INSUFFICIENT_LIQUIDITY: u64 = 1;
const E_INSUFFICIENT_COLLATERAL: u64 = 2;
const E_POSITION_HEALTHY: u64 = 3;
const E_INVALID_AMOUNT: u64 = 4;

// ============================================================================
// Structs
// ============================================================================

/// Represents a lending market for a specific asset
/// Similar to Compound's cToken contract
public struct Market<phantom T> has key, store {
    id: UID,
    /// Total supply of underlying assets
    total_cash: Balance<T>,
    /// Total amount borrowed
    total_borrows: u64,
    /// Total reserves accumulated
    total_reserves: Balance<T>,
    /// Total cTokens in circulation
    total_supply: u64,
    /// Reserve factor (portion of interest to reserves) - 10% = 1000 bps
    reserve_factor: u64,
    /// Collateral factor (max LTV ratio) - 75% = 7500 bps
    collateral_factor: u64,
    /// Liquidation threshold - 80% = 8000 bps
    liquidation_threshold: u64,
    /// Base rate per second (APY calculation)
    base_rate_per_second: u64,
    /// Multiplier for utilization rate
    multiplier_per_second: u64,
    /// Jump multiplier after kink
    jump_multiplier_per_second: u64,
    /// Kink point (optimal utilization) - 80% = 8000 bps
    kink: u64,
    /// Last accrual timestamp
    accrual_block_timestamp: u64,
    /// Borrow index for interest accrual
    borrow_index: u64,
    /// Oracle pool for price feeds
    oracle_pool_id: address,
}

/// Represents user's position in a market
/// Tracks supplied collateral and borrowed amount
public struct Position<phantom T> has key, store {
    id: UID,
    market_id: address,
    owner: address,
    /// Amount of cTokens owned (represents supplied assets)
    c_token_balance: u64,
    /// Amount borrowed with interest
    borrow_balance: u64,
    /// Borrow index at last interaction
    borrow_index: u64,
}

/// cToken - represents supplied assets earning interest
/// Similar to Compound's cToken
#[allow(unused_field)]
public struct CToken<phantom T> has key, store {
    id: UID,
    market_id: address,
    amount: u64,
}

// ============================================================================
// Events
// ============================================================================

/// Emitted when user supplies assets to market
public struct SupplyEvent<phantom T> has copy, drop {
    market_id: address,
    supplier: address,
    amount: u64,
    c_tokens_minted: u64,
    exchange_rate: u64,
    timestamp: u64,
}

/// Emitted when user borrows assets
public struct BorrowEvent<phantom T> has copy, drop {
    market_id: address,
    borrower: address,
    position_id: address,
    borrow_amount: u64,
    collateral_value: u64,
    oracle_price: u64,
    health_factor: u64,
    total_borrows: u64,
    timestamp: u64,
}

/// Emitted when user repays debt
public struct RepayEvent<phantom T> has copy, drop {
    market_id: address,
    borrower: address,
    position_id: address,
    repay_amount: u64,
    remaining_debt: u64,
    timestamp: u64,
}

/// Emitted when position is liquidated
public struct LiquidationEvent<phantom T> has copy, drop {
    market_id: address,
    liquidator: address,
    borrower: address,
    position_id: address,
    debt_repaid: u64,
    collateral_seized: u64,
    liquidation_incentive: u64,
    health_factor_before: u64,
    protocol_loss: u64,
    timestamp: u64,
}

/// Emitted when interest is accrued
public struct AccrueInterestEvent<phantom T> has copy, drop {
    market_id: address,
    borrow_rate: u64,
    supply_rate: u64,
    total_borrows: u64,
    total_reserves: u64,
    borrow_index: u64,
    timestamp: u64,
}

// ============================================================================
// Market Creation & Configuration
// ============================================================================

/// Create a new lending market for asset T
///
/// Parameters:
/// - initial_liquidity: Initial assets to seed the market
/// - oracle_pool_id: DEX pool address for price oracle
/// - collateral_factor: Max LTV (e.g., 7500 = 75%)
/// - reserve_factor: Portion to reserves (e.g., 1000 = 10%)
public fun create_market<T>(
    initial_liquidity: Coin<T>,
    oracle_pool_id: address,
    collateral_factor: u64,
    reserve_factor: u64,
    clock: &Clock,
    ctx: &mut TxContext,
): Market<T> {
    let current_time = clock::timestamp_ms(clock) / 1000;

    Market<T> {
        id: object::new(ctx),
        total_cash: coin::into_balance(initial_liquidity),
        total_borrows: 0,
        total_reserves: balance::zero<T>(),
        total_supply: 0,
        reserve_factor,
        collateral_factor,
        liquidation_threshold: 8000, // 80%
        base_rate_per_second: 0, // 0% base APY
        multiplier_per_second: 95129375951, // ~3% at kink (calculated)
        jump_multiplier_per_second: 1268391679350, // ~40% after kink
        kink: 8000, // 80% utilization
        accrual_block_timestamp: current_time,
        borrow_index: PRECISION,
        oracle_pool_id,
    }
}

// ============================================================================
// Supply Functions (Similar to Compound's mint)
// ============================================================================

/// Supply assets to the market and receive cTokens
///
/// User deposits underlying assets and receives cTokens representing
/// their share of the pool. cTokens earn interest over time.
public fun supply<T>(
    market: &mut Market<T>,
    amount: Coin<T>,
    clock: &Clock,
    ctx: &mut TxContext,
): Position<T> {
    let supply_amount = coin::value(&amount);
    assert!(supply_amount > 0, E_INVALID_AMOUNT);

    // Accrue interest before supply
    accrue_interest(market, clock);

    // Calculate exchange rate and cTokens to mint
    let exchange_rate = get_exchange_rate(market);
    let c_tokens_to_mint = (supply_amount as u128) * (PRECISION as u128) / (exchange_rate as u128);
    let c_tokens_to_mint = (c_tokens_to_mint as u64);

    // Update market state
    balance::join(&mut market.total_cash, coin::into_balance(amount));
    market.total_supply = market.total_supply + c_tokens_to_mint;

    // Emit event
    event::emit(SupplyEvent<T> {
        market_id: object::uid_to_address(&market.id),
        supplier: tx_context::sender(ctx),
        amount: supply_amount,
        c_tokens_minted: c_tokens_to_mint,
        exchange_rate,
        timestamp: clock::timestamp_ms(clock) / 1000,
    });

    // Create position
    Position<T> {
        id: object::new(ctx),
        market_id: object::uid_to_address(&market.id),
        owner: tx_context::sender(ctx),
        c_token_balance: c_tokens_to_mint,
        borrow_balance: 0,
        borrow_index: market.borrow_index,
    }
}

/// Withdraw supplied assets by burning cTokens
public fun withdraw<T>(
    market: &mut Market<T>,
    position: &mut Position<T>,
    c_tokens_to_burn: u64,
    clock: &Clock,
    ctx: &mut TxContext,
): Coin<T> {
    assert!(c_tokens_to_burn <= position.c_token_balance, E_INVALID_AMOUNT);

    // Accrue interest
    accrue_interest(market, clock);

    // Calculate underlying amount to return
    let exchange_rate = get_exchange_rate(market);
    let underlying_amount =
        (c_tokens_to_burn as u128) * (exchange_rate as u128) / (PRECISION as u128);
    let underlying_amount = (underlying_amount as u64);

    // Check liquidity
    assert!(balance::value(&market.total_cash) >= underlying_amount, E_INSUFFICIENT_LIQUIDITY);

    // Update state
    position.c_token_balance = position.c_token_balance - c_tokens_to_burn;
    market.total_supply = market.total_supply - c_tokens_to_burn;

    // Transfer underlying
    coin::from_balance(balance::split(&mut market.total_cash, underlying_amount), ctx)
}

// ============================================================================
// Borrow Functions
// ============================================================================

/// Borrow assets against collateral
///
/// Uses DEX pool as price oracle to determine collateral value.
/// Vulnerable to price manipulation attacks (for research purposes).
public fun borrow<Collateral, Debt>(
    collateral_market: &mut Market<Collateral>,
    debt_market: &mut Market<Debt>,
    position: &mut Position<Collateral>,
    oracle: &Pool<Collateral, Debt>,
    borrow_amount: u64,
    clock: &Clock,
    ctx: &mut TxContext,
): Coin<Debt> {
    assert!(borrow_amount > 0, E_INVALID_AMOUNT);

    // Accrue interest on both markets
    accrue_interest(collateral_market, clock);
    accrue_interest(debt_market, clock);

    // Get oracle price (VULNERABLE to manipulation)
    let oracle_price = get_oracle_price(oracle);

    // Calculate collateral value in terms of debt asset
    let exchange_rate = get_exchange_rate(collateral_market);
    let underlying_collateral =
        (position.c_token_balance as u128) * (exchange_rate as u128) / (PRECISION as u128);
    let underlying_collateral = (underlying_collateral as u64);

    let collateral_value =
        (underlying_collateral as u128) * (oracle_price as u128) / (PRECISION as u128);
    let collateral_value = (collateral_value as u64);

    // Calculate max borrow based on collateral factor
    let max_borrow =
        (collateral_value as u128) * (collateral_market.collateral_factor as u128) / (BPS_PRECISION as u128);
    let max_borrow = (max_borrow as u64);

    // Check borrow capacity
    let new_borrow_balance = position.borrow_balance + borrow_amount;
    assert!(new_borrow_balance <= max_borrow, E_INSUFFICIENT_COLLATERAL);

    // Check market liquidity
    assert!(balance::value(&debt_market.total_cash) >= borrow_amount, E_INSUFFICIENT_LIQUIDITY);

    // Update position
    position.borrow_balance = new_borrow_balance;
    position.borrow_index = debt_market.borrow_index;

    // Update market
    debt_market.total_borrows = debt_market.total_borrows + borrow_amount;

    // Calculate health factor
    let health_factor = calculate_health_factor(
        collateral_value,
        new_borrow_balance,
        collateral_market.liquidation_threshold,
    );

    // Emit event
    event::emit(BorrowEvent<Debt> {
        market_id: object::uid_to_address(&debt_market.id),
        borrower: tx_context::sender(ctx),
        position_id: object::uid_to_address(&position.id),
        borrow_amount,
        collateral_value,
        oracle_price,
        health_factor,
        total_borrows: debt_market.total_borrows,
        timestamp: clock::timestamp_ms(clock) / 1000,
    });

    // Transfer borrowed assets
    coin::from_balance(balance::split(&mut debt_market.total_cash, borrow_amount), ctx)
}

/// Repay borrowed assets
public fun repay<Collateral, Debt>(
    market: &mut Market<Debt>,
    position: &mut Position<Collateral>,
    repayment: Coin<Debt>,
    clock: &Clock,
    ctx: &TxContext,
) {
    let repay_amount = coin::value(&repayment);

    // Accrue interest
    accrue_interest(market, clock);

    // Update borrow balance with accrued interest
    let accrued_interest = calculate_accrued_interest(
        position.borrow_balance,
        position.borrow_index,
        market.borrow_index,
    );
    let total_debt = position.borrow_balance + accrued_interest;

    // Cap repayment at total debt
    let actual_repay = if (repay_amount > total_debt) { total_debt } else { repay_amount };

    // Update state
    position.borrow_balance = total_debt - actual_repay;
    position.borrow_index = market.borrow_index;
    market.total_borrows = market.total_borrows - actual_repay;

    // Add to market cash
    balance::join(&mut market.total_cash, coin::into_balance(repayment));

    // Emit event
    event::emit(RepayEvent<Debt> {
        market_id: object::uid_to_address(&market.id),
        borrower: tx_context::sender(ctx),
        position_id: object::uid_to_address(&position.id),
        repay_amount: actual_repay,
        remaining_debt: position.borrow_balance,
        timestamp: clock::timestamp_ms(clock) / 1000,
    });
}

// ============================================================================
// Liquidation Functions
// ============================================================================

/// Liquidate underwater position
///
/// When health factor < 1.0, liquidators can repay debt and seize collateral
/// with a liquidation incentive (5% bonus).
public fun liquidate<Collateral, Debt>(
    collateral_market: &mut Market<Collateral>,
    debt_market: &mut Market<Debt>,
    position: &mut Position<Collateral>,
    oracle: &Pool<Collateral, Debt>,
    repayment: Coin<Debt>,
    clock: &Clock,
    ctx: &mut TxContext,
): Coin<Collateral> {
    // Accrue interest
    accrue_interest(collateral_market, clock);
    accrue_interest(debt_market, clock);

    // Get oracle price
    let oracle_price = get_oracle_price(oracle);

    // Calculate collateral value
    let exchange_rate = get_exchange_rate(collateral_market);
    let underlying_collateral =
        (position.c_token_balance as u128) * (exchange_rate as u128) / (PRECISION as u128);
    let underlying_collateral = (underlying_collateral as u64);

    let collateral_value =
        (underlying_collateral as u128) * (oracle_price as u128) / (PRECISION as u128);
    let collateral_value = (collateral_value as u64);

    // Update borrow with accrued interest
    let accrued_interest = calculate_accrued_interest(
        position.borrow_balance,
        position.borrow_index,
        debt_market.borrow_index,
    );
    let total_debt = position.borrow_balance + accrued_interest;

    // Check if position is underwater
    let health_factor = calculate_health_factor(
        collateral_value,
        total_debt,
        collateral_market.liquidation_threshold,
    );
    assert!(health_factor < BPS_PRECISION, E_POSITION_HEALTHY);

    // Calculate max seizable collateral (close factor * debt)
    let repay_amount = coin::value(&repayment);
    let max_close = (total_debt as u128) * (CLOSE_FACTOR as u128) / (BPS_PRECISION as u128);
    let max_close = (max_close as u64);
    let actual_repay = if (repay_amount > max_close) { max_close } else { repay_amount };

    // Calculate collateral to seize (with liquidation incentive)
    let incentive_multiplier = (BPS_PRECISION as u128) + (LIQUIDATION_INCENTIVE as u128);
    let seize_value = (actual_repay as u128) * incentive_multiplier / (BPS_PRECISION as u128);
    let seize_value = (seize_value as u64);
    let seize_amount = (seize_value as u128) * (PRECISION as u128) / (oracle_price as u128);
    let seize_amount = (seize_amount as u64);

    // Convert to cTokens
    let c_tokens_to_seize = (seize_amount as u128) * (PRECISION as u128) / (exchange_rate as u128);
    let c_tokens_to_seize = (c_tokens_to_seize as u64);

    // Check if enough collateral
    let actual_seize_c_tokens = if (c_tokens_to_seize > position.c_token_balance) {
        position.c_token_balance
    } else {
        c_tokens_to_seize
    };

    // Update position
    position.borrow_balance = total_debt - actual_repay;
    position.borrow_index = debt_market.borrow_index;
    position.c_token_balance = position.c_token_balance - actual_seize_c_tokens;

    // Update markets
    debt_market.total_borrows = debt_market.total_borrows - actual_repay;
    collateral_market.total_supply = collateral_market.total_supply - actual_seize_c_tokens;
    balance::join(&mut debt_market.total_cash, coin::into_balance(repayment));

    // Calculate actual underlying to transfer
    let underlying_to_transfer =
        (actual_seize_c_tokens as u128) * (exchange_rate as u128) / (PRECISION as u128);
    let underlying_to_transfer = (underlying_to_transfer as u64);

    // Calculate protocol loss (if bad debt remains)
    let protocol_loss = if (position.borrow_balance > 0 && position.c_token_balance == 0) {
        position.borrow_balance
    } else {
        0
    };

    // Emit event
    event::emit(LiquidationEvent<Collateral> {
        market_id: object::uid_to_address(&collateral_market.id),
        liquidator: tx_context::sender(ctx),
        borrower: position.owner,
        position_id: object::uid_to_address(&position.id),
        debt_repaid: actual_repay,
        collateral_seized: underlying_to_transfer,
        liquidation_incentive: (seize_value - actual_repay),
        health_factor_before: health_factor,
        protocol_loss,
        timestamp: clock::timestamp_ms(clock) / 1000,
    });

    // Transfer seized collateral
    coin::from_balance(
        balance::split(&mut collateral_market.total_cash, underlying_to_transfer),
        ctx,
    )
}

// ============================================================================
// Interest Rate & Accrual Functions
// ============================================================================

/// Accrue interest to borrows and reserves
/// Based on Compound's interest rate model
fun accrue_interest<T>(market: &mut Market<T>, clock: &Clock) {
    let current_time = clock::timestamp_ms(clock) / 1000;
    let time_delta = current_time - market.accrual_block_timestamp;

    if (time_delta == 0) {
        return
    };

    // Calculate borrow rate
    let borrow_rate = get_borrow_rate(market);

    // Calculate interest factor
    let interest_factor = (borrow_rate as u128) * (time_delta as u128);

    // Calculate interest accumulated
    let interest_accumulated =
        (market.total_borrows as u128) * interest_factor / (PRECISION as u128);
    let interest_accumulated = (interest_accumulated as u64);

    // Calculate reserves
    let reserves_added =
        (interest_accumulated as u128) * (market.reserve_factor as u128) / (BPS_PRECISION as u128);
    let reserves_added = (reserves_added as u64);

    // Update state
    market.total_borrows = market.total_borrows + interest_accumulated;
    
    // Note: In a real implementation, we would split the reserves from the repayments
    // For now, we just track the amount that *should* be in reserves
    // Since total_reserves is a Balance<T>, we can't just add u64 to it without actual tokens
    // Ideally, when repay() happens, we split the interest payment into reserves and suppliers
    
    market.borrow_index =
        market.borrow_index + ((market.borrow_index as u128) * interest_factor / (PRECISION as u128) as u64);
    market.accrual_block_timestamp = current_time;

    // Emit event
    event::emit(AccrueInterestEvent<T> {
        market_id: object::uid_to_address(&market.id),
        borrow_rate,
        supply_rate: get_supply_rate(market),
        total_borrows: market.total_borrows,
        total_reserves: reserves_added, // Show added amount
        borrow_index: market.borrow_index,
        timestamp: current_time,
    });
}

/// Calculate current borrow rate
/// Uses Jump Rate Model (similar to Compound)
fun get_borrow_rate<T>(market: &Market<T>): u64 {
    let utilization = get_utilization_rate(market);

    if (utilization <= market.kink) {
        // Below kink: rate = base + utilization * multiplier
        let rate =
            market.base_rate_per_second +
                      ((utilization as u128) * (market.multiplier_per_second as u128) / (BPS_PRECISION as u128) as u64);
        rate
    } else {
        // Above kink: rate = base + kink * multiplier + (utilization - kink) * jump_multiplier
        let normal_rate =
            market.base_rate_per_second +
                             ((market.kink as u128) * (market.multiplier_per_second as u128) / (BPS_PRECISION as u128) as u64);
        let excess_util = utilization - market.kink;
        normal_rate + ((excess_util as u128) * (market.jump_multiplier_per_second as u128) / (BPS_PRECISION as u128) as u64)
    }
}

/// Calculate supply rate (what suppliers earn)
fun get_supply_rate<T>(market: &Market<T>): u64 {
    let borrow_rate = get_borrow_rate(market);
    let utilization = get_utilization_rate(market);
    let one_minus_reserve_factor = BPS_PRECISION - market.reserve_factor;

    // supply_rate = borrow_rate * utilization * (1 - reserve_factor)
    let rate = (borrow_rate as u128) * (utilization as u128) / (BPS_PRECISION as u128);
    let rate = (rate as u128) * (one_minus_reserve_factor as u128) / (BPS_PRECISION as u128);
    (rate as u64)
}

/// Calculate utilization rate
fun get_utilization_rate<T>(market: &Market<T>): u64 {
    if (market.total_borrows == 0) {
        return 0
    };

    let total_cash = balance::value(&market.total_cash);
    let total_supply = total_cash + market.total_borrows;

    // utilization = borrows / (cash + borrows)
    ((market.total_borrows as u128) * (BPS_PRECISION as u128) / (total_supply as u128) as u64)
}

// ============================================================================
// View & Helper Functions
// ============================================================================

/// Get current exchange rate: underlying per cToken
public fun get_exchange_rate<T>(market: &Market<T>): u64 {
    if (market.total_supply == 0) {
        return INITIAL_EXCHANGE_RATE
    };

    let total_cash = balance::value(&market.total_cash);
    let total_value = total_cash + market.total_borrows - balance::value(&market.total_reserves);

    // exchange_rate = (cash + borrows - reserves) / total_supply
    ((total_value as u128) * (PRECISION as u128) / (market.total_supply as u128) as u64)
}

/// Get price from DEX oracle (VULNERABLE to manipulation)
public fun get_oracle_price<C, D>(oracle: &Pool<C, D>): u64 {
    let (reserve_c, reserve_d) = simple_dex::get_reserves(oracle);

    // price = reserve_d / reserve_c (how much debt per unit of collateral)
    ((reserve_d as u128) * (PRECISION as u128) / (reserve_c as u128) as u64)
}

/// Calculate health factor
/// health_factor = (collateral * liquidation_threshold) / debt
/// health_factor < 1.0 (10000) means liquidatable
public fun calculate_health_factor(
    collateral_value: u64,
    debt: u64,
    liquidation_threshold: u64,
): u64 {
    if (debt == 0) {
        return BPS_PRECISION * 10 // Very healthy
    };

    let adjusted_collateral =
        (collateral_value as u128) * (liquidation_threshold as u128) / (BPS_PRECISION as u128);
    ((adjusted_collateral as u128) * (BPS_PRECISION as u128) / (debt as u128) as u64)
}

/// Calculate accrued interest on borrow
fun calculate_accrued_interest(principal: u64, old_index: u64, new_index: u64): u64 {
    if (old_index == 0 || new_index == old_index) {
        return 0
    };

    let interest_factor =
        ((new_index - old_index) as u128) * (PRECISION as u128) / (old_index as u128);
    ((principal as u128) * interest_factor / (PRECISION as u128) as u64)
}

// ============================================================================
// Getters for Testing
// ============================================================================

public fun get_total_borrows<T>(market: &Market<T>): u64 {
    market.total_borrows
}

public fun get_total_cash<T>(market: &Market<T>): u64 {
    balance::value(&market.total_cash)
}

public fun get_position_collateral<T>(position: &Position<T>): u64 {
    position.c_token_balance
}

public fun get_position_debt<T>(position: &Position<T>): u64 {
    position.borrow_balance
}
