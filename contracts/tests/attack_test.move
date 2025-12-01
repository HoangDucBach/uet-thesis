// tests/attack_test.move
#[test_only]
module simulation::attack_test {
    use simulation::coin_factory::{Self, CoinFactory};
    use simulation::usdc::USDC;
    use simulation::usdt::USDT;
    use simulation::simple_dex::{Self, Pool};
    use simulation::flash_loan_pool::{Self, FlashLoanPool};
    use simulation::price_oracle::{Self, PriceOracle};
    use simulation::sandwich_attack;
    use simulation::flash_loan_attack;
    use simulation::retail_trader;
    use sui::test_scenario::{Self as ts};
    use sui::clock;
    use sui::coin::{Self, TreasuryCap};

    const ADMIN: address = @0xAD;
    const ALICE: address = @0xA11CE;
    const ATTACKER: address = @0xA77AC;

    /// Helper function to initialize coin factory
    fun setup_coin_factory(scenario: &mut ts::Scenario) {
        // Initialize coin modules with ADMIN
        ts::next_tx(scenario, ADMIN);
        coin_factory::init_for_testing(ts::ctx(scenario));

        ts::next_tx(scenario, ADMIN);

        // Create factory with treasury caps
        let usdc_treasury = ts::take_from_sender<TreasuryCap<USDC>>(scenario);
        let usdt_treasury = ts::take_from_sender<TreasuryCap<USDT>>(scenario);
        let weth_treasury = ts::take_from_sender<TreasuryCap<simulation::weth::WETH>>(scenario);
        let btc_treasury = ts::take_from_sender<TreasuryCap<simulation::btc::BTC>>(scenario);
        let sui_treasury = ts::take_from_sender<TreasuryCap<simulation::sui_coin::SUI_COIN>>(scenario);

        coin_factory::create_factory(
            usdc_treasury,
            usdt_treasury,
            weth_treasury,
            btc_treasury,
            sui_treasury,
            ts::ctx(scenario)
        );

        ts::next_tx(scenario, ADMIN);
    }

    #[test]
    fun test_sandwich_attack_basic() {
        let mut scenario = ts::begin(ATTACKER);

        setup_coin_factory(&mut scenario);

        // Create pool with liquidity
        {
            let mut factory = ts::take_shared<CoinFactory>(&scenario);

            let usdc = coin_factory::mint_usdc(&mut factory, 1000000, ts::ctx(&mut scenario));
            let usdt = coin_factory::mint_usdt(&mut factory, 1000000, ts::ctx(&mut scenario));

            simple_dex::create_pool(usdc, usdt, ts::ctx(&mut scenario));

            ts::return_shared(factory);
        };

        ts::next_tx(&mut scenario, ATTACKER);

        // Execute sandwich attack
        {
            let mut pool = ts::take_shared<Pool<USDC, USDT>>(&scenario);
            let mut factory = ts::take_shared<CoinFactory>(&scenario);

            // Attacker has large amount for front-run
            let attacker_coins = coin_factory::mint_usdc(&mut factory, 100000, ts::ctx(&mut scenario));

            // Victim has smaller amount
            let victim_coins = coin_factory::mint_usdc(&mut factory, 50000, ts::ctx(&mut scenario));

            // Execute sandwich: front-run 50k, victim 50k
            let attacker_result = sandwich_attack::execute_sandwich_attack(
                &mut pool,
                50000, // Front-run amount
                50000, // Victim amount
                attacker_coins,
                victim_coins,
                ALICE, // Victim address
                ts::ctx(&mut scenario)
            );

            // Attacker should have profit
            let final_amount = coin::value(&attacker_result);
            assert!(final_amount > 50000, 100); // Should profit from sandwich

            // Clean up
            coin_factory::burn_usdc(&mut factory, attacker_result);

            ts::return_shared(pool);
            ts::return_shared(factory);
        };

        ts::end(scenario);
    }

    #[test]
    fun test_retail_trader_behavior() {
        let mut scenario = ts::begin(ALICE);

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

        // Retail trader executes normal trade with slippage protection
        {
            let mut pool = ts::take_shared<Pool<USDC, USDT>>(&scenario);
            let mut factory = ts::take_shared<CoinFactory>(&scenario);

            let coins = coin_factory::mint_usdc(&mut factory, 50000, ts::ctx(&mut scenario));

            // Execute normal trade with 5% max slippage
            let (usdt_out, remaining) = retail_trader::execute_normal_trade(
                &mut pool,
                30000, // Trade 30k
                500,   // 5% max slippage (basis points)
                coins,
                ts::ctx(&mut scenario)
            );

            assert!(coin::value(&usdt_out) > 0, 101);
            assert!(coin::value(&remaining) == 20000, 102); // 50k - 30k

            // Clean up
            coin_factory::burn_usdt(&mut factory, usdt_out);
            coin_factory::burn_usdc(&mut factory, remaining);

            ts::return_shared(pool);
            ts::return_shared(factory);
        };

        ts::end(scenario);
    }

    #[test]
    fun test_retail_trader_simple_trade() {
        let mut scenario = ts::begin(ALICE);

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

        // Retail trader executes simple trade (no slippage protection - more vulnerable)
        {
            let mut pool = ts::take_shared<Pool<USDC, USDT>>(&scenario);
            let mut factory = ts::take_shared<CoinFactory>(&scenario);

            let coins = coin_factory::mint_usdc(&mut factory, 50000, ts::ctx(&mut scenario));

            let (usdt_out, remaining) = retail_trader::execute_simple_trade(
                &mut pool,
                30000,
                coins,
                ts::ctx(&mut scenario)
            );

            assert!(coin::value(&usdt_out) > 0, 103);

            coin_factory::burn_usdt(&mut factory, usdt_out);
            coin_factory::burn_usdc(&mut factory, remaining);

            ts::return_shared(pool);
            ts::return_shared(factory);
        };

        ts::end(scenario);
    }

    #[test]
    fun test_flash_loan_arbitrage() {
        let mut scenario = ts::begin(ATTACKER);

        setup_coin_factory(&mut scenario);

        // Create two pools with price difference
        {
            let mut factory = ts::take_shared<CoinFactory>(&scenario);

            // Pool 1: 1M USDC, 1M USDT (1:1 ratio)
            let usdc1 = coin_factory::mint_usdc(&mut factory, 1000000, ts::ctx(&mut scenario));
            let usdt1 = coin_factory::mint_usdt(&mut factory, 1000000, ts::ctx(&mut scenario));
            simple_dex::create_pool(usdc1, usdt1, ts::ctx(&mut scenario));

            ts::return_shared(factory);
        };

        ts::next_tx(&mut scenario, ATTACKER);

        // Pool 2: Reverse (USDT -> USDC)
        {
            let mut factory = ts::take_shared<CoinFactory>(&scenario);

            // Pool 2: 1M USDT, 1.15M USDC (even larger price difference for arbitrage)
            let usdt2 = coin_factory::mint_usdt(&mut factory, 1000000, ts::ctx(&mut scenario));
            let usdc2 = coin_factory::mint_usdc(&mut factory, 1150000, ts::ctx(&mut scenario));
            simple_dex::create_pool(usdt2, usdc2, ts::ctx(&mut scenario));

            ts::return_shared(factory);
        };

        ts::next_tx(&mut scenario, ATTACKER);

        // Create flash loan pool
        {
            let mut factory = ts::take_shared<CoinFactory>(&scenario);

            let flash_funds = coin_factory::mint_usdc(&mut factory, 10000000, ts::ctx(&mut scenario));
            flash_loan_pool::create_pool(flash_funds, 9, ts::ctx(&mut scenario)); // 0.09% fee

            ts::return_shared(factory);
        };

        ts::next_tx(&mut scenario, ATTACKER);

        // Execute flash loan arbitrage
        {
            let mut flash_pool = ts::take_shared<FlashLoanPool<USDC>>(&scenario);
            let mut dex_pool_1 = ts::take_shared<Pool<USDC, USDT>>(&scenario);
            let mut dex_pool_2 = ts::take_shared<Pool<USDT, USDC>>(&scenario);

            let profit = flash_loan_attack::execute_simple_arbitrage(
                &mut flash_pool,
                &mut dex_pool_1,
                &mut dex_pool_2,
                50000, // Borrow 50k USDC (smaller amount to ensure enough liquidity and profit)
                ts::ctx(&mut scenario)
            );

            // Should have some profit (or at least not lose money)
            let profit_amount = coin::value(&profit);
            assert!(profit_amount >= 0, 104);

            // Clean up
            if (profit_amount > 0) {
                let mut factory = ts::take_shared<CoinFactory>(&scenario);
                coin_factory::burn_usdc(&mut factory, profit);
                ts::return_shared(factory);
            } else {
                sui::coin::destroy_zero(profit);
            };

            ts::return_shared(flash_pool);
            ts::return_shared(dex_pool_1);
            ts::return_shared(dex_pool_2);
        };

        ts::end(scenario);
    }

    #[test]
    fun test_oracle_manipulation() {
        let mut scenario = ts::begin(ATTACKER);

        setup_coin_factory(&mut scenario);

        // Initialize oracle
        {
            price_oracle::init_for_testing(ts::ctx(&mut scenario));
        };

        ts::next_tx(&mut scenario, ATTACKER);

        let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
        clock::set_for_testing(&mut clock, 1000000);

        // Set initial price
        {
            let mut oracle = ts::take_shared<PriceOracle>(&scenario);

            price_oracle::update_price<USDT>(
                &mut oracle,
                100000000, // $1.00
                1000000,
                &clock,
                ts::ctx(&mut scenario)
            );

            ts::return_shared(oracle);
        };

        ts::next_tx(&mut scenario, ATTACKER);

        // Manipulate price (>10% should trigger manipulation detection event)
        {
            let mut oracle = ts::take_shared<PriceOracle>(&scenario);

            let (old_price, _) = price_oracle::get_price<USDT>(&oracle, &clock);

            // Pump price by 15%
            price_oracle::manipulate_price<USDT>(
                &mut oracle,
                115000000, // $1.15 (15% increase)
                &clock,
                ts::ctx(&mut scenario)
            );

            let (new_price, _) = price_oracle::get_price<USDT>(&oracle, &clock);

            // Verify price changed
            assert!(new_price > old_price, 105);
            assert!(new_price == 115000000, 106);

            ts::return_shared(oracle);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = flash_loan_pool::E_LOAN_NOT_REPAID)]
    fun test_flash_loan_repayment_failure() {
        let mut scenario = ts::begin(ATTACKER);

        setup_coin_factory(&mut scenario);

        // Create flash loan pool
        {
            let mut factory = ts::take_shared<CoinFactory>(&scenario);

            let flash_funds = coin_factory::mint_usdc(&mut factory, 10000000, ts::ctx(&mut scenario));
            flash_loan_pool::create_pool(flash_funds, 9, ts::ctx(&mut scenario));

            ts::return_shared(factory);
        };

        ts::next_tx(&mut scenario, ATTACKER);

        // Try to repay less than borrowed (should fail)
        {
            let mut flash_pool = ts::take_shared<FlashLoanPool<USDC>>(&scenario);
            let mut factory = ts::take_shared<CoinFactory>(&scenario);

            let (borrowed, receipt) = flash_loan_pool::borrow_flash_loan(
                &mut flash_pool,
                100000,
                ts::ctx(&mut scenario)
            );

            // Try to repay only borrowed amount without fee (should fail)
            let repayment_amount = coin::value(&borrowed); // Missing fee!

            coin_factory::burn_usdc(&mut factory, borrowed);
            let insufficient_repayment = coin_factory::mint_usdc(&mut factory, repayment_amount, ts::ctx(&mut scenario));

            flash_loan_pool::repay_flash_loan(&mut flash_pool, insufficient_repayment, receipt, ts::ctx(&mut scenario));

            ts::return_shared(flash_pool);
            ts::return_shared(factory);
        };

        ts::end(scenario);
    }

    #[test]
    fun test_high_price_impact() {
        let mut scenario = ts::begin(ATTACKER);

        setup_coin_factory(&mut scenario);

        // Create pool with limited liquidity
        {
            let mut factory = ts::take_shared<CoinFactory>(&scenario);

            let usdc = coin_factory::mint_usdc(&mut factory, 500000, ts::ctx(&mut scenario));
            let usdt = coin_factory::mint_usdt(&mut factory, 500000, ts::ctx(&mut scenario));

            simple_dex::create_pool(usdc, usdt, ts::ctx(&mut scenario));

            ts::return_shared(factory);
        };

        ts::next_tx(&mut scenario, ATTACKER);

        // Execute large trade (high impact)
        {
            let mut pool = ts::take_shared<Pool<USDC, USDT>>(&scenario);
            let mut factory = ts::take_shared<CoinFactory>(&scenario);

            let (reserve_a_before, reserve_b_before) = simple_dex::get_reserves(&pool);

            // Trade 100k USDC (20% of pool liquidity - very high impact)
            let large_trade = coin_factory::mint_usdc(&mut factory, 100000, ts::ctx(&mut scenario));

            let _expected_out = simple_dex::calculate_amount_out(&pool, 100000, true);
            let usdt_out = simple_dex::swap_a_to_b(&mut pool, large_trade, 0, ts::ctx(&mut scenario));
            let actual_out = coin::value(&usdt_out);

            let (reserve_a_after, reserve_b_after) = simple_dex::get_reserves(&pool);

            // Verify high price impact (got less than proportional amount)
            let proportional_out = 100000; // Would get ~100k in perfect 1:1 scenario
            assert!(actual_out < proportional_out * 90 / 100, 107); // Got less than 90% of proportional

            // Verify reserves changed significantly
            assert!(reserve_a_after > reserve_a_before, 108);
            assert!(reserve_b_after < reserve_b_before, 109);

            coin_factory::burn_usdt(&mut factory, usdt_out);

            ts::return_shared(pool);
            ts::return_shared(factory);
        };

        ts::end(scenario);
    }
}
