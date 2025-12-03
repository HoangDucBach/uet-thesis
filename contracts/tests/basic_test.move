// tests/basic_test.move
#[test_only]
module simulation::basic_test;

use simulation::btc::BTC;
use simulation::coin_factory::{Self, CoinFactory};
use simulation::flash_loan_pool::{Self, FlashLoanPool};
use simulation::price_oracle::{Self, PriceOracle};
use simulation::simple_dex::{Self, Pool};
use simulation::sui_coin::SUI_COIN;
use simulation::usdc::USDC;
use simulation::usdt::USDT;
use simulation::weth::WETH;
use sui::clock;
use sui::coin::{Self, TreasuryCap};
use sui::test_scenario as ts;

const ADMIN: address = @0xAD;
const ALICE: address = @0xA11CE;

/// Helper function to initialize coin factory in tests
fun setup_coin_factory(scenario: &mut ts::Scenario) {
    // Initialize coin modules
    coin_factory::init_for_testing(ts::ctx(scenario));

    ts::next_tx(scenario, ADMIN);

    // Create factory with treasury caps
    let usdc_treasury = ts::take_from_sender<TreasuryCap<USDC>>(scenario);
    let usdt_treasury = ts::take_from_sender<TreasuryCap<USDT>>(scenario);
    let weth_treasury = ts::take_from_sender<TreasuryCap<WETH>>(scenario);
    let btc_treasury = ts::take_from_sender<TreasuryCap<BTC>>(scenario);
    let sui_treasury = ts::take_from_sender<TreasuryCap<SUI_COIN>>(scenario);

    coin_factory::create_factory(
        usdc_treasury,
        usdt_treasury,
        weth_treasury,
        btc_treasury,
        sui_treasury,
        ts::ctx(scenario),
    );

    ts::next_tx(scenario, ADMIN);
}

#[test]
fun test_coin_factory_creation() {
    let mut scenario = ts::begin(ADMIN);

    setup_coin_factory(&mut scenario);

    // Mint some coins
    {
        let mut factory = ts::take_shared<CoinFactory>(&scenario);

        let usdc = coin_factory::mint_usdc(&mut factory, 1000000, ts::ctx(&mut scenario));
        let usdt = coin_factory::mint_usdt(&mut factory, 1000000, ts::ctx(&mut scenario));

        assert!(coin::value(&usdc) == 1000000, 0);
        assert!(coin::value(&usdt) == 1000000, 1);

        // Burn the coins
        coin_factory::burn_usdc(&mut factory, usdc);
        coin_factory::burn_usdt(&mut factory, usdt);

        ts::return_shared(factory);
    };

    ts::end(scenario);
}

#[test]
fun test_dex_pool_creation() {
    let mut scenario = ts::begin(ADMIN);

    setup_coin_factory(&mut scenario);

    // Create DEX pool
    {
        let mut factory = ts::take_shared<CoinFactory>(&scenario);

        let usdc = coin_factory::mint_usdc(&mut factory, 1000000, ts::ctx(&mut scenario));
        let usdt = coin_factory::mint_usdt(&mut factory, 1000000, ts::ctx(&mut scenario));

        simple_dex::create_pool(usdc, usdt, ts::ctx(&mut scenario));

        ts::return_shared(factory);
    };

    ts::next_tx(&mut scenario, ADMIN);

    // Check pool exists and has correct reserves
    {
        let pool = ts::take_shared<Pool<USDC, USDT>>(&scenario);

        let (reserve_a, reserve_b) = simple_dex::get_reserves(&pool);
        assert!(reserve_a == 1000000, 2);
        assert!(reserve_b == 1000000, 3);

        ts::return_shared(pool);
    };

    ts::end(scenario);
}

#[test]
fun test_simple_swap() {
    let mut scenario = ts::begin(ADMIN);

    setup_coin_factory(&mut scenario);

    // Create pool
    {
        let mut factory = ts::take_shared<CoinFactory>(&scenario);

        let usdc = coin_factory::mint_usdc(&mut factory, 1000000, ts::ctx(&mut scenario));
        let usdt = coin_factory::mint_usdt(&mut factory, 1000000, ts::ctx(&mut scenario));

        simple_dex::create_pool(usdc, usdt, ts::ctx(&mut scenario));

        ts::return_shared(factory);
    };

    ts::next_tx(&mut scenario, ALICE);

    // Execute swap
    {
        let mut pool = ts::take_shared<Pool<USDC, USDT>>(&scenario);
        let mut factory = ts::take_shared<CoinFactory>(&scenario);

        let usdc = coin_factory::mint_usdc(&mut factory, 10000, ts::ctx(&mut scenario));
        let usdt_out = simple_dex::swap_a_to_b(&mut pool, usdc, 0, ts::ctx(&mut scenario));

        assert!(coin::value(&usdt_out) > 0, 4);

        sui::transfer::public_transfer(usdt_out, ALICE);

        ts::return_shared(pool);
        ts::return_shared(factory);
    };

    ts::end(scenario);
}

#[test]
fun test_flash_loan_pool() {
    let mut scenario = ts::begin(ADMIN);

    setup_coin_factory(&mut scenario);

    // Create flash loan pool
    {
        let mut factory = ts::take_shared<CoinFactory>(&scenario);

        let usdc = coin_factory::mint_usdc(&mut factory, 10000000, ts::ctx(&mut scenario));
        flash_loan_pool::create_pool(usdc, 9, ts::ctx(&mut scenario)); // 0.09% fee

        ts::return_shared(factory);
    };

    ts::next_tx(&mut scenario, ALICE);

    // Test borrow and repay
    {
        let mut pool = ts::take_shared<FlashLoanPool<USDC>>(&scenario);
        let mut factory = ts::take_shared<CoinFactory>(&scenario);

        let (borrowed, receipt) = flash_loan_pool::borrow_flash_loan(
            &mut pool,
            100000,
            ts::ctx(&mut scenario),
        );

        assert!(coin::value(&borrowed) == 100000, 5);

        // Mint coins to repay (borrowed + fee)
        let repay_amount = 100000 + ((100000 * 9) / 10000);
        let mut repayment = coin_factory::mint_usdc(
            &mut factory,
            repay_amount,
            ts::ctx(&mut scenario),
        );

        // Join borrowed coins back
        coin::join(&mut repayment, borrowed);

        flash_loan_pool::repay_flash_loan(&mut pool, repayment, receipt, ts::ctx(&mut scenario));

        ts::return_shared(pool);
        ts::return_shared(factory);
    };

    ts::end(scenario);
}

#[test]
fun test_price_oracle() {
    let mut scenario = ts::begin(ADMIN);

    // Initialize
    {
        price_oracle::init_for_testing(ts::ctx(&mut scenario));
    };

    ts::next_tx(&mut scenario, ADMIN);

    // Create clock
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, 1000000);

    // Update price
    {
        let mut oracle = ts::take_shared<PriceOracle>(&scenario);

        price_oracle::update_price<USDC>(
            &mut oracle,
            100000000, // $1.00 with 8 decimals
            1000000,
            &clock,
            ts::ctx(&mut scenario),
        );

        let (price, confidence) = price_oracle::get_price<USDC>(&oracle, &clock);
        assert!(price == 100000000, 6);
        assert!(confidence == 1000000, 7);

        ts::return_shared(oracle);
    };

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
fun test_add_liquidity() {
    let mut scenario = ts::begin(ADMIN);

    setup_coin_factory(&mut scenario);

    // Create initial pool
    {
        let mut factory = ts::take_shared<CoinFactory>(&scenario);

        let usdc = coin_factory::mint_usdc(&mut factory, 1000000, ts::ctx(&mut scenario));
        let usdt = coin_factory::mint_usdt(&mut factory, 1000000, ts::ctx(&mut scenario));

        simple_dex::create_pool(usdc, usdt, ts::ctx(&mut scenario));

        ts::return_shared(factory);
    };

    ts::next_tx(&mut scenario, ALICE);

    // Add liquidity to existing pool
    {
        let mut pool = ts::take_shared<Pool<USDC, USDT>>(&scenario);
        let mut factory = ts::take_shared<CoinFactory>(&scenario);

        let (reserve_a_before, reserve_b_before) = simple_dex::get_reserves(&pool);
        let lp_supply_before = simple_dex::get_lp_supply(&pool);

        // Add 500k USDC and 500k USDT
        let usdc = coin_factory::mint_usdc(&mut factory, 500000, ts::ctx(&mut scenario));
        let usdt = coin_factory::mint_usdt(&mut factory, 500000, ts::ctx(&mut scenario));

        simple_dex::add_liquidity(&mut pool, usdc, usdt, 0, ts::ctx(&mut scenario));

        let (reserve_a_after, reserve_b_after) = simple_dex::get_reserves(&pool);
        let lp_supply_after = simple_dex::get_lp_supply(&pool);

        // Verify reserves increased
        assert!(reserve_a_after > reserve_a_before, 8);
        assert!(reserve_b_after > reserve_b_before, 9);
        assert!(lp_supply_after > lp_supply_before, 10);

        ts::return_shared(pool);
        ts::return_shared(factory);
    };

    ts::end(scenario);
}

#[test]
fun test_swap_both_directions() {
    let mut scenario = ts::begin(ADMIN);

    setup_coin_factory(&mut scenario);

    // Create pool
    {
        let mut factory = ts::take_shared<CoinFactory>(&scenario);

        let usdc = coin_factory::mint_usdc(&mut factory, 1000000, ts::ctx(&mut scenario));
        let usdt = coin_factory::mint_usdt(&mut factory, 1000000, ts::ctx(&mut scenario));

        simple_dex::create_pool(usdc, usdt, ts::ctx(&mut scenario));

        ts::return_shared(factory);
    };

    ts::next_tx(&mut scenario, ALICE);

    // Test swap A → B (USDC → USDT)
    {
        let mut pool = ts::take_shared<Pool<USDC, USDT>>(&scenario);
        let mut factory = ts::take_shared<CoinFactory>(&scenario);

        let usdc = coin_factory::mint_usdc(&mut factory, 10000, ts::ctx(&mut scenario));
        let usdt_out = simple_dex::swap_a_to_b(&mut pool, usdc, 0, ts::ctx(&mut scenario));

        assert!(coin::value(&usdt_out) > 0, 11);

        // Clean up
        coin_factory::burn_usdt(&mut factory, usdt_out);

        ts::return_shared(pool);
        ts::return_shared(factory);
    };

    ts::next_tx(&mut scenario, ALICE);

    // Test swap B → A (USDT → USDC)
    {
        let mut pool = ts::take_shared<Pool<USDC, USDT>>(&scenario);
        let mut factory = ts::take_shared<CoinFactory>(&scenario);

        let usdt = coin_factory::mint_usdt(&mut factory, 10000, ts::ctx(&mut scenario));
        let usdc_out = simple_dex::swap_b_to_a(&mut pool, usdt, 0, ts::ctx(&mut scenario));

        assert!(coin::value(&usdc_out) > 0, 12);

        // Clean up
        coin_factory::burn_usdc(&mut factory, usdc_out);

        ts::return_shared(pool);
        ts::return_shared(factory);
    };

    ts::end(scenario);
}

#[test]
fun test_slippage_protection() {
    let mut scenario = ts::begin(ADMIN);

    setup_coin_factory(&mut scenario);

    // Create pool
    {
        let mut factory = ts::take_shared<CoinFactory>(&scenario);

        let usdc = coin_factory::mint_usdc(&mut factory, 1000000, ts::ctx(&mut scenario));
        let usdt = coin_factory::mint_usdt(&mut factory, 1000000, ts::ctx(&mut scenario));

        simple_dex::create_pool(usdc, usdt, ts::ctx(&mut scenario));

        ts::return_shared(factory);
    };

    ts::next_tx(&mut scenario, ALICE);

    // Test with reasonable min_out (should pass)
    {
        let mut pool = ts::take_shared<Pool<USDC, USDT>>(&scenario);
        let mut factory = ts::take_shared<CoinFactory>(&scenario);

        let usdc = coin_factory::mint_usdc(&mut factory, 10000, ts::ctx(&mut scenario));

        // Calculate expected output
        let expected_out = simple_dex::calculate_amount_out(&pool, 10000, true);
        let min_out = expected_out * 95 / 100; // Accept 5% slippage

        let usdt_out = simple_dex::swap_a_to_b(&mut pool, usdc, min_out, ts::ctx(&mut scenario));

        assert!(coin::value(&usdt_out) >= min_out, 13);

        coin_factory::burn_usdt(&mut factory, usdt_out);

        ts::return_shared(pool);
        ts::return_shared(factory);
    };

    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = simple_dex::E_SLIPPAGE_TOO_HIGH)]
fun test_slippage_protection_failure() {
    let mut scenario = ts::begin(ADMIN);

    setup_coin_factory(&mut scenario);

    // Create pool
    {
        let mut factory = ts::take_shared<CoinFactory>(&scenario);

        let usdc = coin_factory::mint_usdc(&mut factory, 1000000, ts::ctx(&mut scenario));
        let usdt = coin_factory::mint_usdt(&mut factory, 1000000, ts::ctx(&mut scenario));

        simple_dex::create_pool(usdc, usdt, ts::ctx(&mut scenario));

        ts::return_shared(factory);
    };

    ts::next_tx(&mut scenario, ALICE);

    // Test with unrealistic min_out (should fail)
    {
        let mut pool = ts::take_shared<Pool<USDC, USDT>>(&scenario);
        let mut factory = ts::take_shared<CoinFactory>(&scenario);

        let usdc = coin_factory::mint_usdc(&mut factory, 10000, ts::ctx(&mut scenario));

        // Demand more than possible
        let min_out = 15000; // Unrealistic expectation

        let usdt_out = simple_dex::swap_a_to_b(&mut pool, usdc, min_out, ts::ctx(&mut scenario));

        coin_factory::burn_usdt(&mut factory, usdt_out);

        ts::return_shared(pool);
        ts::return_shared(factory);
    };

    ts::end(scenario);
}
