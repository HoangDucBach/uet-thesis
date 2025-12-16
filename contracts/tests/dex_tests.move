// Copyright (c) 2024 DeFi Protocol
// SPDX-License-Identifier: Apache-2.0

/// Comprehensive tests for DEX functionality including pool creation,
/// liquidity management, and token swapping
#[test_only]
module simulation::dex_tests {
    use simulation::simple_dex::{Self, Pool};
    use simulation::coin_factory::{Self, CoinFactory};
    use simulation::usdc::USDC;
    use simulation::usdt::USDT;
    use sui::test_scenario::{Self as test};
    use sui::coin::{Self, TreasuryCap};

    // Test addresses
    const ADMIN: address = @0xAD;
    const ALICE: address = @0xA11CE;
    const BOB: address = @0xB0B;

    // Test amounts (with 6 decimals)
    const INITIAL_LIQUIDITY: u64 = 1_000_000_000; // 1000 tokens
    const SWAP_AMOUNT: u64 = 100_000_000;         // 100 tokens

    /// Initialize coin factory for tests
    fun setup_coins(scenario: &mut test::Scenario) {
        test::next_tx(scenario, ADMIN);
        {
            coin_factory::init_for_testing(test::ctx(scenario));
        };

        test::next_tx(scenario, ADMIN);
        {
            let usdc_cap = test::take_from_sender<TreasuryCap<USDC>>(scenario);
            let usdt_cap = test::take_from_sender<TreasuryCap<USDT>>(scenario);
            let weth_cap = test::take_from_sender<TreasuryCap<simulation::weth::WETH>>(scenario);
            let btc_cap = test::take_from_sender<TreasuryCap<simulation::btc::BTC>>(scenario);
            let sui_cap = test::take_from_sender<TreasuryCap<simulation::sui_coin::SUI_COIN>>(scenario);

            coin_factory::create_factory(
                usdc_cap,
                usdt_cap,
                weth_cap,
                btc_cap,
                sui_cap,
                test::ctx(scenario)
            );
        };
    }

    #[test]
    /// Test: Create a liquidity pool with initial reserves
    fun test_create_pool() {
        let mut scenario = test::begin(ADMIN);
        setup_coins(&mut scenario);

        test::next_tx(&mut scenario, ALICE);
        {
            let mut factory = test::take_shared<CoinFactory>(&scenario);

            // Mint tokens for pool creation
            let usdc = coin_factory::mint_usdc(&mut factory, INITIAL_LIQUIDITY, test::ctx(&mut scenario));
            let usdt = coin_factory::mint_usdt(&mut factory, INITIAL_LIQUIDITY, test::ctx(&mut scenario));

            // Create pool
            simple_dex::create_pool(usdc, usdt, test::ctx(&mut scenario));

            test::return_shared(factory);
        };

        test::next_tx(&mut scenario, ALICE);
        {
            // Verify pool was created and is shared
            let pool = test::take_shared<Pool<USDC, USDT>>(&scenario);
            let (reserve_a, reserve_b) = simple_dex::get_reserves(&pool);
            let lp_supply = simple_dex::get_lp_supply(&pool);

            assert!(reserve_a == INITIAL_LIQUIDITY, 0);
            assert!(reserve_b == INITIAL_LIQUIDITY, 1);
            // Verify minimum liquidity burn (1000)
            assert!(lp_supply == INITIAL_LIQUIDITY - 1000, 2);

            test::return_shared(pool);
        };

        test::end(scenario);
    }

    #[test]
    /// Test: Swap TokenA for TokenB and verify output
    fun test_swap_a_to_b() {
        let mut scenario = test::begin(ADMIN);
        setup_coins(&mut scenario);

        // Create pool
        test::next_tx(&mut scenario, ALICE);
        {
            let mut factory = test::take_shared<CoinFactory>(&scenario);
            let usdc = coin_factory::mint_usdc(&mut factory, INITIAL_LIQUIDITY, test::ctx(&mut scenario));
            let usdt = coin_factory::mint_usdt(&mut factory, INITIAL_LIQUIDITY, test::ctx(&mut scenario));
            simple_dex::create_pool(usdc, usdt, test::ctx(&mut scenario));
            test::return_shared(factory);
        };

        // Perform swap
        test::next_tx(&mut scenario, BOB);
        {
            let mut factory = test::take_shared<CoinFactory>(&scenario);
            let mut pool = test::take_shared<Pool<USDC, USDT>>(&scenario);

            // Mint USDC for swap
            let usdc_in = coin_factory::mint_usdc(&mut factory, SWAP_AMOUNT, test::ctx(&mut scenario));

            // Calculate expected output (approximate)
            let expected_out = simple_dex::calculate_amount_out(&pool, SWAP_AMOUNT, true);

            // Execute swap
            let usdt_out = simple_dex::swap_a_to_b(
                &mut pool,
                usdc_in,
                0, // min_out = 0 for test
                test::ctx(&mut scenario)
            );

            // Verify output amount
            assert!(coin::value(&usdt_out) == expected_out, 0);
            assert!(coin::value(&usdt_out) > 0, 1);

            // Burn received tokens
            coin_factory::burn_usdt(&mut factory, usdt_out);

            test::return_shared(pool);
            test::return_shared(factory);
        };

        test::end(scenario);
    }

    #[test]
    /// Test: Swap TokenB for TokenA and verify output
    fun test_swap_b_to_a() {
        let mut scenario = test::begin(ADMIN);
        setup_coins(&mut scenario);

        // Create pool
        test::next_tx(&mut scenario, ALICE);
        {
            let mut factory = test::take_shared<CoinFactory>(&scenario);
            let usdc = coin_factory::mint_usdc(&mut factory, INITIAL_LIQUIDITY, test::ctx(&mut scenario));
            let usdt = coin_factory::mint_usdt(&mut factory, INITIAL_LIQUIDITY, test::ctx(&mut scenario));
            simple_dex::create_pool(usdc, usdt, test::ctx(&mut scenario));
            test::return_shared(factory);
        };

        // Perform swap
        test::next_tx(&mut scenario, BOB);
        {
            let mut factory = test::take_shared<CoinFactory>(&scenario);
            let mut pool = test::take_shared<Pool<USDC, USDT>>(&scenario);

            let usdt_in = coin_factory::mint_usdt(&mut factory, SWAP_AMOUNT, test::ctx(&mut scenario));
            let expected_out = simple_dex::calculate_amount_out(&pool, SWAP_AMOUNT, false);

            let usdc_out = simple_dex::swap_b_to_a(
                &mut pool,
                usdt_in,
                0,
                test::ctx(&mut scenario)
            );

            assert!(coin::value(&usdc_out) == expected_out, 0);

            coin_factory::burn_usdc(&mut factory, usdc_out);
            test::return_shared(pool);
            test::return_shared(factory);
        };

        test::end(scenario);
    }

    #[test]
    /// Test: Add liquidity to existing pool
    fun test_add_liquidity() {
        let mut scenario = test::begin(ADMIN);
        setup_coins(&mut scenario);

        // Create initial pool
        test::next_tx(&mut scenario, ALICE);
        {
            let mut factory = test::take_shared<CoinFactory>(&scenario);
            let usdc = coin_factory::mint_usdc(&mut factory, INITIAL_LIQUIDITY, test::ctx(&mut scenario));
            let usdt = coin_factory::mint_usdt(&mut factory, INITIAL_LIQUIDITY, test::ctx(&mut scenario));
            simple_dex::create_pool(usdc, usdt, test::ctx(&mut scenario));
            test::return_shared(factory);
        };

        // Add liquidity
        test::next_tx(&mut scenario, BOB);
        {
            let mut factory = test::take_shared<CoinFactory>(&scenario);
            let mut pool = test::take_shared<Pool<USDC, USDT>>(&scenario);

            let (reserve_a_before, reserve_b_before) = simple_dex::get_reserves(&pool);
            let lp_supply_before = simple_dex::get_lp_supply(&pool);

            // Add 10% more liquidity
            let add_amount = INITIAL_LIQUIDITY / 10;
            let usdc = coin_factory::mint_usdc(&mut factory, add_amount, test::ctx(&mut scenario));
            let usdt = coin_factory::mint_usdt(&mut factory, add_amount, test::ctx(&mut scenario));

            simple_dex::add_liquidity(
                &mut pool,
                usdc,
                usdt,
                0, // min_liquidity
                test::ctx(&mut scenario)
            );

            let (reserve_a_after, reserve_b_after) = simple_dex::get_reserves(&pool);
            let lp_supply_after = simple_dex::get_lp_supply(&pool);

            // Verify reserves increased
            assert!(reserve_a_after > reserve_a_before, 0);
            assert!(reserve_b_after > reserve_b_before, 1);
            assert!(lp_supply_after > lp_supply_before, 2);

            test::return_shared(pool);
            test::return_shared(factory);
        };

        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = simple_dex::E_SLIPPAGE_TOO_HIGH)]
    /// Test: Swap fails when slippage too high
    fun test_swap_slippage_protection() {
        let mut scenario = test::begin(ADMIN);
        setup_coins(&mut scenario);

        test::next_tx(&mut scenario, ALICE);
        {
            let mut factory = test::take_shared<CoinFactory>(&scenario);
            let usdc = coin_factory::mint_usdc(&mut factory, INITIAL_LIQUIDITY, test::ctx(&mut scenario));
            let usdt = coin_factory::mint_usdt(&mut factory, INITIAL_LIQUIDITY, test::ctx(&mut scenario));
            simple_dex::create_pool(usdc, usdt, test::ctx(&mut scenario));
            test::return_shared(factory);
        };

        test::next_tx(&mut scenario, BOB);
        {
            let mut factory = test::take_shared<CoinFactory>(&scenario);
            let mut pool = test::take_shared<Pool<USDC, USDT>>(&scenario);

            let usdc_in = coin_factory::mint_usdc(&mut factory, SWAP_AMOUNT, test::ctx(&mut scenario));

            // Set min_out higher than possible output (will fail)
            let impossible_min_out = SWAP_AMOUNT * 2;

            let usdt_out = simple_dex::swap_a_to_b(
                &mut pool,
                usdc_in,
                impossible_min_out, // This will trigger E_SLIPPAGE_TOO_HIGH
                test::ctx(&mut scenario)
            );

            coin_factory::burn_usdt(&mut factory, usdt_out);
            test::return_shared(pool);
            test::return_shared(factory);
        };

        test::end(scenario);
    }

    #[test]
    /// Test: Multiple swaps change pool reserves correctly
    fun test_multiple_swaps() {
        let mut scenario = test::begin(ADMIN);
        setup_coins(&mut scenario);

        test::next_tx(&mut scenario, ALICE);
        {
            let mut factory = test::take_shared<CoinFactory>(&scenario);
            let usdc = coin_factory::mint_usdc(&mut factory, INITIAL_LIQUIDITY, test::ctx(&mut scenario));
            let usdt = coin_factory::mint_usdt(&mut factory, INITIAL_LIQUIDITY, test::ctx(&mut scenario));
            simple_dex::create_pool(usdc, usdt, test::ctx(&mut scenario));
            test::return_shared(factory);
        };

        // Execute 3 swaps
        let mut i = 0;
        while (i < 3) {
            test::next_tx(&mut scenario, BOB);
            {
                let mut factory = test::take_shared<CoinFactory>(&scenario);
                let mut pool = test::take_shared<Pool<USDC, USDT>>(&scenario);

                let usdc_in = coin_factory::mint_usdc(&mut factory, SWAP_AMOUNT, test::ctx(&mut scenario));
                let usdt_out = simple_dex::swap_a_to_b(&mut pool, usdc_in, 0, test::ctx(&mut scenario));

                coin_factory::burn_usdt(&mut factory, usdt_out);
                test::return_shared(pool);
                test::return_shared(factory);
            };
            i = i + 1;
        };

        test::next_tx(&mut scenario, BOB);
        {
            let pool = test::take_shared<Pool<USDC, USDT>>(&scenario);
            let (reserve_a, reserve_b) = simple_dex::get_reserves(&pool);

            // After 3 swaps of USDC → USDT:
            // - Reserve A (USDC) should be higher
            // - Reserve B (USDT) should be lower
            assert!(reserve_a > INITIAL_LIQUIDITY, 0);
            assert!(reserve_b < INITIAL_LIQUIDITY, 1);

            test::return_shared(pool);
        };

        test::end(scenario);
    }

    #[test]
    /// Test: Remove liquidity from the pool
    fun test_remove_liquidity() {
        let mut scenario = test::begin(ADMIN);
        setup_coins(&mut scenario);

        // Create pool
        test::next_tx(&mut scenario, ALICE);
        {
            let mut factory = test::take_shared<CoinFactory>(&scenario);
            let usdc = coin_factory::mint_usdc(&mut factory, INITIAL_LIQUIDITY, test::ctx(&mut scenario));
            let usdt = coin_factory::mint_usdt(&mut factory, INITIAL_LIQUIDITY, test::ctx(&mut scenario));
            simple_dex::create_pool(usdc, usdt, test::ctx(&mut scenario));
            test::return_shared(factory);
        };

        // Remove liquidity
        test::next_tx(&mut scenario, ALICE);
        {
            let mut pool = test::take_shared<Pool<USDC, USDT>>(&scenario);
            let lp_supply = simple_dex::get_lp_supply(&pool);
            
            // Remove 50% of remaining liquidity
            let remove_amount = lp_supply / 2;
            
            let (usdc_out, usdt_out) = simple_dex::remove_liquidity(
                &mut pool,
                remove_amount,
                0, // min_a
                0, // min_b
                test::ctx(&mut scenario)
            );

            // Verify amounts
            assert!(coin::value(&usdc_out) > 0, 0);
            assert!(coin::value(&usdt_out) > 0, 1);
            
            // Verify pool state updated
            let new_lp_supply = simple_dex::get_lp_supply(&pool);
            assert!(new_lp_supply == lp_supply - remove_amount, 2);

            coin::burn_for_testing(usdc_out);
            coin::burn_for_testing(usdt_out);
            test::return_shared(pool);
        };

        test::end(scenario);
    }
}
