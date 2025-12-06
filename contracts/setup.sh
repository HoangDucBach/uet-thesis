#!/bin/bash

# ============================================================================
# Environment Setup - Deployed Contracts & Shared Objects
# ============================================================================

# Package & Upgrade
export PACKAGE_ID="0x0a78ed73edcaca699f8ffead05a9626aadd6edb30d49523574c8016806b0530e"
export UPGRADE_CAP="0x8a5e8591bd97355ab8a8cdf68c8b4d16f7f5ad20ae8499b8f1a03541d982c96d"

# Treasury Caps
export BTC_TREASURY_CAP="0x081404de20e34383a0c3cb43859499c5070f5cfbe6147b8421a527c714a88122"
export USDC_TREASURY_CAP="0xf701afb0601824a5adb5ec5ce8f8e25f11ce3d52ccd403576e2d57346a680a75"
export USDT_TREASURY_CAP="0x15f0843960cefb6e203577c4f64f8f88bb63adb9762f50fec1890354033de9a0"
export WETH_TREASURY_CAP="0x65e2474b557a8232dc643725484ebac3031e1c0c7d45fd3499f0d24f34622729"
export SUI_COIN_TREASURY_CAP="0x5ad4bd35e521d128150e2737f37f87e66f3d99c15453da5a5cb6818717b3bcec"

# Metadata
export BTC_METADATA="0x1d9e922bb701f0a060460b3f0ede5974ecc8af527451acdb9abafa3b18ed58b7"
export USDC_METADATA="0xe051556cc264347eae2dad837c550309345f2b641ed639efca306e2d084bbe11"
export USDT_METADATA="0xef2efc67ddc8ec62c3db88b25a3a0130df113b5345c638eaf2fc2a953a930456"
export WETH_METADATA="0x7d2c64f5cd0c24a372ef3eaf0f15902bd7851243f472baf7ff21bc8f4ea4c8ce"
export SUI_COIN_METADATA="0x641af6ec81de8b63352f871f538fd0dcd23124d843ea558f22a4f62dfa0b48d1"

# Coin Factory
export COIN_FACTORY_ID="0xd3a0118f295dc9a4de0ea3756cfd369aeedf5e91ec7464178724603c12525512"

# Coin Objects
export USDC_ID="0xc8da7f40fd720b6b453e4c89c5aaa0a112f734a6db3a8e0a7a547f695d04945d"
export USDT_ID="0xe3bcd755755ecac83bc682861282ed3b328b7c7ceadb817d481f43920b5ca37a"
export WETH_ID="0x7365f07be9e0724d950d230a9dc2bddb93c512184601ef1e4c1f7250a2210a53"

# Shared Objects - DEX
export DEX_POOL_USDC_USDT="0xcd7c37355a73ace339b03847c860a43797a06cd675f051831562e39e2d4ba14e"
export DEX_POOL_USDT_WETH="0x14a22a54906f8efb546c5f01bcf0220cebbf3b36fc6a124edcefe01977eaed84"

# Shared Objects - Flash Loan
export FLASH_LOAN_POOL_USDC="0xd8c8d2282cc2b2990b4e39709684ef9cfd9fe18a56167d0e32134d90d1e6892b"

# Shared Objects - Oracle
export TWAP_ORACLE_USDC_USDT="0x41d2adfef301525654c19f1b8e207f11a91f37d362788f129c47cc08d716a50b"

# Shared Objects - Lending Markets
export MARKET_USDC="0x6a60fddeebd4087dbeddb65ea71cb38a04bce435dbaa79a757a5cfcbf3c0b731"
export MARKET_WETH="0xb5b1e261dd733cd9b3f72e33b2694a86e1a2bad3cca6676d6818bfc30ce850be"

# Coin Types
export USDC_TYPE="$PACKAGE_ID::usdc::USDC"
export USDT_TYPE="$PACKAGE_ID::usdt::USDT"
export WETH_TYPE="$PACKAGE_ID::weth::WETH"
export BTC_TYPE="$PACKAGE_ID::btc::BTC"
export SUI_TYPE="$PACKAGE_ID::sui_coin::SUI_COIN"

# Wallet
export ADMIN=$(sui client active-address)

echo "✓ Environment variables loaded!"
echo ""
echo "  📦 Package:        $PACKAGE_ID"
echo "  👤 Admin:          $ADMIN"
echo ""
echo "  🔄 DEX Pools:      2"
echo "  ⚡ Flash Loan:     $FLASH_LOAN_POOL_USDC"
echo "  📊 Oracle:         $TWAP_ORACLE_USDC_USDT"
echo "  🏦 Lending:        2 markets"
echo ""
