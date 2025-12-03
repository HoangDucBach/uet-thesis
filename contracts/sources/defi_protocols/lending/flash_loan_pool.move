// sources/defi_protocols/lending/flash_loan_pool.move
module simulation::flash_loan_pool;

use sui::balance::{Self, Balance};
use sui::coin::{Self, Coin};
use sui::event;

// ============================================================================
// Constants & Errors
// ============================================================================

const E_INSUFFICIENT_BALANCE: u64 = 1;
const E_LOAN_NOT_REPAID: u64 = 2;
const E_INVALID_AMOUNT: u64 = 3;
const E_WRONG_POOL: u64 = 4;

// ============================================================================
// Structs
// ============================================================================

/// Flash loan pool
public struct FlashLoanPool<phantom T> has key {
    id: UID,
    balance: Balance<T>,
    fee_rate: u64, // Basis points (9 = 0.09% typical flash loan fee)
    total_borrowed: u64,
    loan_count: u64,
}

/// Flash loan receipt (must be returned)
public struct FlashLoan<phantom T> {
    pool_id: address,
    amount: u64,
    fee: u64,
}

/// Flash loan taken event
public struct FlashLoanTaken<phantom T> has copy, drop {
    pool_id: address,
    borrower: address,
    amount: u64,
    fee: u64,
}

/// Flash loan repaid event
public struct FlashLoanRepaid<phantom T> has copy, drop {
    pool_id: address,
    borrower: address,
    amount: u64,
    fee: u64,
}

// ============================================================================
// Public Functions
// ============================================================================

/// Create flash loan pool
public fun create_pool<T>(initial_funds: Coin<T>, fee_rate: u64, ctx: &mut TxContext) {
    let pool = FlashLoanPool<T> {
        id: object::new(ctx),
        balance: coin::into_balance(initial_funds),
        fee_rate,
        total_borrowed: 0,
        loan_count: 0,
    };

    transfer::share_object(pool);
}

/// Borrow flash loan
public fun borrow_flash_loan<T>(
    pool: &mut FlashLoanPool<T>,
    amount: u64,
    ctx: &mut TxContext,
): (Coin<T>, FlashLoan<T>) {
    assert!(amount > 0, E_INVALID_AMOUNT);
    assert!(balance::value(&pool.balance) >= amount, E_INSUFFICIENT_BALANCE);

    let fee = (amount * pool.fee_rate) / 10000;
    let borrowed_balance = balance::split(&mut pool.balance, amount);
    let borrowed_coin = coin::from_balance(borrowed_balance, ctx);

    let loan = FlashLoan<T> {
        pool_id: object::uid_to_address(&pool.id),
        amount,
        fee,
    };

    pool.total_borrowed = pool.total_borrowed + amount;
    pool.loan_count = pool.loan_count + 1;

    event::emit(FlashLoanTaken<T> {
        pool_id: object::uid_to_address(&pool.id),
        borrower: tx_context::sender(ctx),
        amount,
        fee,
    });

    (borrowed_coin, loan)
}

/// Repay flash loan (must be called in same transaction)
public fun repay_flash_loan<T>(
    pool: &mut FlashLoanPool<T>,
    repayment: Coin<T>,
    loan: FlashLoan<T>,
    ctx: &TxContext,
) {
    let FlashLoan { pool_id, amount, fee } = loan;

    assert!(pool_id == object::uid_to_address(&pool.id), E_WRONG_POOL);
    assert!(coin::value(&repayment) >= amount + fee, E_LOAN_NOT_REPAID);

    // Put repayment back into pool
    balance::join(&mut pool.balance, coin::into_balance(repayment));

    event::emit(FlashLoanRepaid<T> {
        pool_id: object::uid_to_address(&pool.id),
        borrower: tx_context::sender(ctx),
        amount,
        fee,
    });
}

// ============================================================================
// Getters
// ============================================================================

/// Get available liquidity
public fun get_available_liquidity<T>(pool: &FlashLoanPool<T>): u64 {
    balance::value(&pool.balance)
}

/// Get pool stats
public fun get_stats<T>(pool: &FlashLoanPool<T>): (u64, u64, u64, u64) {
    (balance::value(&pool.balance), pool.total_borrowed, pool.loan_count, pool.fee_rate)
}

/// Get pool fee rate
public fun get_fee_rate<T>(pool: &FlashLoanPool<T>): u64 {
    pool.fee_rate
}

/// Add liquidity to pool
public fun add_liquidity<T>(pool: &mut FlashLoanPool<T>, liquidity: Coin<T>) {
    balance::join(&mut pool.balance, coin::into_balance(liquidity));
}
