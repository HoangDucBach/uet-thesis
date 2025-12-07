# DeFi Protocol on Sui

A decentralized finance (DeFi) protocol on the Sui blockchain, featuring an automated market maker (AMM) DEX with TWAP oracle integration and flash loan lending.

## Features

### DEX (Decentralized Exchange)

- **Automated Market Maker (AMM)**: Uniswap V2-style constant product formula (`x * y = k`)
- **Liquidity Pools**: Create and manage token pair pools
- **Token Swaps**: Swap between any token pairs with automatic price discovery
- **Liquidity Provision**: Add/remove liquidity and earn trading fees
- **Slippage Protection**: Minimum output amount guarantees
- **Fee System**: 0.3% trading fee for liquidity providers

### TWAP Oracle

- **Time-Weighted Average Price**: Tracks price movements over time
- **Price Manipulation Detection**: Alerts on significant spot price deviation from TWAP
- **Circular Buffer**: Efficient storage of price observations
- **Configurable Windows**: Customizable time windows for TWAP calculation

### Flash Loans

- **Uncollateralized Borrowing**: Borrow large amounts without collateral
- **Single Transaction Execution**: Borrow and repay in the same transaction
- **Fee-Based**: 0.09% flash loan fee

## Architecture

```
contracts/
├── sources/
│   ├── defi_protocols/
│   │   ├── dex/
│   │   │   ├── simple_dex.move
│   │   │   └── twap_oracle.move
│   │   └── lending/
│   │       └── flash_loan_pool.move
│   ├── test_utils/
│   │   ├── coin_factory.move
│   │   └── coins.move
│   └── utilities/
│       └── math.move
└── tests/
    ├── dex_tests.move
    └── flash_loan_tests.move
```

## Protocol Components

### DEX Module (`simple_dex.move`)

- **Create Pool**: Create a new liquidity pool for a token pair.
- **Swap Tokens**: Swap TokenA for TokenB using the constant product formula.
- **Swap with TWAP Oracle Update**: Swap and update TWAP oracle.
- **Add Liquidity**: Add liquidity to an existing pool.

#### Events

- **PoolCreated**
- **SwapExecuted**
- **LiquidityAdded**

### TWAP Oracle (`twap_oracle.move`)

- **Create Oracle**: Track pool price over time.
- **Update Observation**: Record new price observation.
- **Get TWAP Price**: Return time-weighted average prices.

#### Events

- **TWAPUpdated**
- **PriceDeviationDetected**

### Flash Loan Pool (`flash_loan_pool.move`)

- **Create Pool**: Create a flash loan pool.
- **Borrow Flash Loan**: Borrow funds from the pool.
- **Repay Flash Loan**: Repay with fee in the same transaction.

#### Events

- **FlashLoanTaken**
- **FlashLoanRepaid**

## Economics

### Fee Structure

| Operation            | Fee           | Recipient           |
| -------------------- | ------------- | ------------------- |
| Token Swap           | 0.3%          | Liquidity Providers |
| Flash Loan           | 0.09%         | Flash Loan Pool     |

### Pricing Formula

**Constant Product Formula**:

```
x * y = k
```

**Swap Output Calculation**:

```
amount_out = (amount_in * (10000 - fee) * reserve_out) / (reserve_in * 10000 + amount_in * (10000 - fee))
```

## References

- [Sui Documentation](https://docs.sui.io/)
- [Move Book 2024](https://move-book.com/)
- [Uniswap V2 Whitepaper](https://uniswap.org/whitepaper.pdf)
- [Flash Loans (Aave)](https://docs.aave.com/developers/guides/flash-loans)

---

**Note**: This protocol is for educational and research purposes as part of a thesis on DeFi attack detection patterns.
