// Copyright (c) 2024 DeFi Protocol
// SPDX-License-Identifier: Apache-2.0

/// Comprehensive tests for flash loan functionality
#[test_only]
module simulation::flash_loan_tests;

use simulation::coin_factory::{Self, CoinFactory};
use simulation::flash_loan_pool::{Self, FlashLoanPool};
use simulation::usdc::USDC;
use sui::coin::{Self, TreasuryCap};
use sui::test_scenario as test;

const ADMIN: address = @0xAD;
const ALICE: address = @0xA11CE;
const BOB: address = @0xB0B;

const POOL_LIQUIDITY: u64 = 10_000_000_000; // 10,000 USDC
const FLASH_LOAN_AMOUNT: u64 = 1_000_000_000; // 1,000 USDC
const FEE_RATE: u64 = 9; // 0.09% (9 basis points)

fun setup_coins(scenario: &mut test::Scenario) {
    test::next_tx(scenario, ADMIN);
    {
        coin_factory::init_for_testing(test::ctx(scenario));
    };

    test::next_tx(scenario, ADMIN);
    {
        let usdc_cap = test::take_from_sender<TreasuryCap<USDC>>(scenario);
        let usdt_cap = test::take_from_sender<TreasuryCap<simulation::usdt::USDT>>(scenario);
        let weth_cap = test::take_from_sender<TreasuryCap<simulation::weth::WETH>>(scenario);
        let btc_cap = test::take_from_sender<TreasuryCap<simulation::btc::BTC>>(scenario);
        let sui_cap = test::take_from_sender<TreasuryCap<simulation::sui_coin::SUI_COIN>>(scenario);

        coin_factory::create_factory(
            usdc_cap,
            usdt_cap,
            weth_cap,
            btc_cap,
            sui_cap,
            test::ctx(scenario),
        );
    };
}

#[test]
/// Test: Create flash loan pool with initial liquidity
fun test_create_flash_loan_pool() {
    let mut scenario = test::begin(ADMIN);
    setup_coins(&mut scenario);

    test::next_tx(&mut scenario, ALICE);
    {
        let mut factory = test::take_shared<CoinFactory>(&scenario);
        let initial_funds = coin_factory::mint_usdc(
            &mut factory,
            POOL_LIQUIDITY,
            test::ctx(&mut scenario),
        );

        flash_loan_pool::create_pool(initial_funds, FEE_RATE, test::ctx(&mut scenario));

        test::return_shared(factory);
    };

    test::next_tx(&mut scenario, ALICE);
    {
        let pool = test::take_shared<FlashLoanPool<USDC>>(&scenario);
        let liquidity = flash_loan_pool::get_available_liquidity(&pool);

        assert!(liquidity == POOL_LIQUIDITY, 0);
        assert!(flash_loan_pool::get_fee_rate(&pool) == FEE_RATE, 1);

        test::return_shared(pool);
    };

    test::end(scenario);
}

#[test]
/// Test: Borrow and repay flash loan successfully
fun test_flash_loan_borrow_and_repay() {
    let mut scenario = test::begin(ADMIN);
    setup_coins(&mut scenario);

    // Create pool
    test::next_tx(&mut scenario, ALICE);
    {
        let mut factory = test::take_shared<CoinFactory>(&scenario);
        let initial_funds = coin_factory::mint_usdc(
            &mut factory,
            POOL_LIQUIDITY,
            test::ctx(&mut scenario),
        );
        flash_loan_pool::create_pool(initial_funds, FEE_RATE, test::ctx(&mut scenario));
        test::return_shared(factory);
    };

    // Borrow and repay in same transaction
    test::next_tx(&mut scenario, BOB);
    {
        let mut factory = test::take_shared<CoinFactory>(&scenario);
        let mut pool = test::take_shared<FlashLoanPool<USDC>>(&scenario);

        let liquidity_before = flash_loan_pool::get_available_liquidity(&pool);

        // Borrow flash loan
        let (mut borrowed, receipt) = flash_loan_pool::borrow_flash_loan(
            &mut pool,
            FLASH_LOAN_AMOUNT,
            test::ctx(&mut scenario),
        );

        assert!(coin::value(&borrowed) == FLASH_LOAN_AMOUNT, 0);

        let liquidity_during = flash_loan_pool::get_available_liquidity(&pool);
        assert!(liquidity_during == liquidity_before - FLASH_LOAN_AMOUNT, 1);

        // Calculate fee
        let fee = (FLASH_LOAN_AMOUNT * FEE_RATE) / 10000;

        // Mint additional coins for fee
        let fee_coins = coin_factory::mint_usdc(&mut factory, fee, test::ctx(&mut scenario));

        // Merge borrowed + fee
        coin::join(&mut borrowed, fee_coins);

        // Repay flash loan
        flash_loan_pool::repay_flash_loan(&mut pool, borrowed, receipt, test::ctx(&mut scenario));

        let liquidity_after = flash_loan_pool::get_available_liquidity(&pool);
        assert!(liquidity_after == liquidity_before + fee, 2);

        test::return_shared(pool);
        test::return_shared(factory);
    };

    test::end(scenario);
}

#[test]
#[expected_failure(abort_code = flash_loan_pool::E_INSUFFICIENT_BALANCE)]
/// Test: Cannot borrow more than pool liquidity
fun test_flash_loan_exceeds_liquidity() {
    let mut scenario = test::begin(ADMIN);
    setup_coins(&mut scenario);

    test::next_tx(&mut scenario, ALICE);
    {
        let mut factory = test::take_shared<CoinFactory>(&scenario);
        let initial_funds = coin_factory::mint_usdc(
            &mut factory,
            POOL_LIQUIDITY,
            test::ctx(&mut scenario),
        );
        flash_loan_pool::create_pool(initial_funds, FEE_RATE, test::ctx(&mut scenario));
        test::return_shared(factory);
    };

    test::next_tx(&mut scenario, BOB);
    {
        let mut pool = test::take_shared<FlashLoanPool<USDC>>(&scenario);

        // Try to borrow more than available
        let (borrowed, receipt) = flash_loan_pool::borrow_flash_loan(
            &mut pool,
            POOL_LIQUIDITY + 1, // This will fail
            test::ctx(&mut scenario),
        );

        // Clean up (won't reach here)
        flash_loan_pool::repay_flash_loan(&mut pool, borrowed, receipt, test::ctx(&mut scenario));

        test::return_shared(pool);
    };

    test::end(scenario);
}

#[test]
#[expected_failure(abort_code = flash_loan_pool::E_LOAN_NOT_REPAID)]
/// Test: Cannot repay with insufficient amount
fun test_flash_loan_insufficient_repayment() {
    let mut scenario = test::begin(ADMIN);
    setup_coins(&mut scenario);

    test::next_tx(&mut scenario, ALICE);
    {
        let mut factory = test::take_shared<CoinFactory>(&scenario);
        let initial_funds = coin_factory::mint_usdc(
            &mut factory,
            POOL_LIQUIDITY,
            test::ctx(&mut scenario),
        );
        flash_loan_pool::create_pool(initial_funds, FEE_RATE, test::ctx(&mut scenario));
        test::return_shared(factory);
    };

    test::next_tx(&mut scenario, BOB);
    {
        let mut pool = test::take_shared<FlashLoanPool<USDC>>(&scenario);

        let (borrowed, receipt) = flash_loan_pool::borrow_flash_loan(
            &mut pool,
            FLASH_LOAN_AMOUNT,
            test::ctx(&mut scenario),
        );

        // Try to repay without fee (will fail)
        flash_loan_pool::repay_flash_loan(&mut pool, borrowed, receipt, test::ctx(&mut scenario));

        test::return_shared(pool);
    };

    test::end(scenario);
}

#[test]
/// Test: Add liquidity to existing flash loan pool
fun test_add_liquidity_to_pool() {
    let mut scenario = test::begin(ADMIN);
    setup_coins(&mut scenario);

    test::next_tx(&mut scenario, ALICE);
    {
        let mut factory = test::take_shared<CoinFactory>(&scenario);
        let initial_funds = coin_factory::mint_usdc(
            &mut factory,
            POOL_LIQUIDITY,
            test::ctx(&mut scenario),
        );
        flash_loan_pool::create_pool(initial_funds, FEE_RATE, test::ctx(&mut scenario));
        test::return_shared(factory);
    };

    test::next_tx(&mut scenario, BOB);
    {
        let mut factory = test::take_shared<CoinFactory>(&scenario);
        let mut pool = test::take_shared<FlashLoanPool<USDC>>(&scenario);

        let liquidity_before = flash_loan_pool::get_available_liquidity(&pool);

        // Add more liquidity
        let additional = coin_factory::mint_usdc(
            &mut factory,
            POOL_LIQUIDITY,
            test::ctx(&mut scenario),
        );
        flash_loan_pool::add_liquidity(&mut pool, additional);

        let liquidity_after = flash_loan_pool::get_available_liquidity(&pool);
        assert!(liquidity_after == liquidity_before + POOL_LIQUIDITY, 0);

        test::return_shared(pool);
        test::return_shared(factory);
    };

    test::end(scenario);
}

#[test]
/// Test: Multiple sequential flash loans
fun test_multiple_flash_loans() {
    let mut scenario = test::begin(ADMIN);
    setup_coins(&mut scenario);

    test::next_tx(&mut scenario, ALICE);
    {
        let mut factory = test::take_shared<CoinFactory>(&scenario);
        let initial_funds = coin_factory::mint_usdc(
            &mut factory,
            POOL_LIQUIDITY,
            test::ctx(&mut scenario),
        );
        flash_loan_pool::create_pool(initial_funds, FEE_RATE, test::ctx(&mut scenario));
        test::return_shared(factory);
    };

    // Execute 3 flash loans sequentially
    let mut i = 0;
    while (i < 3) {
        test::next_tx(&mut scenario, BOB);
        {
            let mut factory = test::take_shared<CoinFactory>(&scenario);
            let mut pool = test::take_shared<FlashLoanPool<USDC>>(&scenario);

            let (mut borrowed, receipt) = flash_loan_pool::borrow_flash_loan(
                &mut pool,
                FLASH_LOAN_AMOUNT,
                test::ctx(&mut scenario),
            );

            let fee = (FLASH_LOAN_AMOUNT * FEE_RATE) / 10000;
            let fee_coins = coin_factory::mint_usdc(&mut factory, fee, test::ctx(&mut scenario));
            coin::join(&mut borrowed, fee_coins);

            flash_loan_pool::repay_flash_loan(
                &mut pool,
                borrowed,
                receipt,
                test::ctx(&mut scenario),
            );

            test::return_shared(pool);
            test::return_shared(factory);
        };
        i = i + 1;
    };

    // Verify pool accumulated fees
    test::next_tx(&mut scenario, BOB);
    {
        let pool = test::take_shared<FlashLoanPool<USDC>>(&scenario);
        let liquidity = flash_loan_pool::get_available_liquidity(&pool);

        let expected_fees = ((FLASH_LOAN_AMOUNT * FEE_RATE) / 10000) * 3;
        assert!(liquidity == POOL_LIQUIDITY + expected_fees, 0);

        test::return_shared(pool);
    };

    test::end(scenario);
}

#[test]
/// Test: Flash loan pool statistics tracking
fun test_pool_statistics() {
    let mut scenario = test::begin(ADMIN);
    setup_coins(&mut scenario);

    test::next_tx(&mut scenario, ALICE);
    {
        let mut factory = test::take_shared<CoinFactory>(&scenario);
        let initial_funds = coin_factory::mint_usdc(
            &mut factory,
            POOL_LIQUIDITY,
            test::ctx(&mut scenario),
        );
        flash_loan_pool::create_pool(initial_funds, FEE_RATE, test::ctx(&mut scenario));
        test::return_shared(factory);
    };

    // Execute 2 flash loans
    let mut i = 0;
    while (i < 2) {
        test::next_tx(&mut scenario, BOB);
        {
            let mut factory = test::take_shared<CoinFactory>(&scenario);
            let mut pool = test::take_shared<FlashLoanPool<USDC>>(&scenario);

            let (mut borrowed, receipt) = flash_loan_pool::borrow_flash_loan(
                &mut pool,
                FLASH_LOAN_AMOUNT,
                test::ctx(&mut scenario),
            );

            let fee = (FLASH_LOAN_AMOUNT * FEE_RATE) / 10000;
            let fee_coins = coin_factory::mint_usdc(&mut factory, fee, test::ctx(&mut scenario));
            coin::join(&mut borrowed, fee_coins);

            flash_loan_pool::repay_flash_loan(
                &mut pool,
                borrowed,
                receipt,
                test::ctx(&mut scenario),
            );

            test::return_shared(pool);
            test::return_shared(factory);
        };
        i = i + 1;
    };

    test::next_tx(&mut scenario, BOB);
    {
        let pool = test::take_shared<FlashLoanPool<USDC>>(&scenario);
        let (_balance, total_borrowed, loan_count, fee_rate) = flash_loan_pool::get_stats(&pool);

        assert!(loan_count == 2, 0);
        assert!(total_borrowed == FLASH_LOAN_AMOUNT * 2, 1);
        assert!(fee_rate == FEE_RATE, 2);

        test::return_shared(pool);
    };

    test::end(scenario);
}
