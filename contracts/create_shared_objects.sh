#!/bin/bash
source .env
SENDER=$(sui client active-address)

sui client ptb --move-call $PACKAGE_ID::coin_factory::mint_usdt @$COIN_FACTORY_ID 1000000000000 --assign usdt --transfer-objects "[usdt]" @$SENDER --gas-budget 10000000
sui client ptb --move-call $PACKAGE_ID::coin_factory::mint_weth @$COIN_FACTORY_ID 1000000000000 --assign weth --transfer-objects "[weth]" @$SENDER --gas-budget 10000000
sui client ptb --split-coins @$USDC_ID "[500000000000]" --assign usdc_split --split-coins @$USDT_ID "[500000000000]" --assign usdt_split --move-call "$PACKAGE_ID::simple_dex::create_pool<$PACKAGE_ID::usdc::USDC,$PACKAGE_ID::usdt::USDT>" usdc_split usdt_split --gas-budget 10000000
sui client ptb --split-coins @$USDT_ID "[500000000000]" --assign usdt_split --split-coins @$WETH_ID "[500000000000]" --assign weth_split --move-call "$PACKAGE_ID::simple_dex::create_pool<$PACKAGE_ID::usdt::USDT,$PACKAGE_ID::weth::WETH>" usdt_split weth_split --gas-budget 10000000
sui client ptb --split-coins @$USDC_ID "[100000000000]" --assign usdc_split --move-call "$PACKAGE_ID::flash_loan_pool::create_pool<$PACKAGE_ID::usdc::USDC>" usdc_split 9 --gas-budget 10000000
sui client call --package $PACKAGE_ID --module twap_oracle --function create_oracle --type-args $PACKAGE_ID::usdc::USDC $PACKAGE_ID::usdt::USDT --args $DEX_POOL_USDC_USDT 1800000 60000 --gas-budget 10000000
sui client ptb --split-coins @$USDC_ID "[200000000000]" --assign usdc_split --move-call "$PACKAGE_ID::compound_market::create_market<$PACKAGE_ID::usdc::USDC>" usdc_split @$DEX_POOL_USDC_USDT 7500 1000 @0x6 --assign market --move-call "sui::transfer::public_share_object<$PACKAGE_ID::compound_market::Market<$PACKAGE_ID::usdc::USDC>>" market --gas-budget 10000000
sui client ptb --split-coins @$WETH_ID "[200000000000]" --assign weth_split --move-call "$PACKAGE_ID::compound_market::create_market<$PACKAGE_ID::weth::WETH>" weth_split @$DEX_POOL_USDT_WETH 7500 1000 @0x6 --assign market --move-call "sui::transfer::public_share_object<$PACKAGE_ID::compound_market::Market<$PACKAGE_ID::weth::WETH>>" market --gas-budget 10000000
