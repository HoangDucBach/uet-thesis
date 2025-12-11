#!/usr/bin/env python3
"""
Generate realistic DeFi transaction data for Elasticsearch testing
Simulates 1000+ transactions with diverse attack patterns (90% realistic)
"""

import json
import random
import hashlib
from datetime import datetime, timedelta
from typing import List, Dict, Any

# ============================================================================
# CONSTANTS FROM DEPLOYMENT
# ============================================================================

PACKAGE_ID = "0x0a78ed73edcaca699f8ffead05a9626aadd6edb30d49523574c8016806b0530e"

# Pool IDs
FLASH_LOAN_POOL_USDC = "0xd8c8d2282cc2b2990b4e39709684ef9cfd9fe18a56167d0e32134d90d1e6892b"
DEX_POOL_USDC_USDT = "0xcd7c37355a73ace339b03847c860a43797a06cd675f051831562e39e2d4ba14e"
DEX_POOL_USDT_WETH = "0x14a22a54906f8efb546c5f01bcf0220cebbf3b36fc6a124edcefe01977eaed84"
DEX_POOL_WETH_USDC = "0x9e8326e5cf8b5ccb07f9c8bd39f4a9f95bc7b51f8ea8d70fdea0eb3f4ad92314"
TWAP_ORACLE_USDC_USDT = "0x41d2adfef301525654c19f1b8e207f11a91f37d362788f129c47cc08d716a50b"

# Market IDs
MARKET_USDC = "0x889c24bf63b0d35f44518aea42dac181849f7945d61de20bc86bdbb81da19fd2"
MARKET_WETH = "0x7b9b4f5b6f49d891cf591b029cefee678c6f7b97813b93ce1cf4de607cc5f119"

# Coin IDs
USDC_ID = "0xc8da7f40fd720b6b453e4c89c5aaa0a112f734a6db3a8e0a7a547f695d04945d"
USDT_ID = "0xe3bcd755755ecac83bc682861282ed3b328b7c7ceadb817d481f43920b5ca37a"
WETH_ID = "0x7365f07be9e0724d950d230a9dc2bddb93c512184601ef1e4c1f7250a2210a53"

# ============================================================================
# REALISTIC ADDRESS POOLS
# ============================================================================

# Bot/MEV addresses (attackers)
MEV_BOTS = [
    "0x1a2b3c4d5e6f7890abcdef1234567890abcdef12",
    "0x9876543210fedcba0987654321fedcba09876543",
    "0xdeadbeefcafebabe1234567890abcdef12345678",
    "0x7777777777777777777777777777777777777777",
    "0x8888888888888888888888888888888888888888",
]

# Normal users (victims/regular traders)
NORMAL_USERS = [
    f"0x{''.join(random.choices('0123456789abcdef', k=40))}"
    for _ in range(50)
]

# Liquidity providers
LP_PROVIDERS = [
    f"0x{''.join(random.choices('0123456789abcdef', k=40))}"
    for _ in range(20)
]

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

def generate_tx_digest() -> str:
    """Generate realistic transaction digest"""
    random_bytes = random.randbytes(32)
    return hashlib.sha256(random_bytes).hexdigest()

def generate_checkpoint() -> int:
    """Generate checkpoint number"""
    return random.randint(10000000, 12000000)

def calculate_price_impact(amount_in: int, reserve_in: int, reserve_out: int) -> int:
    """Calculate price impact in basis points (10000 = 100%)"""
    if reserve_in == 0:
        return 0

    # Using constant product formula: x * y = k
    # Price impact = (amount_in / (reserve_in + amount_in)) * 10000
    impact = (amount_in * 10000) // (reserve_in + amount_in)
    return min(impact, 10000)  # Cap at 100%

def calculate_amount_out(amount_in: int, reserve_in: int, reserve_out: int, fee_rate: int = 30) -> int:
    """Calculate output amount using constant product AMM"""
    if reserve_in == 0 or reserve_out == 0:
        return 0

    # Apply fee
    amount_in_with_fee = amount_in * (10000 - fee_rate)

    # x * y = k formula
    numerator = amount_in_with_fee * reserve_out
    denominator = (reserve_in * 10000) + amount_in_with_fee

    if denominator == 0:
        return 0

    return numerator // denominator

# ============================================================================
# EVENT GENERATORS
# ============================================================================

def generate_swap_event(
    pool_id: str,
    sender: str,
    amount_in: int,
    reserve_a: int,
    reserve_b: int,
    token_in: bool = True,
    timestamp: datetime = None
) -> Dict[str, Any]:
    """Generate SwapExecuted event"""

    amount_out = calculate_amount_out(amount_in, reserve_a if token_in else reserve_b,
                                      reserve_b if token_in else reserve_a)
    price_impact = calculate_price_impact(amount_in, reserve_a if token_in else reserve_b,
                                          reserve_b if token_in else reserve_a)

    fee_amount = (amount_in * 30) // 10000  # 0.3% fee

    return {
        "type": "SwapExecuted",
        "pool_id": pool_id,
        "sender": sender,
        "token_in": token_in,
        "amount_in": amount_in,
        "amount_out": amount_out,
        "fee_amount": fee_amount,
        "reserve_a": reserve_a,
        "reserve_b": reserve_b,
        "price_impact": price_impact,
        "timestamp": (timestamp or datetime.now()).isoformat()
    }

def generate_flash_loan_taken(
    pool_id: str,
    borrower: str,
    amount: int,
    timestamp: datetime = None
) -> Dict[str, Any]:
    """Generate FlashLoanTaken event"""
    fee = (amount * 9) // 10000  # 0.09% fee

    return {
        "type": "FlashLoanTaken",
        "pool_id": pool_id,
        "borrower": borrower,
        "amount": amount,
        "fee": fee,
        "timestamp": (timestamp or datetime.now()).isoformat()
    }

def generate_flash_loan_repaid(
    pool_id: str,
    borrower: str,
    amount: int,
    timestamp: datetime = None
) -> Dict[str, Any]:
    """Generate FlashLoanRepaid event"""
    fee = (amount * 9) // 10000

    return {
        "type": "FlashLoanRepaid",
        "pool_id": pool_id,
        "borrower": borrower,
        "amount": amount,
        "fee": fee,
        "timestamp": (timestamp or datetime.now()).isoformat()
    }

def generate_twap_updated(
    pool_id: str,
    twap_price: int,
    spot_price: int,
    timestamp: datetime = None
) -> Dict[str, Any]:
    """Generate TWAPUpdated event"""

    deviation = abs(spot_price - twap_price) * 10000 // twap_price if twap_price > 0 else 0

    return {
        "type": "TWAPUpdated",
        "pool_id": pool_id,
        "twap_price_a": twap_price,
        "spot_price_a": spot_price,
        "price_deviation": deviation,
        "timestamp": (timestamp or datetime.now()).isoformat()
    }

def generate_price_deviation_detected(
    pool_id: str,
    twap_price: int,
    spot_price: int,
    timestamp: datetime = None
) -> Dict[str, Any]:
    """Generate PriceDeviationDetected event"""

    deviation_bps = abs(spot_price - twap_price) * 10000 // twap_price if twap_price > 0 else 0

    return {
        "type": "PriceDeviationDetected",
        "pool_id": pool_id,
        "twap_price": twap_price,
        "spot_price": spot_price,
        "deviation_bps": deviation_bps,
        "timestamp": (timestamp or datetime.now()).isoformat()
    }

# ============================================================================
# TRANSACTION GENERATORS
# ============================================================================

def generate_normal_swap() -> Dict[str, Any]:
    """Generate normal swap transaction (60% of total)"""

    pools = [DEX_POOL_USDC_USDT, DEX_POOL_USDT_WETH, DEX_POOL_WETH_USDC]
    pool_id = random.choice(pools)
    sender = random.choice(NORMAL_USERS)

    # Normal swap amounts (small to medium)
    amount_in = random.randint(100_000_000, 5_000_000_000)  # 100 - 5000 USDC
    reserve_a = random.randint(10_000_000_000, 100_000_000_000)  # 10k - 100k
    reserve_b = random.randint(10_000_000_000, 100_000_000_000)

    timestamp = datetime.now() - timedelta(minutes=random.randint(0, 10000))

    swap_event = generate_swap_event(pool_id, sender, amount_in, reserve_a, reserve_b,
                                     timestamp=timestamp)

    return {
        "tx_digest": generate_tx_digest(),
        "checkpoint": generate_checkpoint(),
        "sender": sender,
        "timestamp_ms": int(timestamp.timestamp() * 1000),
        "execution_status": "success",
        "events": [swap_event],
        "package_id": PACKAGE_ID
    }

def generate_flash_loan_attack() -> Dict[str, Any]:
    """Generate flash loan attack transaction (10% of total)"""

    attacker = random.choice(MEV_BOTS)
    timestamp = datetime.now() - timedelta(minutes=random.randint(0, 10000))

    # Large flash loan
    loan_amount = random.randint(50_000_000_000, 500_000_000_000)  # 50k - 500k

    events = []

    # 1. Flash loan taken
    events.append(generate_flash_loan_taken(FLASH_LOAN_POOL_USDC, attacker, loan_amount, timestamp))

    # 2. Multiple swaps (arbitrage)
    num_swaps = random.randint(3, 6)
    current_amount = loan_amount
    reserve_a = random.randint(50_000_000_000, 200_000_000_000)
    reserve_b = random.randint(50_000_000_000, 200_000_000_000)

    pools = [DEX_POOL_USDC_USDT, DEX_POOL_USDT_WETH, DEX_POOL_WETH_USDC]

    for i in range(num_swaps):
        pool = pools[i % len(pools)]
        swap_amount = current_amount // (num_swaps - i)

        swap_event = generate_swap_event(
            pool, attacker, swap_amount, reserve_a, reserve_b,
            token_in=(i % 2 == 0), timestamp=timestamp
        )
        events.append(swap_event)

        # Circular trading pattern
        current_amount = swap_event["amount_out"]

    # 3. Flash loan repaid (with profit)
    repay_amount = loan_amount + (loan_amount * random.randint(1, 5)) // 100  # 1-5% profit
    events.append(generate_flash_loan_repaid(FLASH_LOAN_POOL_USDC, attacker, loan_amount, timestamp))

    return {
        "tx_digest": generate_tx_digest(),
        "checkpoint": generate_checkpoint(),
        "sender": attacker,
        "timestamp_ms": int(timestamp.timestamp() * 1000),
        "execution_status": "success",
        "events": events,
        "package_id": PACKAGE_ID,
        "attack_type": "flash_loan"  # For testing
    }

def generate_price_manipulation() -> Dict[str, Any]:
    """Generate price manipulation transaction (8% of total)"""

    attacker = random.choice(MEV_BOTS)
    timestamp = datetime.now() - timedelta(minutes=random.randint(0, 10000))

    pool_id = random.choice([DEX_POOL_USDC_USDT, DEX_POOL_USDT_WETH])

    # Large swap (>20% of pool)
    reserve_a = random.randint(30_000_000_000, 100_000_000_000)  # 30k - 100k
    reserve_b = random.randint(30_000_000_000, 100_000_000_000)

    # Manipulative amount (20-40% of pool)
    amount_in = reserve_a * random.randint(20, 40) // 100

    events = []

    # Large swap
    swap_event = generate_swap_event(pool_id, attacker, amount_in, reserve_a, reserve_b, timestamp=timestamp)
    events.append(swap_event)

    # TWAP deviation detected
    twap_price = 1_000_000_000  # Base price
    spot_price = twap_price + (twap_price * random.randint(15, 30)) // 100  # 15-30% deviation

    events.append(generate_twap_updated(pool_id, twap_price, spot_price, timestamp))
    events.append(generate_price_deviation_detected(pool_id, twap_price, spot_price, timestamp))

    # Consecutive swaps (pump pattern)
    if random.random() < 0.5:
        for _ in range(random.randint(1, 3)):
            pump_amount = amount_in // 3
            pump_swap = generate_swap_event(pool_id, attacker, pump_amount,
                                           reserve_a, reserve_b, timestamp=timestamp)
            events.append(pump_swap)

    return {
        "tx_digest": generate_tx_digest(),
        "checkpoint": generate_checkpoint(),
        "sender": attacker,
        "timestamp_ms": int(timestamp.timestamp() * 1000),
        "execution_status": "success",
        "events": events,
        "package_id": PACKAGE_ID,
        "attack_type": "price_manipulation"
    }

def generate_sandwich_attack_sequence() -> List[Dict[str, Any]]:
    """Generate sandwich attack (3 transactions: front-run, victim, back-run)"""

    attacker = random.choice(MEV_BOTS)
    victim = random.choice(NORMAL_USERS)
    pool_id = random.choice([DEX_POOL_USDC_USDT, DEX_POOL_WETH_USDC])

    base_timestamp = datetime.now() - timedelta(minutes=random.randint(0, 10000))
    checkpoint = generate_checkpoint()

    reserve_a = random.randint(50_000_000_000, 200_000_000_000)
    reserve_b = random.randint(50_000_000_000, 200_000_000_000)

    transactions = []

    # TX 1: Front-run (Attacker buys)
    front_run_amount = random.randint(5_000_000_000, 20_000_000_000)
    front_run_swap = generate_swap_event(pool_id, attacker, front_run_amount,
                                         reserve_a, reserve_b, True, base_timestamp)

    transactions.append({
        "tx_digest": generate_tx_digest(),
        "checkpoint": checkpoint,
        "sender": attacker,
        "timestamp_ms": int(base_timestamp.timestamp() * 1000),
        "execution_status": "success",
        "events": [front_run_swap],
        "package_id": PACKAGE_ID
    })

    # Update reserves after front-run
    reserve_a += front_run_amount
    reserve_b -= front_run_swap["amount_out"]

    # TX 2: Victim transaction (5 seconds later)
    victim_timestamp = base_timestamp + timedelta(seconds=5)
    victim_amount = random.randint(20_000_000_000, 100_000_000_000)
    victim_swap = generate_swap_event(pool_id, victim, victim_amount,
                                      reserve_a, reserve_b, True, victim_timestamp)

    transactions.append({
        "tx_digest": generate_tx_digest(),
        "checkpoint": checkpoint,
        "sender": victim,
        "timestamp_ms": int(victim_timestamp.timestamp() * 1000),
        "execution_status": "success",
        "events": [victim_swap],
        "package_id": PACKAGE_ID
    })

    # Update reserves after victim
    reserve_a += victim_amount
    reserve_b -= victim_swap["amount_out"]

    # TX 3: Back-run (Attacker sells - 3 seconds later)
    back_run_timestamp = victim_timestamp + timedelta(seconds=3)
    back_run_amount = front_run_swap["amount_out"]  # Sell what was bought
    back_run_swap = generate_swap_event(pool_id, attacker, back_run_amount,
                                        reserve_b, reserve_a, False, back_run_timestamp)

    transactions.append({
        "tx_digest": generate_tx_digest(),
        "checkpoint": checkpoint,
        "sender": attacker,
        "timestamp_ms": int(back_run_timestamp.timestamp() * 1000),
        "execution_status": "success",
        "events": [back_run_swap],
        "package_id": PACKAGE_ID,
        "attack_type": "sandwich"
    })

    return transactions

def generate_liquidity_operations() -> Dict[str, Any]:
    """Generate liquidity add/remove transactions (15% of total)"""

    provider = random.choice(LP_PROVIDERS)
    pool_id = random.choice([DEX_POOL_USDC_USDT, DEX_POOL_USDT_WETH, DEX_POOL_WETH_USDC])
    timestamp = datetime.now() - timedelta(minutes=random.randint(0, 10000))

    operation = random.choice(["add", "remove"])

    amount_a = random.randint(10_000_000_000, 100_000_000_000)
    amount_b = random.randint(10_000_000_000, 100_000_000_000)
    liquidity = int((amount_a * amount_b) ** 0.5)

    event = {
        "type": "LiquidityAdded" if operation == "add" else "LiquidityRemoved",
        "pool_id": pool_id,
        "provider": provider,
        "amount_a": amount_a,
        "amount_b": amount_b,
        "liquidity_minted" if operation == "add" else "liquidity_burned": liquidity,
        "timestamp": timestamp.isoformat()
    }

    return {
        "tx_digest": generate_tx_digest(),
        "checkpoint": generate_checkpoint(),
        "sender": provider,
        "timestamp_ms": int(timestamp.timestamp() * 1000),
        "execution_status": "success",
        "events": [event],
        "package_id": PACKAGE_ID
    }

def generate_lending_operations() -> Dict[str, Any]:
    """Generate lending market transactions (4% of total)"""

    user = random.choice(NORMAL_USERS + LP_PROVIDERS)
    market_id = random.choice([MARKET_USDC, MARKET_WETH])
    timestamp = datetime.now() - timedelta(minutes=random.randint(0, 10000))

    operation = random.choice(["supply", "borrow", "repay"])

    amount = random.randint(1_000_000_000, 50_000_000_000)

    if operation == "supply":
        event = {
            "type": "SupplyEvent",
            "market_id": market_id,
            "supplier": user,
            "amount": amount,
            "c_tokens_minted": amount * 50,  # 1:50 ratio
            "exchange_rate": 50,
            "timestamp": timestamp.isoformat()
        }
    elif operation == "borrow":
        event = {
            "type": "BorrowEvent",
            "market_id": market_id,
            "borrower": user,
            "position_id": f"0x{generate_tx_digest()[:40]}",
            "borrow_amount": amount,
            "collateral_value": amount * 150 // 100,  # 150% collateralization
            "timestamp": timestamp.isoformat()
        }
    else:  # repay
        event = {
            "type": "RepayEvent",
            "market_id": market_id,
            "borrower": user,
            "position_id": f"0x{generate_tx_digest()[:40]}",
            "repay_amount": amount,
            "remaining_debt": random.randint(0, amount // 2),
            "timestamp": timestamp.isoformat()
        }

    return {
        "tx_digest": generate_tx_digest(),
        "checkpoint": generate_checkpoint(),
        "sender": user,
        "timestamp_ms": int(timestamp.timestamp() * 1000),
        "execution_status": "success",
        "events": [event],
        "package_id": PACKAGE_ID
    }

# ============================================================================
# MAIN DATA GENERATION
# ============================================================================

def generate_dataset(num_transactions: int = 1500) -> List[Dict[str, Any]]:
    """
    Generate comprehensive dataset

    Distribution:
    - 60% normal swaps
    - 10% flash loan attacks
    - 8% price manipulation
    - 5% sandwich attacks (3 txs each)
    - 15% liquidity operations
    - 2% lending operations
    """

    transactions = []

    # Calculate counts
    num_normal = int(num_transactions * 0.60)
    num_flash_loan = int(num_transactions * 0.10)
    num_price_manip = int(num_transactions * 0.08)
    num_sandwich = int(num_transactions * 0.05) // 3  # 3 txs per sandwich
    num_liquidity = int(num_transactions * 0.15)
    num_lending = int(num_transactions * 0.02)

    print(f"Generating {num_transactions} transactions...")
    print(f"  - Normal swaps: {num_normal}")
    print(f"  - Flash loan attacks: {num_flash_loan}")
    print(f"  - Price manipulations: {num_price_manip}")
    print(f"  - Sandwich attacks: {num_sandwich} (x3 = {num_sandwich * 3} txs)")
    print(f"  - Liquidity operations: {num_liquidity}")
    print(f"  - Lending operations: {num_lending}")
    print()

    # Generate normal swaps
    for _ in range(num_normal):
        transactions.append(generate_normal_swap())

    # Generate flash loan attacks
    for _ in range(num_flash_loan):
        transactions.append(generate_flash_loan_attack())

    # Generate price manipulations
    for _ in range(num_price_manip):
        transactions.append(generate_price_manipulation())

    # Generate sandwich attacks
    for _ in range(num_sandwich):
        transactions.extend(generate_sandwich_attack_sequence())

    # Generate liquidity operations
    for _ in range(num_liquidity):
        transactions.append(generate_liquidity_operations())

    # Generate lending operations
    for _ in range(num_lending):
        transactions.append(generate_lending_operations())

    # Shuffle to mix attack types
    random.shuffle(transactions)

    # Sort by timestamp for realistic ordering
    transactions.sort(key=lambda x: x["timestamp_ms"])

    return transactions

# ============================================================================
# OUTPUT
# ============================================================================

if __name__ == "__main__":
    print("=" * 80)
    print("DeFi Transaction Data Generator")
    print("=" * 80)
    print()

    # Generate dataset
    dataset = generate_dataset(1500)

    # Save to file
    output_file = "defi_transactions_1500.json"
    with open(output_file, "w") as f:
        json.dump(dataset, f, indent=2)

    print(f"✅ Generated {len(dataset)} transactions")
    print(f"📁 Saved to: {output_file}")
    print()

    # Statistics
    attack_types = {
        "flash_loan": sum(1 for tx in dataset if tx.get("attack_type") == "flash_loan"),
        "price_manipulation": sum(1 for tx in dataset if tx.get("attack_type") == "price_manipulation"),
        "sandwich": sum(1 for tx in dataset if tx.get("attack_type") == "sandwich"),
        "normal": sum(1 for tx in dataset if "attack_type" not in tx)
    }

    print("📊 Dataset Statistics:")
    print(f"  Total transactions: {len(dataset)}")
    print(f"  Flash loan attacks: {attack_types['flash_loan']}")
    print(f"  Price manipulations: {attack_types['price_manipulation']}")
    print(f"  Sandwich attacks: {attack_types['sandwich']}")
    print(f"  Normal transactions: {attack_types['normal']}")
    print()

    print("🔥 Sample attack transaction:")
    attack_sample = next((tx for tx in dataset if "attack_type" in tx), None)
    if attack_sample:
        print(json.dumps(attack_sample, indent=2)[:500] + "...")
