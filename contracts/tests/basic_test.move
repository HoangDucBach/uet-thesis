// tests/basic_test.move
#[test_only]
module simulation::basic_test {
    use simulation::coin_factory::{Self, CoinFactory, USDC, USDT};
    use simulation::simple_dex::{Self, Pool};
    use simulation::flash_loan_pool::{Self, FlashLoanPool};
    use simulation::price_oracle::{Self, PriceOracle};
    use sui::test_scenario::{Self as ts, Scenario};
    use sui::clock::{Self, Clock};
    use sui::coin;

    const ADMIN: address = @0xAD;
    const ALICE: address = @0xA11CE;
    const BOB: address = @0xB0B;

    #[test]
    fun test_coin_factory_creation() {
        let mut scenario = ts::begin(ADMIN);

        // Initialize coin factory
        {
            coin_factory::init_for_testing(ts::ctx(&mut scenario));
        };

        ts::next_tx(&mut scenario, ADMIN);

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

        // Initialize coin factory
        {
            coin_factory::init_for_testing(ts::ctx(&mut scenario));
        };

        ts::next_tx(&mut scenario, ADMIN);

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

        // Initialize
        {
            coin_factory::init_for_testing(ts::ctx(&mut scenario));
        };

        ts::next_tx(&mut scenario, ADMIN);

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

        // Initialize
        {
            coin_factory::init_for_testing(ts::ctx(&mut scenario));
        };

        ts::next_tx(&mut scenario, ADMIN);

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
                ts::ctx(&mut scenario)
            );

            assert!(coin::value(&borrowed) == 100000, 5);

            // Mint coins to repay (borrowed + fee)
            let repay_amount = 100000 + ((100000 * 9) / 10000);
            let mut repayment = coin_factory::mint_usdc(&mut factory, repay_amount, ts::ctx(&mut scenario));

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
                ts::ctx(&mut scenario)
            );

            let (price, confidence) = price_oracle::get_price<USDC>(&oracle, &clock);
            assert!(price == 100000000, 6);
            assert!(confidence == 1000000, 7);

            ts::return_shared(oracle);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }
}
