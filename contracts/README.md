# Sui DeFi Attack Simulation - Technical Deep Dive

Framework mô phỏng các cuộc tấn công DeFi trên Sui blockchain sử dụng Move smart contracts. Tài liệu này giải thích chi tiết kỹ thuật từng contract, cách chúng hoạt động, và cách test verify behavior.

## 🏗️ Kiến Trúc Tổng Quan

Project này mô phỏng một hệ sinh thái DeFi hoàn chỉnh với:
- **Infrastructure**: Coin factory, price oracle
- **DeFi Protocols**: DEX (AMM), Flash loan pool
- **Attack Simulations**: Sandwich attacks, Flash loan arbitrage
- **Victim Scenarios**: Retail trader behaviors

Tất cả được implement bằng Sui Move với focus vào:
- **Type Safety**: Sử dụng phantom types cho generic pools
- **Resource Safety**: Sử dụng `Balance` và `Coin` types từ Sui framework
- **Atomic Operations**: Flash loans phải được repay trong cùng transaction
- **Event Emission**: Tất cả operations emit events để tracking

---

## 📦 Infrastructure Modules

### 1. Coin Types (`sources/infrastructure/coins.move`)

**Kỹ thuật: One-Time Witness (OTW) Pattern**

Mỗi coin type (USDC, USDT, WETH, BTC, SUI_COIN) được định nghĩa trong module riêng để có OTW hợp lệ. Đây là requirement của Sui Move để tạo currency.

```move
module simulation::usdc {
    public struct USDC has drop {}
    
    fun init(witness: USDC, ctx: &mut TxContext) {
        let (treasury, metadata) = coin::create_currency(
            witness,  // OTW - chỉ có thể tạo 1 lần
            6,        // decimals
            b"USDC",  // symbol
            b"USD Coin", // name
            b"Test USDC for simulation",
            std::option::none(),
            ctx
        );
        transfer::public_freeze_object(metadata);
        transfer::public_transfer(treasury, ctx.sender());
    }
}
```

**Tại sao tách module?**
- Sui Move yêu cầu OTW phải match với module name
- Module `simulation::usdc` → OTW là `usdc::USDC {}`
- Nếu gộp tất cả vào 1 module, không thể có nhiều OTW khác nhau

**Test Pattern:**
```move
#[test_only]
public fun test_init(ctx: &mut TxContext) {
    init(USDC {}, ctx);  // Tạo OTW instance
}
```

---

### 2. Coin Factory (`sources/infrastructure/coin_factory.move`)

**Kỹ thuật: TreasuryCap Management & Shared Objects**

CoinFactory là một shared object chứa tất cả TreasuryCap của các coins. TreasuryCap cho phép mint/burn coins.

```move
public struct CoinFactory has key {
    id: UID,
    usdc_treasury: TreasuryCap<USDC>,
    usdt_treasury: TreasuryCap<USDT>,
    // ... other treasuries
}
```

**Key Functions:**

1. **Mint Coins:**
```move
public fun mint_usdc(
    factory: &mut CoinFactory,
    amount: u64,
    ctx: &mut TxContext
): Coin<USDC> {
    coin::mint(&mut factory.usdc_treasury, amount, ctx)
}
```
- Sử dụng `&mut` để modify TreasuryCap
- Return `Coin<USDC>` - owned object có thể transfer

2. **Burn Coins:**
```move
public fun burn_usdc(
    factory: &mut CoinFactory, 
    coin: Coin<USDC>
): u64 {
    coin::burn(&mut factory.usdc_treasury, coin)
}
```
- Consume `Coin` để giảm total supply

**Test Setup Pattern:**
```move
fun setup_coin_factory(scenario: &mut ts::Scenario) {
    // Step 1: Init coins (tạo TreasuryCap cho sender)
    coin_factory::init_for_testing(ts::ctx(scenario));
    
    ts::next_tx(scenario, ADMIN);
    
    // Step 2: Lấy TreasuryCap từ sender
    let usdc_treasury = ts::take_from_sender<TreasuryCap<USDC>>(scenario);
    
    // Step 3: Tạo shared CoinFactory
    coin_factory::create_factory(usdc_treasury, ..., ts::ctx(scenario));
}
```

**Tại sao cần `next_tx`?**
- `init_for_testing` tạo TreasuryCap và transfer cho sender trong transaction đầu tiên
- `next_tx` chuyển sang transaction mới với ADMIN làm sender
- `take_from_sender` lấy TreasuryCap từ inventory của ADMIN

---

### 3. Price Oracle (`sources/infrastructure/price_oracle.move`)

**Kỹ thuật: TypeName-based Price Storage & Staleness Checks**

Oracle sử dụng `Table<TypeName, PriceFeed>` để lưu price cho mỗi coin type.

```move
public struct PriceOracle has key {
    id: UID,
    feeds: Table<TypeName, PriceFeed>,
    authorized_sources: VecSet<address>,
    admin: address,
}
```

**Key Mechanism:**

1. **TypeName Extraction:**
```move
let token_type = type_name::with_defining_ids<T>();
```
- `with_defining_ids` tạo TypeName unique cho mỗi coin type
- Cho phép generic function `get_price<T>()` work với bất kỳ coin nào

2. **Staleness Check:**
```move
let current_time = clock::timestamp_ms(clock);
assert!(current_time - feed.timestamp < 300_000, E_STALE_PRICE);
```
- Kiểm tra price không quá 5 phút (300,000ms)
- Sử dụng `Clock` object từ Sui framework

3. **Manipulation Detection:**
```move
if (price_change_pct > 1000) {  // >10%
    event::emit(PriceManipulationDetected { ... });
}
```
- Emit event khi price thay đổi >10% để tracking

---

## 💱 DeFi Protocol Modules

### 4. Simple DEX (`sources/defi_protocols/dex/simple_dex.move`)

**Kỹ thuật: Constant Product AMM (x * y = k) với Fee**

Đây là implementation của Uniswap V2-style AMM trên Sui.

**Pool Structure:**
```move
public struct Pool<phantom TokenA, phantom TokenB> has key {
    id: UID,
    reserve_a: Balance<TokenA>,  // Sử dụng Balance thay vì Coin
    reserve_b: Balance<TokenB>,
    lp_supply: u64,
    fee_rate: u64,  // 30 = 0.3%
}
```

**Tại sao dùng `Balance` thay vì `Coin`?**
- `Balance` là internal storage, không thể transfer trực tiếp
- `Coin` là owned object, có thể transfer
- Pool cần hold reserves internally → dùng `Balance`
- Khi user swap, convert `Coin` → `Balance` (join) và `Balance` → `Coin` (split)

**Swap Formula với Fee:**

```move
// amount_out = (amount_in * (10000-fee) * reserve_b) / (reserve_a * 10000 + amount_in * (10000-fee))
let amount_in_with_fee = amount_in * (10000 - pool.fee_rate);
let numerator = amount_in_with_fee * reserve_b_val;
let denominator = reserve_a_val * 10000 + amount_in_with_fee;
let amount_out = numerator / denominator;
```

**Giải thích:**
- `10000 - fee_rate`: Nếu fee = 30 (0.3%), thì `10000 - 30 = 9970` (99.7% goes to pool)
- `amount_in_with_fee`: Số lượng thực tế được add vào pool sau khi trừ fee
- Formula đảm bảo `(reserve_a + amount_in_with_fee) * (reserve_b - amount_out) = reserve_a * reserve_b` (constant product)

**Swap Execution:**
```move
// 1. Add input to pool
balance::join(&mut pool.reserve_a, coin::into_balance(token_a));

// 2. Calculate and extract output
let token_b_out = coin::from_balance(
    balance::split(&mut pool.reserve_b, amount_out),
    ctx
);
```

**Slippage Protection:**
```move
assert!(amount_out >= min_out, E_SLIPPAGE_TOO_HIGH);
```
- User có thể specify `min_out` để protect khỏi price impact quá lớn
- Nếu actual output < min_out → transaction revert

**Price Impact Calculation:**
```move
let price_impact = (amount_out * 10000) / reserve_b_val;
```
- Tính % của reserve bị extract
- Emit trong event để tracking

**Add Liquidity:**
```move
let liquidity = if (pool.lp_supply == 0) {
    math_utils::sqrt(amount_a * amount_b)  // Initial: sqrt(x * y)
} else {
    // Proportional: min(liquidity_a, liquidity_b)
    let liquidity_a = (amount_a * pool.lp_supply) / reserve_a_val;
    let liquidity_b = (amount_b * pool.lp_supply) / reserve_b_val;
    if (liquidity_a < liquidity_b) { liquidity_a } else { liquidity_b }
};
```

**Test Pattern:**
```move
// Create pool
simple_dex::create_pool(usdc, usdt, ts::ctx(&mut scenario));

ts::next_tx(&mut scenario, ALICE);

// Swap
let mut pool = ts::take_shared<Pool<USDC, USDT>>(&scenario);
let usdc = coin_factory::mint_usdc(&mut factory, 10000, ts::ctx(&mut scenario));
let usdt_out = simple_dex::swap_a_to_b(&mut pool, usdc, 0, ts::ctx(&mut scenario));
```

---

### 5. Flash Loan Pool (`sources/defi_protocols/lending/flash_loan_pool.move`)

**Kỹ thuật: Atomic Borrow-Repay Enforcement**

Flash loans cho phép borrow không cần collateral, nhưng PHẢI repay trong cùng transaction.

**Pool Structure:**
```move
public struct FlashLoanPool<phantom T> has key {
    id: UID,
    balance: Balance<T>,
    fee_rate: u64,  // 9 = 0.09%
    total_borrowed: u64,
    loan_count: u64,
}
```

**Borrow Mechanism:**
```move
public fun borrow_flash_loan<T>(
    pool: &mut FlashLoanPool<T>,
    amount: u64,
    ctx: &mut TxContext
): (Coin<T>, FlashLoan<T>) {
    let fee = (amount * pool.fee_rate) / 10000;
    let borrowed_balance = balance::split(&mut pool.balance, amount);
    let borrowed_coin = coin::from_balance(borrowed_balance, ctx);
    
    let loan = FlashLoan<T> {
        pool_id: object::uid_to_address(&pool.id),
        amount,
        fee,
    };
    
    (borrowed_coin, loan)  // Return cả coin và receipt
}
```

**Repay Mechanism:**
```move
public fun repay_flash_loan<T>(
    pool: &mut FlashLoanPool<T>,
    repayment: Coin<T>,
    loan: FlashLoan<T>,
    ctx: &TxContext
) {
    let FlashLoan { pool_id, amount, fee } = loan;
    
    assert!(pool_id == object::uid_to_address(&pool.id), E_WRONG_POOL);
    assert!(coin::value(&repayment) >= amount + fee, E_LOAN_NOT_REPAID);
    
    balance::join(&mut pool.balance, coin::into_balance(repayment));
}
```

**Tại sao atomic?**
- Nếu transaction không gọi `repay_flash_loan` → transaction sẽ fail
- Nếu `repay_flash_loan` không được gọi đúng cách → `assert!` sẽ fail
- Move's type system đảm bảo `FlashLoan` receipt phải được consumed

**Test Pattern:**
```move
let (borrowed, receipt) = flash_loan_pool::borrow_flash_loan(
    &mut pool, 100000, ts::ctx(&mut scenario)
);

// ... use borrowed funds ...

let repayment = coin::split(&mut profit, repayment_amount, ctx);
flash_loan_pool::repay_flash_loan(&mut pool, repayment, receipt, ts::ctx(&mut scenario));
```

---

## 🎯 Attack Simulation Modules

### 6. Sandwich Attack (`sources/attack_simulations/sandwich_attack.move`)

**Kỹ thuật: MEV Extraction qua Front-run + Back-run**

Sandwich attack là cách attacker extract value từ victim transaction bằng cách:
1. Front-run: Buy trước victim → tăng price
2. Victim trade: Victim swap ở price cao hơn → nhận ít hơn
3. Back-run: Sell sau victim → profit từ price increase

**Attack Flow:**
```move
public fun execute_sandwich_attack(
    pool: &mut Pool<USDC, USDT>,
    front_run_amount: u64,
    victim_amount: u64,
    mut attacker_coins: Coin<USDC>,
    victim_coins: Coin<USDC>,
    victim_address: address,
    ctx: &mut TxContext
): Coin<USDC> {
    // Step 1: Front-run
    let front_run_coin = coin::split(&mut attacker_coins, front_run_amount, ctx);
    let usdt_received = simple_dex::swap_a_to_b(pool, front_run_coin, 0, ctx);
    
    // Step 2: Victim transaction (simulated)
    let expected_victim_out = simple_dex::calculate_amount_out(pool, victim_amount, true);
    let victim_usdt = simple_dex::swap_a_to_b(pool, victim_coins, 0, ctx);
    let actual_victim_out = coin::value(&victim_usdt);
    
    // Calculate slippage
    let victim_slippage = if (expected_victim_out > actual_victim_out) {
        expected_victim_out - actual_victim_out
    } else { 0 };
    
    // Step 3: Back-run
    let usdc_back = simple_dex::swap_b_to_a(pool, usdt_received, 0, ctx);
    
    // Calculate profit
    let usdc_back_value = coin::value(&usdc_back);
    let profit = if (usdc_back_value > front_run_amount) {
        usdc_back_value - front_run_amount
    } else { 0 };
    
    // Transfer victim's tokens
    transfer::public_transfer(victim_usdt, victim_address);
    
    // Return attacker's coins (including profit)
    coin::join(&mut attacker_coins, usdc_back);
    attacker_coins
}
```

**Key Insights:**
- `expected_victim_out`: Số lượng victim sẽ nhận được NẾU không có front-run
- `actual_victim_out`: Số lượng victim thực tế nhận được (ít hơn do front-run)
- `victim_slippage`: Loss của victim = profit của attacker
- Attacker profit = `usdc_back_value - front_run_amount`

**Tại sao hoạt động?**
- Front-run làm tăng `reserve_a` → giảm `reserve_b` → price của TokenB tăng
- Victim swap ở price cao → nhận ít TokenB hơn
- Back-run bán TokenB ở price cao → profit

---

### 7. Flash Loan Attack (`sources/attack_simulations/flash_loan_attack.move`)

**Kỹ thuật: Arbitrage với Zero Capital**

Flash loan cho phép attacker borrow capital lớn để exploit price differences giữa các pools.

**Simple Arbitrage Flow:**
```move
public fun execute_simple_arbitrage(
    flash_pool: &mut FlashLoanPool<USDC>,
    dex_pool_1: &mut Pool<USDC, USDT>,
    dex_pool_2: &mut Pool<USDT, USDC>,
    loan_amount: u64,
    ctx: &mut TxContext,
): Coin<USDC> {
    // Step 1: Borrow
    let (borrowed_usdc, loan_receipt) = flash_loan_pool::borrow_flash_loan(
        flash_pool, loan_amount, ctx
    );
    
    // Step 2: Swap USDC → USDT in Pool 1
    let usdt_received = simple_dex::swap_a_to_b(
        dex_pool_1, borrowed_usdc, 0, ctx
    );
    
    // Step 3: Swap USDT → USDC in Pool 2 (arbitrage)
    let mut usdc_received = simple_dex::swap_a_to_b(
        dex_pool_2, usdt_received, 0, ctx
    );
    
    // Step 4: Repay loan
    let repayment_amount = loan_amount + ((loan_amount * 9) / 10000);
    let usdc_received_value = coin::value(&usdc_received);
    
    assert!(usdc_received_value >= repayment_amount, 2);  // Must have profit
    
    let repayment = coin::split(&mut usdc_received, repayment_amount, ctx);
    flash_loan_pool::repay_flash_loan(flash_pool, repayment, loan_receipt, ctx);
    
    // Step 5: Return profit
    usdc_received  // Remaining after repayment
}
```

**Tại sao cần 2 pools?**
- Pool 1: USDC/USDT với price ratio X
- Pool 2: USDT/USDC với price ratio Y
- Nếu X ≠ 1/Y → có arbitrage opportunity
- Attacker exploit difference này mà không cần capital ban đầu

**Profit Calculation:**
```move
let repayment_amount = loan_amount + fee;  // loan + 0.09%
let profit = usdc_received - repayment_amount;
```
- Profit chỉ có nếu `usdc_received > repayment_amount`
- `assert!` đảm bảo transaction fail nếu không có profit

**Test Setup:**
```move
// Pool 1: 1M USDC, 1M USDT (1:1 ratio)
simple_dex::create_pool(usdc1, usdt1, ctx);

// Pool 2: 1M USDT, 1.15M USDC (price difference)
simple_dex::create_pool(usdt2, usdc2, ctx);

// Arbitrage: Borrow 50k USDC
// Swap 50k USDC → ~50k USDT in Pool 1
// Swap ~50k USDT → ~57.5k USDC in Pool 2
// Repay 50k + fee = 50.045k USDC
// Profit = ~7.455k USDC
```

---

## 🧪 Testing Architecture

### Test Framework: Sui Test Scenario

Sui Move sử dụng `test_scenario` để simulate multi-transaction flows.

**Key Concepts:**
- `ts::begin(address)`: Bắt đầu scenario với sender
- `ts::next_tx(scenario, address)`: Chuyển sang transaction mới với sender mới
- `ts::take_shared<T>()`: Lấy shared object từ scenario
- `ts::take_from_sender<T>()`: Lấy object từ sender's inventory
- `ts::return_shared(obj)`: Return shared object về scenario

**Test Pattern Example:**
```move
#[test]
fun test_simple_swap() {
    let mut scenario = ts::begin(ADMIN);
    
    // Transaction 1: Setup
    {
        setup_coin_factory(&mut scenario);
        // ... create pool ...
    };
    
    ts::next_tx(&mut scenario, ALICE);
    
    // Transaction 2: Execute swap
    {
        let mut pool = ts::take_shared<Pool<USDC, USDT>>(&scenario);
        let usdc = coin_factory::mint_usdc(&mut factory, 10000, ts::ctx(&mut scenario));
        let usdt_out = simple_dex::swap_a_to_b(&mut pool, usdc, 0, ts::ctx(&mut scenario));
        
        ts::return_shared(pool);
    };
    
    ts::end(scenario);
}
```

**Tại sao cần `{ }` blocks?**
- Move's borrow checker yêu cầu references được drop trước khi `next_tx`
- `{ }` block tạo scope → references được drop khi block end
- `return_shared` đảm bảo shared objects được return về scenario

**Test Coverage:**

1. **Coin Factory Tests:**
   - `test_coin_factory_creation`: Verify mint/burn works
   - Verify TreasuryCap management

2. **DEX Tests:**
   - `test_dex_pool_creation`: Verify pool creation và reserves
   - `test_simple_swap`: Verify swap execution
   - `test_add_liquidity`: Verify liquidity addition
   - `test_swap_both_directions`: Verify bidirectional swaps
   - `test_slippage_protection`: Verify slippage protection works
   - `test_slippage_protection_failure`: Verify transaction fails với unrealistic min_out

3. **Flash Loan Tests:**
   - `test_flash_loan_pool`: Verify borrow/repay cycle
   - `test_flash_loan_arbitrage`: Verify arbitrage attack
   - `test_flash_loan_repayment_failure`: Verify transaction fails nếu không repay

4. **Attack Tests:**
   - `test_sandwich_attack_basic`: Verify sandwich attack flow
   - `test_retail_trader_behavior`: Verify victim behavior
   - `test_oracle_manipulation`: Verify oracle attacks
   - `test_high_price_impact`: Verify large trade impact

---

## 🔍 Technical Deep Dives

### Phantom Types trong Generic Pools

```move
public struct Pool<phantom TokenA, phantom TokenB> has key { ... }
```

**Tại sao `phantom`?**
- `phantom` type parameter không được store trong struct
- Chỉ dùng để type-checking và distinguish pools
- `Pool<USDC, USDT>` và `Pool<USDT, USDC>` là 2 types khác nhau
- Không tốn storage space cho type parameters

**Type Safety:**
```move
// Compile error: Type mismatch
let pool1: Pool<USDC, USDT> = ...;
let pool2: Pool<USDT, USDC> = pool1;  // ❌ Error!

// Correct usage
let usdt = simple_dex::swap_a_to_b<USDC, USDT>(&mut pool1, usdc, 0, ctx);
```

### Balance vs Coin

**Balance:**
- Internal storage type
- Không thể transfer trực tiếp
- Dùng trong pools để hold reserves
- Convert: `coin::into_balance(coin)` và `coin::from_balance(balance, ctx)`

**Coin:**
- Owned object type
- Có thể transfer, split, join
- Dùng khi interact với users
- Convert: `balance::split(&mut balance, amount)` → `Coin`

**Usage Pattern:**
```move
// User sends Coin
balance::join(&mut pool.reserve_a, coin::into_balance(user_coin));

// Pool sends Coin to user
let user_coin = coin::from_balance(
    balance::split(&mut pool.reserve_b, amount),
    ctx
);
```

### Event Emission

Tất cả operations emit events để tracking và analysis:

```move
event::emit(SwapExecuted<TokenA, TokenB> {
    pool_id: object::uid_to_address(&pool.id),
    sender: tx_context::sender(ctx),
    token_in: true,
    amount_in,
    amount_out,
    fee_amount,
    reserve_a,
    reserve_b,
    price_impact,
});
```

**Tại sao cần events?**
- Move không có return values từ transactions
- Events là cách duy nhất để track transaction results
- Có thể query events từ blockchain để analyze
- Useful cho attack detection và MEV analysis

---

## 🎯 Key Design Decisions

1. **Separate Modules cho Coin Types:**
   - Required bởi Sui's OTW pattern
   - Mỗi coin cần module riêng để có valid OTW

2. **Shared Objects cho Pools:**
   - Pools cần accessible từ nhiều transactions
   - `has key` + `transfer::share_object` cho phép concurrent access

3. **Balance trong Pools:**
   - Pools không thể hold `Coin` (owned objects)
   - `Balance` là internal storage type phù hợp

4. **Flash Loan Receipt Pattern:**
   - `FlashLoan<T>` struct đảm bảo repay được gọi
   - Type system enforce consumption của receipt

5. **Generic Functions với Phantom Types:**
   - Cho phép type-safe operations
   - Compile-time checking thay vì runtime

---

## 🚀 Running Tests

```bash
# Run all tests
sui move test

# Run specific test
sui move test simulation::basic_test::test_simple_swap

# Build only
sui move build
```

**Test Results:**
- 16 tests total
- 9 basic tests (infrastructure + protocols)
- 7 attack tests (attack simulations)

Tất cả tests verify:
- Correct state transitions
- Error handling
- Slippage protection
- Atomic operations
- Event emission

---

**⚡ Framework này được thiết kế để:**
- Simulate real-world DeFi attacks
- Test attack detection mechanisms
- Educate về blockchain security
- Research MEV extraction patterns
