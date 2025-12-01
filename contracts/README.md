# Sui DeFi Attack Simulation

A comprehensive Move smart contract framework for simulating real-world DeFi attacks on the Sui blockchain. This project provides infrastructure, DeFi protocols, and attack scenarios for testing and analyzing blockchain security.

## 🎯 Overview

This simulation framework enables:
- **Testing DeFi attack patterns** (flash loans, sandwich attacks, oracle manipulation)
- **Analyzing attack detection mechanisms**
- **Educational demonstrations** of blockchain security vulnerabilities
- **Research on MEV** (Maximal Extractable Value)

## 📁 Project Structure

```
sui-defi-attack-simulation/
├── sources/
│   ├── infrastructure/
│   │   ├── coin_factory.move          # Test token creation (USDC, USDT, WETH, BTC)
│   │   └── price_oracle.move          # Manipulatable price oracle
│   ├── defi_protocols/
│   │   ├── dex/
│   │   │   └── simple_dex.move        # AMM pool (Uniswap V2 style)
│   │   └── lending/
│   │       └── flash_loan_pool.move   # Flash loan provider
│   ├── attack_simulations/
│   │   ├── flash_loan_attack.move     # Flash loan arbitrage attacks
│   │   └── sandwich_attack.move       # MEV sandwich attacks
│   ├── victim_scenarios/
│   │   └── retail_trader.move         # Innocent user transactions
│   └── utilities/
│       └── math.move                  # Math utilities
└── tests/
    └── basic_test.move                # Unit tests
```

## 🏗️ Core Components

### Infrastructure Modules

#### **Coin Factory** (`coin_factory.move`)
Creates test tokens for simulation:
- **USDC** (6 decimals)
- **USDT** (6 decimals)
- **WETH** (8 decimals)
- **BTC** (8 decimals)
- **SUI_COIN** (9 decimals)

```move
// Mint test tokens
let usdc = coin_factory::mint_usdc(&mut factory, 1_000_000, ctx);
let usdt = coin_factory::mint_usdt(&mut factory, 1_000_000, ctx);
```

#### **Price Oracle** (`price_oracle.move`)
Manipulatable price feeds for testing oracle attacks:

```move
// Update price
price_oracle::update_price<USDC>(oracle, 100_000_000, confidence, clock, ctx);

// Manipulate price (for attack simulation)
price_oracle::manipulate_price<USDT>(oracle, new_price, clock, ctx);
```

### DeFi Protocol Modules

#### **Simple DEX** (`simple_dex.move`)
Constant product AMM (like Uniswap V2):

```move
// Create pool
simple_dex::create_pool(usdc_coin, usdt_coin, ctx);

// Swap tokens
let usdt_out = simple_dex::swap_a_to_b(pool, usdc_coin, min_out, ctx);

// Add liquidity
simple_dex::add_liquidity(pool, token_a, token_b, min_liquidity, ctx);
```

**Features:**
- Constant product formula: `x * y = k`
- 0.3% swap fee (30 basis points)
- Slippage protection
- Price impact calculation

#### **Flash Loan Pool** (`flash_loan_pool.move`)
Uncollateralized flash loans:

```move
// Borrow flash loan
let (borrowed, receipt) = flash_loan_pool::borrow_flash_loan(pool, amount, ctx);

// ... use borrowed funds for arbitrage ...

// Repay flash loan (must happen in same transaction)
flash_loan_pool::repay_flash_loan(pool, repayment, receipt, ctx);
```

**Features:**
- 0.09% flash loan fee (9 basis points)
- Atomic borrow/repay enforcement
- Unlimited liquidity (for testing)

### Attack Simulation Modules

#### **Flash Loan Attack** (`flash_loan_attack.move`)

Demonstrates arbitrage attacks using flash loans:

```move
// Execute flash loan arbitrage attack
flash_loan_attack::execute_arbitrage_attack(
    flash_pool,
    dex_pool_1,
    dex_pool_2,
    oracle,
    clock,
    loan_amount,
    ctx
);
```

**Attack Flow:**
1. Borrow USDC via flash loan
2. Manipulate oracle price (optional)
3. Swap USDC → USDT in Pool 1
4. Swap USDT → USDC in Pool 2 (arbitrage)
5. Repay flash loan + fee
6. Keep profit

#### **Sandwich Attack** (`sandwich_attack.move`)

MEV sandwich attack simulation:

```move
// Execute sandwich attack
sandwich_attack::execute_sandwich_attack(
    pool,
    front_run_amount,
    victim_amount,
    attacker_coins,
    victim_coins,
    victim_address,
    ctx
);
```

**Attack Flow:**
1. **Front-run:** Buy tokens before victim to increase price
2. **Victim trade:** Victim executes trade at worse price
3. **Back-run:** Sell tokens after victim to profit

### Victim Scenario Modules

#### **Retail Trader** (`retail_trader.move`)

Simulates innocent user trading:

```move
// Execute normal trade with slippage protection
let (tokens_out, remaining) = retail_trader::execute_normal_trade(
    pool,
    trade_amount,
    max_slippage_bp, // e.g., 500 = 5%
    user_coins,
    ctx
);
```

## 🧪 Testing

Run the test suite:

```bash
sui move test
```

### Test Coverage

- ✅ Coin factory creation and minting
- ✅ DEX pool creation and reserves
- ✅ Token swaps with slippage
- ✅ Flash loan borrow/repay
- ✅ Price oracle updates
- ✅ Attack simulations

## 📊 Events

All modules emit events for analysis:

### **SwapExecuted**
```move
struct SwapExecuted {
    pool_id: address,
    user: address,
    amount_in: u64,
    amount_out: u64,
    fee_amount: u64,
    price_impact: u64,  // basis points
}
```

### **FlashLoanAttackExecuted**
```move
struct FlashLoanAttackExecuted {
    attacker: address,
    borrowed_amount: u64,
    profit_amount: u64,
}
```

### **SandwichAttackExecuted**
```move
struct SandwichAttackExecuted {
    attacker: address,
    victim: address,
    victim_slippage: u64,
    attacker_profit: u64,
}
```

## 🔧 Development

### Build the project

```bash
sui move build
```

### Run tests

```bash
sui move test
```

### Deploy to testnet

```bash
sui client publish --gas-budget 100000000
```

## 📚 Use Cases

1. **Security Research:** Test attack detection algorithms
2. **Education:** Demonstrate DeFi vulnerabilities
3. **MEV Analysis:** Study maximal extractable value
4. **Protocol Testing:** Stress-test DeFi protocols
5. **Attack Detection:** Train ML models on attack patterns

## ⚠️ Security Considerations

**This is a simulation framework for educational and testing purposes only.**

- ❌ DO NOT use in production
- ❌ DO NOT deploy to mainnet
- ❌ Contains intentionally vulnerable code
- ✅ Use only on testnet/devnet
- ✅ For research and education

## 🎓 Resources

- [Sui Move Book](https://move-book.com/)
- [Sui Move Reference](https://move-book.com/reference)
- [Sui Documentation](https://docs.sui.io/)
- [Move Book GitHub](https://github.com/MystenLabs/move-book)

## 📄 License

MIT License - For educational and research purposes only.

## 🤝 Contributing

Contributions welcome! Please ensure:
- All tests pass
- Code follows Sui Move best practices
- Documentation is updated
- Security warnings are clear

## 🔗 Related Projects

- [Sui Framework](https://github.com/MystenLabs/sui)
- [Move Language](https://github.com/move-language/move)
- [DeFi Security Research](https://github.com/topics/defi-security)

---

**⚡ Built for educational purposes to advance blockchain security research.**
