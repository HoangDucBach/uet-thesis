# Flash Loan Pool

## Overview

The `flash_loan_pool` module implements an uncollateralized lending protocol that allows users to borrow assets with the condition that the borrowed amount plus a fee must be repaid within the same transaction. Flash loans enable arbitrage, collateral swapping, and self-liquidation strategies without requiring upfront capital.

The module maintains the state of the pool liquidity, tracks historical borrowing statistics, and enforces atomic repayment through the `FlashLoan` receipt mechanism. Unlike traditional lending, flash loans have no collateral requirements, credit checks, or approval processes - loans are executed instantly and must be repaid in the same transaction or the entire transaction reverts.

## Key Public Functions

### create_pool

```move
public fun create_pool<T>(
    initial_funds: Coin<T>,
    fee_rate: u64,
    ctx: &mut TxContext
)
```

Creates a new flash loan pool for a specific asset type with initial liquidity and fee configuration.

**Input Parameters:**

| Name | Type | Description |
|------|------|-------------|
| initial_funds | Coin\<T\> | Initial liquidity to seed the pool |
| fee_rate | u64 | Flash loan fee in basis points (e.g., 9 = 0.09%) |
| ctx | &mut TxContext | Transaction context |

**Behavior:**
- Creates a shared `FlashLoanPool<T>` object
- Initializes pool with provided liquidity
- Sets the fee rate for all flash loans
- Initializes borrowing statistics to zero

---

### borrow_flash_loan

```move
public fun borrow_flash_loan<T>(
    pool: &mut FlashLoanPool<T>,
    amount: u64,
    ctx: &mut TxContext
): (Coin<T>, FlashLoan<T>)
```

Borrows assets from the pool and returns a loan receipt that must be repaid in the same transaction.

**Input Parameters:**

| Name | Type | Description |
|------|------|-------------|
| pool | &mut FlashLoanPool\<T\> | The flash loan pool to borrow from |
| amount | u64 | Amount of assets to borrow |
| ctx | &mut TxContext | Transaction context |

**Return Values:**

| Position | Type | Description |
|----------|------|-------------|
| 0 | Coin\<T\> | Borrowed assets available for use |
| 1 | FlashLoan\<T\> | Loan receipt that must be returned to `repay_flash_loan` |

**Behavior:**
- Validates amount is greater than zero
- Checks pool has sufficient liquidity
- Calculates fee based on pool's fee rate
- Transfers borrowed amount to caller
- Creates `FlashLoan` receipt with pool ID, amount, and fee
- Updates pool statistics (total_borrowed, loan_count)
- Emits `FlashLoanTaken` event

**Error Codes:**
- `E_INVALID_AMOUNT` (3): Borrow amount must be greater than zero
- `E_INSUFFICIENT_BALANCE` (1): Pool does not have enough liquidity

---

### repay_flash_loan

```move
public fun repay_flash_loan<T>(
    pool: &mut FlashLoanPool<T>,
    repayment: Coin<T>,
    loan: FlashLoan<T>,
    ctx: &TxContext
)
```

Repays a flash loan by returning the borrowed amount plus fee. Must be called in the same transaction as `borrow_flash_loan`.

**Input Parameters:**

| Name | Type | Description |
|------|------|-------------|
| pool | &mut FlashLoanPool\<T\> | The flash loan pool to repay to |
| repayment | Coin\<T\> | Payment including borrowed amount and fee |
| loan | FlashLoan\<T\> | Loan receipt from `borrow_flash_loan` |
| ctx | &TxContext | Transaction context |

**Behavior:**
- Validates repayment is for the correct pool
- Validates repayment amount covers borrowed amount plus fee
- Returns repayment to pool liquidity
- Destroys the `FlashLoan` receipt
- Emits `FlashLoanRepaid` event

**Error Codes:**
- `E_WRONG_POOL` (4): Loan receipt does not match the pool
- `E_LOAN_NOT_REPAID` (2): Repayment amount insufficient (< amount + fee)

---

### add_liquidity

```move
public fun add_liquidity<T>(
    pool: &mut FlashLoanPool<T>,
    liquidity: Coin<T>
)
```

Adds liquidity to the pool, increasing available funds for flash loans.

**Input Parameters:**

| Name | Type | Description |
|------|------|-------------|
| pool | &mut FlashLoanPool\<T\> | The flash loan pool |
| liquidity | Coin\<T\> | Assets to add to the pool |

**Behavior:**
- Joins the provided liquidity to pool balance
- No LP tokens are minted (simple liquidity model)

## View Functions

### get_available_liquidity

```move
public fun get_available_liquidity<T>(pool: &FlashLoanPool<T>): u64
```

Returns the current amount of assets available for borrowing in the pool.

**Input Parameters:**

| Name | Type | Description |
|------|------|-------------|
| pool | &FlashLoanPool\<T\> | The flash loan pool |

**Return Value:**

| Type | Description |
|------|-------------|
| u64 | Available liquidity in the pool |

---

### get_stats

```move
public fun get_stats<T>(pool: &FlashLoanPool<T>): (u64, u64, u64, u64)
```

Returns comprehensive statistics about the flash loan pool.

**Input Parameters:**

| Name | Type | Description |
|------|------|-------------|
| pool | &FlashLoanPool\<T\> | The flash loan pool |

**Return Values:**

| Position | Type | Description |
|----------|------|-------------|
| 0 | u64 | Current available liquidity |
| 1 | u64 | Total amount borrowed historically |
| 2 | u64 | Total number of loans issued |
| 3 | u64 | Fee rate in basis points |

---

### get_fee_rate

```move
public fun get_fee_rate<T>(pool: &FlashLoanPool<T>): u64
```

Returns the flash loan fee rate for the pool.

**Input Parameters:**

| Name | Type | Description |
|------|------|-------------|
| pool | &FlashLoanPool\<T\> | The flash loan pool |

**Return Value:**

| Type | Description |
|------|-------------|
| u64 | Fee rate in basis points (e.g., 9 = 0.09%) |

## Events

### FlashLoanTaken

```move
public struct FlashLoanTaken<phantom T> has copy, drop {
    pool_id: address,
    borrower: address,
    amount: u64,
    fee: u64,
}
```

Emitted when a flash loan is borrowed from the pool.

**Fields:**

| Name | Type | Description |
|------|------|-------------|
| pool_id | address | Address of the flash loan pool |
| borrower | address | Address of the borrower |
| amount | u64 | Amount borrowed |
| fee | u64 | Fee to be paid on repayment |

---

### FlashLoanRepaid

```move
public struct FlashLoanRepaid<phantom T> has copy, drop {
    pool_id: address,
    borrower: address,
    amount: u64,
    fee: u64,
}
```

Emitted when a flash loan is successfully repaid.

**Fields:**

| Name | Type | Description |
|------|------|-------------|
| pool_id | address | Address of the flash loan pool |
| borrower | address | Address of the borrower |
| amount | u64 | Amount repaid (principal) |
| fee | u64 | Fee paid |

## Core Data Structures

### FlashLoanPool

```move
public struct FlashLoanPool<phantom T> has key {
    id: UID,
    balance: Balance<T>,
    fee_rate: u64,
    total_borrowed: u64,
    loan_count: u64,
}
```

Represents the flash loan pool state.

**Fields:**

| Name | Type | Description |
|------|------|-------------|
| id | UID | Unique identifier for the pool |
| balance | Balance\<T\> | Current liquidity in the pool |
| fee_rate | u64 | Flash loan fee in basis points (9 = 0.09%) |
| total_borrowed | u64 | Cumulative amount borrowed historically |
| loan_count | u64 | Total number of flash loans issued |

---

### FlashLoan

```move
public struct FlashLoan<phantom T> {
    pool_id: address,
    amount: u64,
    fee: u64,
}
```

Receipt for a flash loan that must be repaid in the same transaction. This struct does not have the `drop` ability, ensuring it cannot be ignored and must be consumed by `repay_flash_loan`.

**Fields:**

| Name | Type | Description |
|------|------|-------------|
| pool_id | address | Address of the originating pool |
| amount | u64 | Amount borrowed |
| fee | u64 | Fee that must be paid |

## Key Features

### Atomic Loan-Repay Mechanism

The flash loan protocol enforces atomicity through Move's type system. The `FlashLoan` receipt struct does not have the `drop` ability, which means:

1. The receipt **must** be consumed by calling `repay_flash_loan`
2. If repayment fails, the receipt cannot be destroyed
3. The entire transaction reverts if the loan is not properly repaid

This is a key security feature that prevents users from taking loans without repaying them.

### Fee Calculation

Flash loan fees are calculated in basis points:
- Fee in basis points (e.g., 9 = 0.09%, 30 = 0.3%)
- Fee amount = `(borrowed_amount * fee_rate) / 10000`
- Total repayment = `borrowed_amount + fee_amount`

Example: Borrowing 1,000,000 tokens with 9 bps fee:
- Fee = (1,000,000 × 9) / 10,000 = 900 tokens
- Total repayment = 1,000,900 tokens

### Typical Flash Loan Flow

```move
// 1. Borrow assets
let (borrowed_coins, loan_receipt) = borrow_flash_loan(pool, 1000000, ctx);

// 2. Use borrowed assets for arbitrage, liquidation, etc.
let profit_coins = execute_arbitrage_strategy(borrowed_coins, ...);

// 3. Combine borrowed amount + fee for repayment
let repayment = combine_coins(borrowed_coins, fee_coins);

// 4. Repay loan (must happen in same transaction)
repay_flash_loan(pool, repayment, loan_receipt, ctx);
```

## Error Handling

| Error Code | Constant | Description |
|------------|----------|-------------|
| 1 | E_INSUFFICIENT_BALANCE | Pool does not have enough liquidity for the requested loan |
| 2 | E_LOAN_NOT_REPAID | Repayment amount is less than borrowed amount + fee |
| 3 | E_INVALID_AMOUNT | Borrow amount must be greater than zero |
| 4 | E_WRONG_POOL | Attempting to repay to a different pool than borrowed from |

## Comparison to Traditional Flash Loans

### Similarities to Aave Flash Loans
- Uncollateralized lending within a single transaction
- Fee-based revenue model
- Atomic loan-repay enforcement
- Support for arbitrage and liquidation strategies

### Key Differences

| Feature | Aave (Solidity/EVM) | This Implementation (Move/Sui) |
|---------|---------------------|--------------------------------|
| Atomicity Enforcement | require() statements | Move type system (non-droppable receipt) |
| Multiple Borrows | Single flash loan call can borrow multiple assets | One borrow per asset type |
| Fee Distribution | Protocol treasury + LP providers | All fees go to pool liquidity |
| Premium Model | Two-tier (total premium + protocol premium) | Single fee rate |

### Security Guarantees

The Move implementation provides stronger compile-time guarantees:

1. **Type Safety**: The `FlashLoan` receipt cannot be copied, dropped, or stored, only consumed
2. **No Reentrancy**: Move's resource model prevents reentrancy attacks
3. **Explicit Ownership**: All asset transfers are explicit and tracked by the type system

## Use Cases

### Arbitrage
Flash loans enable traders to exploit price differences across DEXs without upfront capital.

```move
// Pseudo-code
let (borrowed, loan) = borrow_flash_loan(pool, amount, ctx);
let swapped = swap_on_dex_a(borrowed, ...);
let profit = swap_on_dex_b(swapped, ...);
let repayment = split_for_repayment(profit, amount + fee);
repay_flash_loan(pool, repayment, loan, ctx);
// Keep remaining profit
```

### Collateral Swap
Users can swap collateral types in lending protocols without closing positions.

### Self-Liquidation
Borrowers can flash loan to repay debt and avoid liquidation penalties.

### Protocol Refinancing
Move debt from one lending protocol to another with better rates.

## Integration Guide

### For Protocol Developers

To integrate flash loans into your DeFi protocol:

1. **Borrow**: Call `borrow_flash_loan` to obtain assets and a loan receipt
2. **Execute**: Perform your protocol operations with the borrowed assets
3. **Prepare Repayment**: Ensure you have `borrowed_amount + fee`
4. **Repay**: Call `repay_flash_loan` before transaction ends

### Example Integration

```move
public fun arbitrage_with_flash_loan<T>(
    flash_pool: &mut FlashLoanPool<T>,
    dex1: &mut Pool<T, USDC>,
    dex2: &mut Pool<T, USDC>,
    amount: u64,
    ctx: &mut TxContext
) {
    // Borrow
    let (borrowed, loan) = borrow_flash_loan(flash_pool, amount, ctx);

    // Arbitrage
    let usdc = swap_on_dex1(dex1, borrowed, ctx);
    let tokens_back = swap_on_dex2(dex2, usdc, ctx);

    // Split repayment + fee
    let (repayment, profit) = split_coins(tokens_back, loan.amount + loan.fee);

    // Repay
    repay_flash_loan(flash_pool, repayment, loan, ctx);

    // Transfer profit to user
    transfer::public_transfer(profit, tx_context::sender(ctx));
}
```

## References

- [Aave V3 Flash Loans](https://docs.aave.com/developers/guides/flash-loans)
- [EIP-3156 Flash Loan Standard](https://eips.ethereum.org/EIPS/eip-3156)
- [Move Language Book](https://move-language.github.io/move/)
