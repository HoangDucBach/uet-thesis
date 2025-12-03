# DeFi Protocol on Sui

A comprehensive decentralized finance (DeFi) protocol implemented on the Sui blockchain, featuring an automated market maker (AMM) DEX with TWAP oracle integration and flash loan lending capabilities.

## 📋 Table of Contents

- [Features](#features)
- [Architecture](#architecture)
- [Getting Started](#getting-started)
- [Protocol Components](#protocol-components)
- [Testing](#testing)
- [Deployment](#deployment)
- [Security Considerations](#security-considerations)
- [License](#license)

## ✨ Features

### DEX (Decentralized Exchange)
- **Automated Market Maker (AMM)**: Uniswap V2-style constant product formula (`x * y = k`)
- **Liquidity Pools**: Create and manage token pair pools
- **Token Swaps**: Swap between any token pairs with automatic price discovery
- **Liquidity Provision**: Add/remove liquidity and earn trading fees
- **Slippage Protection**: Minimum output amount guarantees
- **Fee System**: 0.3% trading fee (30 basis points) for liquidity providers

### TWAP Oracle
- **Time-Weighted Average Price**: Tracks price movements over time
- **Price Manipulation Detection**: Automatic deviation alerts when spot price diverges significantly from TWAP
- **Circular Buffer**: Efficient storage of price observations
- **Configurable Windows**: Customizable time windows for TWAP calculation (default: 30 minutes)
- **Update Intervals**: Configurable minimum intervals between observations (default: 1 minute)

### Flash Loans
- **Uncollateralized Borrowing**: Borrow large amounts without collateral
- **Single Transaction Execution**: Borrow and repay must occur in the same transaction
- **Fee-Based**: 0.09% flash loan fee (9 basis points)
- **Liquidity Management**: Add/remove liquidity to flash loan pools
- **Statistics Tracking**: Monitor total borrowed volume and loan counts

## 🏗️ Architecture

```
contracts/
├── sources/
│   ├── defi_protocols/
│   │   ├── dex/
│   │   │   ├── simple_dex.move          # AMM DEX implementation
│   │   │   └── twap_oracle.move         # TWAP oracle
│   │   └── lending/
│   │       └── flash_loan_pool.move     # Flash loan implementation
│   ├── test_utils/
│   │   ├── coin_factory.move            # Test coin minting
│   │   └── coins.move                   # Mock tokens (USDC, USDT, WETH, BTC, SUI)
│   └── utilities/
│       └── math.move                    # Mathematical utilities
└── tests/
    ├── dex_tests.move                   # DEX comprehensive tests
    └── flash_loan_tests.move            # Flash loan tests
```

## 🚀 Getting Started

### Prerequisites

- [Sui CLI](https://docs.sui.io/build/install) (v1.19.0 or later)
- [Rust](https://www.rust-lang.org/tools/install) (for building)

### Installation

1. Clone the repository:
```bash
git clone <repository-url>
cd contracts
```

2. Build the project:
```bash
sui move build
```

3. Run tests:
```bash
sui move test
```

## 📦 Protocol Components

### 1. DEX Module (`simple_dex.move`)

#### Create Pool
```move
public fun create_pool<TokenA, TokenB>(
    token_a: Coin<TokenA>,
    token_b: Coin<TokenB>,
    ctx: &mut TxContext
)
```

Creates a new liquidity pool for a token pair. Initial liquidity providers receive LP tokens representing their share of the pool.

#### Swap Tokens
```move
public fun swap_a_to_b<TokenA, TokenB>(
    pool: &mut Pool<TokenA, TokenB>,
    token_a: Coin<TokenA>,
    min_out: u64,
    ctx: &mut TxContext
): Coin<TokenB>
```

Swaps TokenA for TokenB using the constant product formula. Includes slippage protection via `min_out` parameter.

#### Swap with TWAP Oracle Update
```move
public fun swap_a_to_b_with_twap<TokenA, TokenB>(
    pool: &mut Pool<TokenA, TokenB>,
    oracle: &mut TWAPOracle<TokenA, TokenB>,
    token_a: Coin<TokenA>,
    min_out: u64,
    clock: &Clock,
    ctx: &mut TxContext
): Coin<TokenB>
```

Performs swap and automatically updates the TWAP oracle with new price observation.

#### Add Liquidity
```move
public fun add_liquidity<TokenA, TokenB>(
    pool: &mut Pool<TokenA, TokenB>,
    token_a: Coin<TokenA>,
    token_b: Coin<TokenB>,
    min_liquidity: u64,
    ctx: &mut TxContext
)
```

Adds liquidity to an existing pool. Amounts must maintain the current pool ratio.

#### Events Emitted

**PoolCreated**
```move
public struct PoolCreated<phantom TokenA, phantom TokenB> has copy, drop {
    pool_id: address,
    initial_a: u64,
    initial_b: u64,
    creator: address,
}
```

**SwapExecuted**
```move
public struct SwapExecuted<phantom TokenA, phantom TokenB> has copy, drop {
    pool_id: address,
    sender: address,
    token_in: bool,        // true = TokenA in, false = TokenB in
    amount_in: u64,
    amount_out: u64,
    fee_amount: u64,
    reserve_a: u64,        // Reserves after swap
    reserve_b: u64,
    price_impact: u64,     // Basis points
}
```

**LiquidityAdded**
```move
public struct LiquidityAdded<phantom TokenA, phantom TokenB> has copy, drop {
    pool_id: address,
    provider: address,
    amount_a: u64,
    amount_b: u64,
    liquidity_minted: u64,
}
```

### 2. TWAP Oracle (`twap_oracle.move`)

#### Create Oracle
```move
public fun create_oracle<TokenA, TokenB>(
    pool_id: address,
    window_size_ms: u64,      // e.g., 1800000 for 30 minutes
    update_interval_ms: u64,  // e.g., 60000 for 1 minute
    ctx: &mut TxContext
)
```

Creates a TWAP oracle for tracking a specific pool's price over time.

#### Update Observation
```move
public fun update_observation<TokenA, TokenB>(
    oracle: &mut TWAPOracle<TokenA, TokenB>,
    reserve_a: u64,
    reserve_b: u64,
    clock: &Clock,
)
```

Records a new price observation. Called automatically by `swap_*_with_twap` functions.

#### Get TWAP Price
```move
public fun get_twap<TokenA, TokenB>(
    oracle: &TWAPOracle<TokenA, TokenB>,
    clock: &Clock,
): (u64, u64)
```

Returns time-weighted average prices for both directions (TokenA/TokenB and TokenB/TokenA).

#### Events Emitted

**TWAPUpdated**
```move
public struct TWAPUpdated has copy, drop {
    pool_id: address,
    token_a: TypeName,
    token_b: TypeName,
    twap_price_a: u64,      // Scaled by 1e9
    twap_price_b: u64,
    spot_price_a: u64,
    spot_price_b: u64,
    price_deviation: u64,   // Basis points
    timestamp: u64,
}
```

**PriceDeviationDetected**
```move
public struct PriceDeviationDetected has copy, drop {
    pool_id: address,
    token_a: TypeName,
    token_b: TypeName,
    twap_price: u64,
    spot_price: u64,
    deviation_bps: u64,     // Basis points (10000 = 100%)
    timestamp: u64,
}
```

Emitted when spot price deviates more than 10% from TWAP, indicating potential price manipulation.

### 3. Flash Loan Pool (`flash_loan_pool.move`)

#### Create Pool
```move
public fun create_pool<T>(
    initial_funds: Coin<T>,
    fee_rate: u64,          // Basis points (9 = 0.09%)
    ctx: &mut TxContext
)
```

Creates a flash loan pool with initial liquidity.

#### Borrow Flash Loan
```move
public fun borrow_flash_loan<T>(
    pool: &mut FlashLoanPool<T>,
    amount: u64,
    ctx: &mut TxContext
): (Coin<T>, FlashLoan<T>)
```

Borrows funds from the pool. Returns borrowed coins and a receipt that must be used for repayment.

#### Repay Flash Loan
```move
public fun repay_flash_loan<T>(
    pool: &mut FlashLoanPool<T>,
    repayment: Coin<T>,
    loan: FlashLoan<T>,
    ctx: &TxContext
)
```

Repays the flash loan with fee. Must be called in the same transaction as borrow.

#### Events Emitted

**FlashLoanTaken**
```move
public struct FlashLoanTaken<phantom T> has copy, drop {
    pool_id: address,
    borrower: address,
    amount: u64,
    fee: u64,
}
```

**FlashLoanRepaid**
```move
public struct FlashLoanRepaid<phantom T> has copy, drop {
    pool_id: address,
    borrower: address,
    amount: u64,
    fee: u64,
}
```

## 🧪 Testing

The protocol includes comprehensive test suites covering all functionality:

### Run All Tests
```bash
sui move test
```

### Run Specific Test Suite
```bash
# DEX tests
sui move test --filter dex_tests

# Flash loan tests
sui move test --filter flash_loan_tests
```

### Test Coverage

**DEX Tests** (`dex_tests.move`):
- ✅ Pool creation with initial liquidity
- ✅ Token swaps (A→B and B→A)
- ✅ Adding liquidity to existing pools
- ✅ Slippage protection
- ✅ Multiple sequential swaps
- ✅ Reserve management

**Flash Loan Tests** (`flash_loan_tests.move`):
- ✅ Pool creation
- ✅ Borrow and repay cycle
- ✅ Fee calculation and collection
- ✅ Insufficient liquidity handling
- ✅ Insufficient repayment protection
- ✅ Multiple sequential flash loans
- ✅ Pool statistics tracking

## 📦 Deployment

### 1. Deploy to Testnet

```bash
sui client publish --gas-budget 500000000
```

### 2. Save Important Object IDs

After deployment, save these object IDs:
- **Package ID**: Your deployed protocol package
- **CoinFactory**: For minting test tokens
- **Pool Objects**: For each token pair you create
- **TWAP Oracle Objects**: For each pool
- **FlashLoan Pool Objects**: For each token type

### 3. Create Initial Pools

```bash
# Example: Create USDC/USDT pool
sui client call \
  --package <PACKAGE_ID> \
  --module simple_dex \
  --function create_pool \
  --type-args <PACKAGE_ID>::usdc::USDC <PACKAGE_ID>::usdt::USDT \
  --args <USDC_COIN_OBJECT> <USDT_COIN_OBJECT> \
  --gas-budget 10000000
```

### 4. Create TWAP Oracle for Pool

```bash
sui client call \
  --package <PACKAGE_ID> \
  --module twap_oracle \
  --function create_oracle \
  --type-args <PACKAGE_ID>::usdc::USDC <PACKAGE_ID>::usdt::USDT \
  --args <POOL_ID> 1800000 60000 \
  --gas-budget 10000000
```

## 🔒 Security Considerations

### Audited Features
- ✅ Constant product formula implementation
- ✅ Flash loan borrow/repay atomicity
- ✅ Slippage protection mechanisms
- ✅ Integer overflow protection (Sui Move 2024)

### Known Limitations
- **Price Oracle Dependency**: TWAP oracle is only as reliable as the pool's liquidity
- **Frontrunning**: Like all AMMs, susceptible to MEV (Miner Extractable Value) on active networks
- **Impermanent Loss**: Liquidity providers subject to IL in volatile markets

### Best Practices
1. **Always set `min_out`**: Protect against slippage in swaps
2. **Monitor TWAP deviation**: Large deviations may indicate manipulation
3. **Test flash loan logic**: Ensure profitable execution before mainnet
4. **Check pool depth**: Large swaps on low-liquidity pools have high price impact

## 📊 Economics

### Fee Structure

| Operation | Fee | Recipient |
|-----------|-----|-----------|
| Token Swap | 0.3% (30 bps) | Liquidity Providers |
| Flash Loan | 0.09% (9 bps) | Flash Loan Pool |
| Pool Creation | None | - |
| Add/Remove Liquidity | None | - |

### Pricing Formula

**Constant Product Formula**:
```
x * y = k

where:
- x = reserve of TokenA
- y = reserve of TokenB
- k = constant product
```

**Swap Output Calculation**:
```
amount_out = (amount_in * (10000 - fee) * reserve_out) / (reserve_in * 10000 + amount_in * (10000 - fee))

where fee is in basis points (30 for 0.3%)
```

## 🤝 Contributing

This protocol is part of a research thesis on DeFi attack detection. Contributions are welcome for:
- Additional test coverage
- Gas optimization
- Documentation improvements
- Bug reports

## 📄 License

Apache-2.0

## 📚 References

- [Sui Documentation](https://docs.sui.io/)
- [Move Book 2024](https://move-book.com/)
- [Uniswap V2 Whitepaper](https://uniswap.org/whitepaper.pdf)
- [Flash Loans (Aave)](https://docs.aave.com/developers/guides/flash-loans)

## 📧 Contact

For questions or collaboration:
- **GitHub Issues**: [Create an issue](../../issues)
- **Documentation**: See inline code comments for detailed explanations

---

**Note**: This protocol is designed for educational and research purposes as part of a thesis on DeFi attack detection patterns. Use at your own risk in production environments.
