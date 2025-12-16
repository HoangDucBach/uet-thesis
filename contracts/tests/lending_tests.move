// Copyright (c) 2024 DeFi Protocol
// SPDX-License-Identifier: Apache-2.0

#[test_only]
module simulation::lending_tests;

use simulation::coin_factory::{Self, CoinFactory};
use simulation::compound_market::{Self, Market, Position};
use simulation::simple_dex::{Self, Pool};
use simulation::flash_loan_pool;
use simulation::usdc::USDC;
use simulation::weth::WETH;
use simulation::usdt::USDT;
use simulation::btc::BTC;
use simulation::sui_coin::SUI_COIN;
use sui::clock::{Self, Clock};
use sui::coin::{Self, Coin, TreasuryCap};
use sui::test_scenario::{Self as test, Scenario, next_tx, ctx};

// Test addresses
const ADMIN: address = @0xAD;
const ALICE: address = @0xA11CE;
const BOB: address = @0xB0B;
const LIQUIDATOR: address = @0x11D;

// ============================================================================
// Test Helpers
// ============================================================================

fun setup_coins(scenario: &mut Scenario) {
    next_tx(scenario, ADMIN);
    {
        coin_factory::init_for_testing(ctx(scenario));
    };

    next_tx(scenario, ADMIN);
    {
        let usdc_cap = test::take_from_sender<TreasuryCap<USDC>>(scenario);
        let usdt_cap = test::take_from_sender<TreasuryCap<USDT>>(scenario);
        let weth_cap = test::take_from_sender<TreasuryCap<WETH>>(scenario);
        let btc_cap = test::take_from_sender<TreasuryCap<BTC>>(scenario);
        let sui_cap = test::take_from_sender<TreasuryCap<SUI_COIN>>(scenario);

        coin_factory::create_factory(
            usdc_cap,
            usdt_cap,
            weth_cap,
            btc_cap,
            sui_cap,
            ctx(scenario)
        );
    };
}

fun setup_markets(scenario: &mut Scenario): (address, address) {
    // Setup USDC market
    next_tx(scenario, ADMIN);
    {
        let mut factory = test::take_shared<CoinFactory>(scenario);
        let clock = test::take_shared<Clock>(scenario);

        // Mint initial liquidity for USDC market
        let initial_liquidity = coin_factory::mint_usdc(&mut factory, 1000, ctx(scenario));

        let mut usdc_market = compound_market::create_market<USDC>(
            initial_liquidity,
            @0x1, // Dummy oracle address, will use actual pool
            7500, // 75% collateral factor
            1000, // 10% reserve factor
            &clock,
            ctx(scenario),
        );

        // Supply the rest of liquidity to mint cTokens and establish exchange rate
        let large_liquidity = coin_factory::mint_usdc(&mut factory, 10_000_000_000_000, ctx(scenario));
        let position = compound_market::supply(&mut usdc_market, large_liquidity, &clock, ctx(scenario));
        transfer::public_transfer(position, ADMIN);

        transfer::public_share_object(usdc_market);

        test::return_shared(factory);
        test::return_shared(clock);
    };

    // Setup WETH market
    next_tx(scenario, ADMIN);
    {
        let mut factory = test::take_shared<CoinFactory>(scenario);
        let clock = test::take_shared<Clock>(scenario);

        let initial_liquidity = coin_factory::mint_weth(&mut factory, 1000, ctx(scenario));

        let mut weth_market = compound_market::create_market<WETH>(
            initial_liquidity,
            @0x2,
            7500,
            1000,
            &clock,
            ctx(scenario),
        );

        // Supply the rest of liquidity
        let large_liquidity = coin_factory::mint_weth(&mut factory, 100_000_000_000, ctx(scenario));
        let position = compound_market::supply(&mut weth_market, large_liquidity, &clock, ctx(scenario));
        transfer::public_transfer(position, ADMIN);

        transfer::public_share_object(weth_market);

        test::return_shared(factory);
        test::return_shared(clock);
    };

    // Create DEX pool for oracle
    next_tx(scenario, ADMIN);
    {
        let mut factory = test::take_shared<CoinFactory>(scenario);

        let weth = coin_factory::mint_weth(&mut factory, 100_000_000, ctx(scenario));
        let usdc = coin_factory::mint_usdc(&mut factory, 200_000_000_000, ctx(scenario));

        // Price: 1 WETH = 2000 USDC
        simple_dex::create_pool(weth, usdc, ctx(scenario));

        test::return_shared(factory);
    };

    // Create Flash Loan Pool
    next_tx(scenario, ADMIN);
    {
        let mut factory = test::take_shared<CoinFactory>(scenario);
        let initial_funds = coin_factory::mint_usdc(&mut factory, 100_000_000_000_000, ctx(scenario));
        flash_loan_pool::create_pool(initial_funds, 9, ctx(scenario));
        test::return_shared(factory);
    };

    (@0x1, @0x2)
}

// ============================================================================
// Supply & Withdraw Tests
// ============================================================================

#[test]
fun test_supply_and_withdraw() {
    let mut scenario_val = test::begin(ADMIN);
    let scenario = &mut scenario_val;

    // Initialize
    setup_coins(scenario);

    next_tx(scenario, ADMIN);
    {
        let clock = clock::create_for_testing(ctx(scenario));
        clock::share_for_testing(clock);
    };

    setup_markets(scenario);

    // Alice supplies USDC
    next_tx(scenario, ALICE);
    {
        let mut factory = test::take_shared<CoinFactory>(scenario);
        let mut market = test::take_shared<Market<USDC>>(scenario);
        let clock = test::take_shared<Clock>(scenario);

        let supply_amount = coin_factory::mint_usdc(&mut factory, 10_000_000_000, ctx(scenario));

        let position = compound_market::supply(&mut market, supply_amount, &clock, ctx(scenario));

        // Verify position received cTokens
        assert!(compound_market::get_position_collateral(&position) > 0, 0);

        transfer::public_transfer(position, ALICE);

        test::return_shared(factory);
        test::return_shared(market);
        test::return_shared(clock);
    };

    // Alice withdraws some USDC
    next_tx(scenario, ALICE);
    {
        let mut market = test::take_shared<Market<USDC>>(scenario);
        let clock = test::take_shared<Clock>(scenario);
        let mut position = test::take_from_sender<Position<USDC>>(scenario);

        let c_tokens = compound_market::get_position_collateral(&position);
        let withdraw_c_tokens = c_tokens / 2;

        let withdrawn = compound_market::withdraw(
            &mut market,
            &mut position,
            withdraw_c_tokens,
            &clock,
            ctx(scenario),
        );

        assert!(coin::value(&withdrawn) > 0, 1);

        coin::burn_for_testing(withdrawn);
        test::return_to_sender(scenario, position);
        test::return_shared(market);
        test::return_shared(clock);
    };

    test::end(scenario_val);
}

// ============================================================================
// Borrow & Repay Tests
// ============================================================================

#[test]
fun test_borrow_and_repay() {
    let mut scenario_val = test::begin(ADMIN);
    let scenario = &mut scenario_val;

    setup_coins(scenario);

    next_tx(scenario, ADMIN);
    {
        let clock = clock::create_for_testing(ctx(scenario));
        clock::share_for_testing(clock);
    };

    setup_markets(scenario);

    // Alice supplies WETH as collateral
    next_tx(scenario, ALICE);
    {
        let mut factory = test::take_shared<CoinFactory>(scenario);
        let mut market = test::take_shared<Market<WETH>>(scenario);
        let clock = test::take_shared<Clock>(scenario);

        let weth = coin_factory::mint_weth(&mut factory, 1_000_000, ctx(scenario));
        let position = compound_market::supply(&mut market, weth, &clock, ctx(scenario));

        transfer::public_transfer(position, ALICE);

        test::return_shared(factory);
        test::return_shared(market);
        test::return_shared(clock);
    };

    // Alice borrows USDC against WETH
    next_tx(scenario, ALICE);
    {
        let mut weth_market = test::take_shared<Market<WETH>>(scenario);
        let mut usdc_market = test::take_shared<Market<USDC>>(scenario);
        let pool = test::take_shared<Pool<WETH, USDC>>(scenario);
        let clock = test::take_shared<Clock>(scenario);
        let mut position = test::take_from_sender<Position<WETH>>(scenario);

        let borrow_amount = 1_000_000_000; // 1000 USDC

        let borrowed = compound_market::borrow(
            &mut weth_market,
            &mut usdc_market,
            &mut position,
            &pool,
            borrow_amount,
            &clock,
            ctx(scenario),
        );

        assert!(coin::value(&borrowed) == borrow_amount, 2);
        assert!(compound_market::get_position_debt(&position) == borrow_amount, 3);

        // Store borrowed USDC
        transfer::public_transfer(borrowed, ALICE);
        test::return_to_sender(scenario, position);
        test::return_shared(weth_market);
        test::return_shared(usdc_market);
        test::return_shared(pool);
        test::return_shared(clock);
    };

    // Alice repays debt
    next_tx(scenario, ALICE);
    {
        let mut usdc_market = test::take_shared<Market<USDC>>(scenario);
        let clock = test::take_shared<Clock>(scenario);
        let mut position = test::take_from_sender<Position<WETH>>(scenario);
        let repayment = test::take_from_sender<Coin<USDC>>(scenario);

        compound_market::repay(&mut usdc_market, &mut position, repayment, &clock, ctx(scenario));

        // Debt should be zero
        assert!(compound_market::get_position_debt(&position) == 0, 4);

        test::return_to_sender(scenario, position);
        test::return_shared(usdc_market);
        test::return_shared(clock);
    };

    test::end(scenario_val);
}

// ============================================================================
// Oracle Manipulation Attack Test
// ============================================================================

#[test]
fun test_oracle_manipulation_attack() {
    let mut scenario_val = test::begin(ADMIN);
    let scenario = &mut scenario_val;

    setup_coins(scenario);

    next_tx(scenario, ADMIN);
    {
        let clock = clock::create_for_testing(ctx(scenario));
        clock::share_for_testing(clock);
    };

    setup_markets(scenario);

    // Bob performs flash loan attack
    next_tx(scenario, BOB);
    {
        let mut factory = test::take_shared<CoinFactory>(scenario);
        let mut weth_market = test::take_shared<Market<WETH>>(scenario);
        let mut usdc_market = test::take_shared<Market<USDC>>(scenario);
        let mut pool = test::take_shared<Pool<WETH, USDC>>(scenario);
        let mut flash_pool = test::take_shared<flash_loan_pool::FlashLoanPool<USDC>>(scenario);
        let clock = test::take_shared<Clock>(scenario);

        // Step 1: Borrow flash loan (10M USDC)
        let (mut flash_loan_coins, flash_loan_receipt) = flash_loan_pool::borrow_flash_loan(
            &mut flash_pool,
            10_000_000_000_000,
            ctx(scenario),
        );

        // Step 2: Manipulate price - swap 5M USDC to WETH (push WETH price up)
        let manipulation_amount = coin::split(
            &mut flash_loan_coins,
            5_000_000_000_000,
            ctx(scenario),
        );
        let weth_from_swap = simple_dex::swap_b_to_a(
            &mut pool,
            manipulation_amount,
            0,
            ctx(scenario),
        );

        // Step 3: Supply manipulated WETH as collateral
        let mut position = compound_market::supply(
            &mut weth_market,
            weth_from_swap,
            &clock,
            ctx(scenario),
        );

        // Step 4: Borrow max USDC (using inflated WETH price)
        let borrowed_usdc = compound_market::borrow(
            &mut weth_market,
            &mut usdc_market,
            &mut position,
            &pool, // Oracle shows inflated price!
            3_000_000_000_000, // Borrow 3M USDC (more than should be allowed)
            &clock,
            ctx(scenario),
        );

        // Step 5: Add borrowed to flash loan repayment
        coin::join(&mut flash_loan_coins, borrowed_usdc);

        // Mint extra USDC to cover the shortfall (shortfall due to swap slippage and fees)
        let extra_usdc = coin_factory::mint_usdc(&mut factory, 3_000_000_000_000, ctx(scenario));
        coin::join(&mut flash_loan_coins, extra_usdc);

        // Step 6: Repay flash loan
        flash_loan_pool::repay_flash_loan(
            &mut flash_pool,
            flash_loan_coins,
            flash_loan_receipt,
            ctx(scenario),
        );

        // Bob keeps position with inflated collateral value
        // Lending protocol now has bad debt risk
        transfer::public_transfer(position, BOB);

        test::return_shared(factory);
        test::return_shared(weth_market);
        test::return_shared(usdc_market);
        test::return_shared(pool);
        test::return_shared(flash_pool);
        test::return_shared(clock);
    };

    test::end(scenario_val);
}

// ============================================================================
// Liquidation Tests
// ============================================================================

#[test]
fun test_liquidation() {
    let mut scenario_val = test::begin(ADMIN);
    let scenario = &mut scenario_val;

    setup_coins(scenario);

    next_tx(scenario, ADMIN);
    {
        let clock = clock::create_for_testing(ctx(scenario));
        clock::share_for_testing(clock);
    };

    setup_markets(scenario);

    // Alice creates position
    next_tx(scenario, ALICE);
    {
        let mut factory = test::take_shared<CoinFactory>(scenario);
        let mut weth_market = test::take_shared<Market<WETH>>(scenario);
        let mut usdc_market = test::take_shared<Market<USDC>>(scenario);
        let pool = test::take_shared<Pool<WETH, USDC>>(scenario);
        let clock = test::take_shared<Clock>(scenario);

        // Supply 1 WETH
        let weth = coin_factory::mint_weth(&mut factory, 1_000_000, ctx(scenario));
        let mut position = compound_market::supply(&mut weth_market, weth, &clock, ctx(scenario));

        // Borrow 1200 USDC (close to max)
        let borrowed = compound_market::borrow(
            &mut weth_market,
            &mut usdc_market,
            &mut position,
            &pool,
            1_200_000_000,
            &clock,
            ctx(scenario),
        );

        coin::burn_for_testing(borrowed);
        transfer::public_transfer(position, ALICE);

        test::return_shared(factory);
        test::return_shared(weth_market);
        test::return_shared(usdc_market);
        test::return_shared(pool);
        test::return_shared(clock);
    };

    // Price drops, making position liquidatable
    next_tx(scenario, ADMIN);
    {
        let mut factory = test::take_shared<CoinFactory>(scenario);
        let mut pool = test::take_shared<Pool<WETH, USDC>>(scenario);

        // Swap to drop WETH price
        let weth_to_dump = coin_factory::mint_weth(&mut factory, 1_000_000_000, ctx(scenario));
        let usdc_out = simple_dex::swap_a_to_b(&mut pool, weth_to_dump, 0, ctx(scenario));

        coin::burn_for_testing(usdc_out);
        test::return_shared(factory);
        test::return_shared(pool);
    };

    // Liquidator liquidates Alice's position
    next_tx(scenario, LIQUIDATOR);
    {
        let mut factory = test::take_shared<CoinFactory>(scenario);
        let mut weth_market = test::take_shared<Market<WETH>>(scenario);
        let mut usdc_market = test::take_shared<Market<USDC>>(scenario);
        let pool = test::take_shared<Pool<WETH, USDC>>(scenario);
        let clock = test::take_shared<Clock>(scenario);

        // Get Alice's position
        test::next_tx(scenario, ALICE);
        let mut position = test::take_from_sender<Position<WETH>>(scenario);

        // Liquidator repays debt
        test::next_tx(scenario, LIQUIDATOR);
        let repayment = coin_factory::mint_usdc(&mut factory, 600_000_000, ctx(scenario));

        let seized_collateral = compound_market::liquidate(
            &mut weth_market,
            &mut usdc_market,
            &mut position,
            &pool,
            repayment,
            &clock,
            ctx(scenario),
        );

        // Liquidator gets collateral with 5% bonus
        assert!(coin::value(&seized_collateral) > 0, 5);

        coin::burn_for_testing(seized_collateral);
        test::return_to_address(ALICE, position);
        test::return_shared(factory);
        test::return_shared(weth_market);
        test::return_shared(usdc_market);
        test::return_shared(pool);
        test::return_shared(clock);
    };

    test::end(scenario_val);
}
