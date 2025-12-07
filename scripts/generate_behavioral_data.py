#!/usr/bin/env python3
"""
Behavioral Pattern Data Generator for Elasticsearch Testing

Generates realistic DeFi transaction data that follows the actual sui-indexer
Elasticsearch document structure. Behavioral patterns (wash trading, money
laundering, etc.) are HIDDEN in the normal-looking transaction sequences.

NO explicit behavior tags - patterns must be detected through ELK queries
analyzing transaction sequences, amounts, timing, and address relationships.
"""

import json
import random
import hashlib
from datetime import datetime, timedelta
from typing import List, Dict, Any, Tuple
from dataclasses import dataclass
import os

# Load contract addresses from .env
def load_env_vars():
    env_path = os.path.join(os.path.dirname(__file__), '..', 'contracts', '.env')
    env_vars = {}
    if os.path.exists(env_path):
        with open(env_path, 'r') as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#') and '=' in line:
                    key, value = line.split('=', 1)
                    env_vars[key.strip()] = value.strip()
    return env_vars

ENV = load_env_vars()

# Contract addresses
PACKAGE_ID = ENV.get('PACKAGE_ID', '0x0a78ed73edcaca699f8ffead05a9626aadd6edb30d49523574c8016806b0530e')
FLASH_LOAN_POOL_USDC = ENV.get('FLASH_LOAN_POOL_USDC', '0xd8c8d2282cc2b2990b4e39709684ef9cfd9fe18a56167d0e32134d90d1e6892b')
DEX_POOL_USDC_USDT = ENV.get('DEX_POOL_USDC_USDT', '0xcd7c37355a73ace339b03847c860a43797a06cd675f051831562e39e2d4ba14e')
DEX_POOL_BTC_USDC = ENV.get('DEX_POOL_BTC_USDC', '0x123')  # Fallback if not in .env

POOLS = [
    DEX_POOL_USDC_USDT,
    DEX_POOL_BTC_USDC,
    FLASH_LOAN_POOL_USDC,
]

# Address generation
def generate_address(seed: str = None) -> str:
    """Generate a Sui address (32 bytes = 64 hex chars with 0x prefix)"""
    if seed:
        hash_obj = hashlib.sha256(seed.encode())
        return '0x' + hash_obj.hexdigest()[:64]
    else:
        return '0x' + ''.join(random.choices('0123456789abcdef', k=64))

def generate_tx_digest(seed: str = None) -> str:
    """Generate a transaction digest"""
    if seed:
        hash_obj = hashlib.sha256(seed.encode())
        return hash_obj.hexdigest()
    else:
        return hashlib.sha256(str(random.random()).encode()).hexdigest()

# Global state for realistic data
START_TIME = datetime.now() - timedelta(hours=2)
START_CHECKPOINT = 1000000
current_timestamp = START_TIME
current_checkpoint = START_CHECKPOINT

def advance_time(seconds: int):
    """Advance global timestamp"""
    global current_timestamp, current_checkpoint
    current_timestamp += timedelta(seconds=seconds)
    current_checkpoint += random.randint(1, 3)

def get_current_time_ms() -> int:
    """Get current timestamp in milliseconds"""
    return int(current_timestamp.timestamp() * 1000)

# =============================================================================
# EsTransaction Structure (matches sui-indexer)
# =============================================================================

def create_es_transaction(
    sender: str,
    events: List[Dict[str, Any]],
    move_calls: List[Dict[str, Any]],
    is_flash_loan: bool = False
) -> Dict[str, Any]:
    """
    Create an Elasticsearch transaction document matching the actual indexer structure

    Structure matches EsTransaction from sui-indexer/src/models/es_transaction.rs
    """
    tx_digest = generate_tx_digest(f"{sender}_{get_current_time_ms()}")

    # Extract packages/modules/functions from move_calls
    packages = list(set(call['package'] for call in move_calls))
    modules = list(set(call['module'] for call in move_calls))
    functions = list(set(call['function'] for call in move_calls))

    return {
        "tx_digest": tx_digest,
        "checkpoint_sequence_number": current_checkpoint,
        "timestamp_ms": current_timestamp.isoformat() + "Z",
        "sender": sender,
        "execution_status": "success",
        "kind": "ProgrammableTransaction",
        "is_system_tx": False,
        "is_sponsored_tx": False,
        "is_end_of_epoch_tx": False,

        "gas": {
            "owner": sender,
            "budget": 10000000,
            "price": 1000,
            "used": random.randint(500000, 2000000),
            "computation_cost": random.randint(300000, 1000000),
            "storage_cost": random.randint(100000, 500000),
            "storage_rebate": random.randint(50000, 200000),
        },

        "move_calls": move_calls,

        "objects": [
            {
                "object_id": random.choice(POOLS),
                "type": "SharedObject",
                "owner": None
            }
        ],

        "effects": {
            "created_count": 0,
            "mutated_count": 2 if is_flash_loan else 1,
            "deleted_count": 0,
            "all_changed_objects": [],
            "all_removed_objects": []
        },

        "events": events,

        # Flattened arrays for aggregation
        "packages": packages,
        "modules": modules,
        "functions": functions,
    }

def create_swap_event(
    pool_id: str,
    sender: str,
    amount_in: int,
    amount_out: int,
    token_in: bool = True
) -> Dict[str, Any]:
    """
    Create a SwapExecuted event with parsed event data

    Matches SwapExecuted struct from sui-indexer/src/events.rs
    NOTE: In production, event_data would be parsed from BCS
    """
    price_impact = random.randint(10, 500)  # 0.1% to 5% in basis points
    fee_amount = amount_in * 30 // 10000  # 0.3% fee

    return {
        # Basic event info (always in EsEvent)
        "type": f"{PACKAGE_ID}::simple_dex::SwapExecuted<0x2::sui::SUI, 0x2::sui::SUI>",
        "package": PACKAGE_ID,
        "module": "simple_dex",
        "sender": sender,

        # Parsed event data (NOT currently in indexer ES, but needed for behavioral detection)
        "event_data": {
            "pool_id": pool_id,
            "sender": sender,
            "token_in": token_in,
            "amount_in": amount_in,
            "amount_out": amount_out,
            "fee_amount": fee_amount,
            "reserve_a": random.randint(1000000000, 10000000000),
            "reserve_b": random.randint(1000000000, 10000000000),
            "price_impact": price_impact,
        }
    }

def create_flash_loan_event(
    pool_id: str,
    borrower: str,
    amount: int
) -> Dict[str, Any]:
    """Create a FlashLoanTaken event"""
    fee = amount * 9 // 10000  # 0.09% fee

    return {
        "type": f"{PACKAGE_ID}::flash_loan_pool::FlashLoanTaken<0x2::sui::SUI>",
        "package": PACKAGE_ID,
        "module": "flash_loan_pool",
        "sender": borrower,

        "event_data": {
            "pool_id": pool_id,
            "borrower": borrower,
            "amount": amount,
            "fee": fee,
        }
    }

# =============================================================================
# BEHAVIORAL PATTERN GENERATORS
# Patterns are HIDDEN - no explicit tags, detect via ELK queries
# =============================================================================

def generate_wash_trading_sequence(num_rounds: int = 20) -> List[Dict[str, Any]]:
    """
    Wash Trading: Two addresses trading back and forth to create fake volume

    Pattern (HIDDEN in data):
    - Same 2 addresses
    - Same pool
    - Alternating directions
    - Similar amounts (within 5%)
    - Short time windows (20-40 seconds between trades)
    - Low price impact
    - 10-30 rounds in 30 minutes

    Detection: Query for address pairs with high frequency, same pool, alternating swaps
    """
    addr1 = generate_address("wash_addr1_" + str(random.randint(1000, 9999)))
    addr2 = generate_address("wash_addr2_" + str(random.randint(1000, 9999)))
    pool = random.choice(POOLS)
    base_amount = random.randint(5_000_000_000, 20_000_000_000)  # 5-20 units

    transactions = []

    for i in range(num_rounds):
        # Alternating: addr1 -> addr2, then addr2 -> addr1
        if i % 2 == 0:
            sender = addr1
            token_in = True
        else:
            sender = addr2
            token_in = False

        # Similar amounts with small variance
        amount_in = int(base_amount * random.uniform(0.95, 1.05))
        amount_out = int(amount_in * random.uniform(0.997, 0.999))  # Minimal price impact

        event = create_swap_event(pool, sender, amount_in, amount_out, token_in)
        move_call = {
            "package": PACKAGE_ID,
            "module": "simple_dex",
            "function": "swap_a_to_b" if token_in else "swap_b_to_a",
            "full_name": f"{PACKAGE_ID}::simple_dex::{'swap_a_to_b' if token_in else 'swap_b_to_a'}"
        }

        tx = create_es_transaction(sender, [event], [move_call])
        transactions.append(tx)

        # Short time between rounds (20-40 seconds)
        advance_time(random.randint(20, 40))

    return transactions

def generate_money_laundering_chain(chain_length: int = 8) -> List[Dict[str, Any]]:
    """
    Money Laundering: Layering funds through multiple addresses to obscure origin

    Pattern (HIDDEN in data):
    - Sequential chain of swaps: A -> B -> C -> D -> ... -> Z
    - Different addresses for each hop
    - May use different pools
    - Amounts may be broken up (structuring) - amounts < 10M units
    - Time spacing: 2-5 minutes between hops
    - Total chain completes in 20-40 minutes

    Detection: Query for chains of swaps connecting addresses in sequence
    """
    # Create address chain
    addresses = [generate_address(f"launder_{i}_{random.randint(1000,9999)}")
                 for i in range(chain_length)]

    # Initial large amount
    total_amount = random.randint(50_000_000_000, 200_000_000_000)  # 50-200 units

    transactions = []

    for i in range(chain_length - 1):
        sender = addresses[i]
        receiver = addresses[i + 1]  # Next in chain

        # Structuring: break into smaller amounts if amount > 10M
        if total_amount > 10_000_000_000:
            # Split into 2-4 smaller transactions
            num_splits = random.randint(2, 4)
            split_amounts = []
            remaining = total_amount
            for j in range(num_splits - 1):
                split = int(remaining * random.uniform(0.2, 0.4))
                split_amounts.append(split)
                remaining -= split
            split_amounts.append(remaining)

            # Create multiple smaller swaps
            for split_amt in split_amounts:
                amount_in = split_amt
                amount_out = int(amount_in * random.uniform(0.995, 0.999))
                pool = random.choice(POOLS)

                event = create_swap_event(pool, sender, amount_in, amount_out)
                move_call = {
                    "package": PACKAGE_ID,
                    "module": "simple_dex",
                    "function": "swap_a_to_b",
                    "full_name": f"{PACKAGE_ID}::simple_dex::swap_a_to_b"
                }

                tx = create_es_transaction(sender, [event], [move_call])
                transactions.append(tx)

                advance_time(random.randint(10, 30))  # Short gaps between splits

            total_amount = sum(split_amounts) - int(sum(split_amounts) * 0.003)  # Account for fees
        else:
            # Single swap
            amount_in = total_amount
            amount_out = int(amount_in * random.uniform(0.995, 0.999))
            pool = random.choice(POOLS)

            event = create_swap_event(pool, sender, amount_in, amount_out)
            move_call = {
                "package": PACKAGE_ID,
                "module": "simple_dex",
                "function": "swap_a_to_b",
                "full_name": f"{PACKAGE_ID}::simple_dex::swap_a_to_b"
            }

            tx = create_es_transaction(sender, [event], [move_call])
            transactions.append(tx)

            total_amount = amount_out

        # Time between hops in chain (2-5 minutes)
        advance_time(random.randint(120, 300))

    return transactions

def generate_circular_flow() -> List[Dict[str, Any]]:
    """
    Circular Fund Flow: A -> B -> C -> D -> A

    Pattern (HIDDEN in data):
    - 4-6 addresses forming a circle
    - Each address swaps to the next
    - Returns to original address
    - Similar amounts throughout (with small losses from fees)
    - Quick succession (1-2 minutes between hops)
    - Complete circle in 5-10 minutes

    Detection: Graph analysis - detect cycles in address->address swap graph
    """
    circle_size = random.randint(4, 6)
    addresses = [generate_address(f"circle_{i}_{random.randint(1000,9999)}")
                 for i in range(circle_size)]

    amount = random.randint(10_000_000_000, 50_000_000_000)
    transactions = []

    for i in range(circle_size):
        sender = addresses[i]
        # Next address in circle (wraps around)
        next_addr = addresses[(i + 1) % circle_size]

        amount_in = amount
        amount_out = int(amount_in * random.uniform(0.996, 0.999))
        pool = random.choice(POOLS)

        event = create_swap_event(pool, sender, amount_in, amount_out)
        move_call = {
            "package": PACKAGE_ID,
            "module": "simple_dex",
            "function": "swap_a_to_b",
            "full_name": f"{PACKAGE_ID}::simple_dex::swap_a_to_b"
        }

        tx = create_es_transaction(sender, [event], [move_call])
        transactions.append(tx)

        amount = amount_out  # Amount for next hop
        advance_time(random.randint(60, 120))  # 1-2 minutes between hops

    return transactions

def generate_hft_manipulation_burst() -> List[Dict[str, Any]]:
    """
    High-Frequency Trading Manipulation: Rapid burst of trades

    Pattern (HIDDEN in data):
    - Single address
    - Same pool
    - 20-50 transactions in 2-3 minutes
    - Small amounts per trade
    - Alternating directions (buy/sell)
    - Used to manipulate price or front-run

    Detection: Query for high transaction frequency from single address + pool
    """
    attacker = generate_address(f"hft_{random.randint(1000,9999)}")
    pool = random.choice(POOLS)
    num_trades = random.randint(20, 50)
    base_amount = random.randint(1_000_000_000, 5_000_000_000)  # Small amounts

    transactions = []

    for i in range(num_trades):
        token_in = (i % 2 == 0)  # Alternating directions
        amount_in = int(base_amount * random.uniform(0.9, 1.1))
        amount_out = int(amount_in * random.uniform(0.995, 0.999))

        event = create_swap_event(pool, attacker, amount_in, amount_out, token_in)
        move_call = {
            "package": PACKAGE_ID,
            "module": "simple_dex",
            "function": "swap_a_to_b" if token_in else "swap_b_to_a",
            "full_name": f"{PACKAGE_ID}::simple_dex::{'swap_a_to_b' if token_in else 'swap_b_to_a'}"
        }

        tx = create_es_transaction(attacker, [event], [move_call])
        transactions.append(tx)

        # Very short time between trades (2-10 seconds)
        advance_time(random.randint(2, 10))

    return transactions

def generate_coordinated_attack() -> List[Dict[str, Any]]:
    """
    Coordinated Attack: Multiple addresses attacking same pool simultaneously

    Pattern (HIDDEN in data):
    - 5-8 different addresses
    - Same pool
    - Same time window (within 5-10 minutes)
    - Similar transaction types
    - May be sandwich attack or coordinated drain

    Detection: Query for multiple addresses + same pool + tight time window
    """
    num_attackers = random.randint(5, 8)
    attackers = [generate_address(f"coord_{i}_{random.randint(1000,9999)}")
                 for i in range(num_attackers)]
    pool = random.choice(POOLS)

    transactions = []

    for attacker in attackers:
        # Each attacker does 1-3 swaps
        num_swaps = random.randint(1, 3)
        for _ in range(num_swaps):
            amount_in = random.randint(10_000_000_000, 50_000_000_000)
            amount_out = int(amount_in * random.uniform(0.990, 0.999))

            event = create_swap_event(pool, attacker, amount_in, amount_out)
            move_call = {
                "package": PACKAGE_ID,
                "module": "simple_dex",
                "function": "swap_a_to_b",
                "full_name": f"{PACKAGE_ID}::simple_dex::swap_a_to_b"
            }

            tx = create_es_transaction(attacker, [event], [move_call])
            transactions.append(tx)

            # Very short time gaps (10-60 seconds)
            advance_time(random.randint(10, 60))

    return transactions

def generate_normal_swap() -> Dict[str, Any]:
    """Generate a normal, legitimate swap transaction"""
    sender = generate_address(f"normal_{random.randint(1000, 99999)}")
    pool = random.choice(POOLS)
    amount_in = random.randint(1_000_000_000, 100_000_000_000)
    amount_out = int(amount_in * random.uniform(0.990, 0.998))

    event = create_swap_event(pool, sender, amount_in, amount_out)
    move_call = {
        "package": PACKAGE_ID,
        "module": "simple_dex",
        "function": "swap_a_to_b",
        "full_name": f"{PACKAGE_ID}::simple_dex::swap_a_to_b"
    }

    return create_es_transaction(sender, [event], [move_call])

def generate_normal_flash_loan() -> Dict[str, Any]:
    """Generate a normal flash loan transaction"""
    borrower = generate_address(f"flashloan_{random.randint(1000, 99999)}")
    pool = FLASH_LOAN_POOL_USDC
    amount = random.randint(10_000_000_000, 500_000_000_000)

    fl_event = create_flash_loan_event(pool, borrower, amount)
    move_calls = [
        {
            "package": PACKAGE_ID,
            "module": "flash_loan_pool",
            "function": "borrow",
            "full_name": f"{PACKAGE_ID}::flash_loan_pool::borrow"
        },
        {
            "package": PACKAGE_ID,
            "module": "flash_loan_pool",
            "function": "repay",
            "full_name": f"{PACKAGE_ID}::flash_loan_pool::repay"
        }
    ]

    return create_es_transaction(borrower, [fl_event], move_calls, is_flash_loan=True)

# =============================================================================
# MAIN DATA GENERATION
# =============================================================================

def generate_behavioral_dataset(total_txs: int = 2000) -> List[Dict[str, Any]]:
    """
    Generate a realistic dataset with behavioral patterns hidden in normal-looking data

    Distribution:
    - 15% Wash Trading (300 txs in ~15 sequences)
    - 10% Money Laundering (200 txs in ~25 chains)
    - 8% Circular Flows (160 txs in ~35 circles)
    - 7% HFT Manipulation (140 txs in ~5 bursts)
    - 5% Coordinated Attacks (100 txs in ~10 attacks)
    - 55% Normal Activity (1100 txs)
    """
    print(f"🔧 Generating {total_txs} transactions with hidden behavioral patterns...")

    all_transactions = []

    # Wash Trading: ~15% (15 sequences of 20 trades each = 300 txs)
    print("  📊 Generating wash trading patterns (hidden)...")
    num_wash_sequences = int(total_txs * 0.15 / 20)
    for i in range(num_wash_sequences):
        all_transactions.extend(generate_wash_trading_sequence(random.randint(15, 25)))
        # Random gap before next sequence
        advance_time(random.randint(300, 900))

    # Money Laundering: ~10% (25 chains of 8 hops each = 200 txs)
    print("  💰 Generating money laundering chains (hidden)...")
    num_laundering_chains = int(total_txs * 0.10 / 8)
    for i in range(num_laundering_chains):
        all_transactions.extend(generate_money_laundering_chain(random.randint(6, 10)))
        advance_time(random.randint(600, 1200))

    # Circular Flows: ~8% (35 circles of ~4.5 txs each = 160 txs)
    print("  ⭕ Generating circular flow patterns (hidden)...")
    num_circles = int(total_txs * 0.08 / 4.5)
    for i in range(num_circles):
        all_transactions.extend(generate_circular_flow())
        advance_time(random.randint(300, 900))

    # HFT Manipulation: ~7% (5 bursts of ~28 txs each = 140 txs)
    print("  ⚡ Generating HFT manipulation bursts (hidden)...")
    num_bursts = int(total_txs * 0.07 / 28)
    for i in range(num_bursts):
        all_transactions.extend(generate_hft_manipulation_burst())
        advance_time(random.randint(1200, 2400))

    # Coordinated Attacks: ~5% (10 attacks of ~10 txs each = 100 txs)
    print("  🎯 Generating coordinated attack patterns (hidden)...")
    num_attacks = int(total_txs * 0.05 / 10)
    for i in range(num_attacks):
        all_transactions.extend(generate_coordinated_attack())
        advance_time(random.randint(1200, 2400))

    # Normal Activity: Fill remaining to reach total_txs
    num_normal = total_txs - len(all_transactions)
    print(f"  ✅ Generating {num_normal} normal transactions...")
    for i in range(num_normal):
        if random.random() < 0.1:  # 10% flash loans
            all_transactions.append(generate_normal_flash_loan())
        else:  # 90% swaps
            all_transactions.append(generate_normal_swap())

        # Random time gaps (30 seconds to 5 minutes)
        advance_time(random.randint(30, 300))

    # Sort by timestamp to mix behavioral patterns with normal activity
    all_transactions.sort(key=lambda tx: tx['timestamp_ms'])

    print(f"\n✅ Generated {len(all_transactions)} total transactions")
    print(f"   Time range: {all_transactions[0]['timestamp_ms']} to {all_transactions[-1]['timestamp_ms']}")
    print(f"   Checkpoint range: {all_transactions[0]['checkpoint_sequence_number']} to {all_transactions[-1]['checkpoint_sequence_number']}")
    print("\n⚠️  NOTE: Behavioral patterns are HIDDEN in normal-looking data")
    print("   Use Elasticsearch queries to detect patterns based on:")
    print("   - Address relationships and frequency")
    print("   - Time windows and clustering")
    print("   - Amount patterns and structuring")
    print("   - Pool targeting and coordination")

    return all_transactions

if __name__ == "__main__":
    # Generate 2000+ transactions
    transactions = generate_behavioral_dataset(total_txs=2000)

    # Save to JSON file
    output_file = "behavioral_defi_data_2000.json"
    with open(output_file, 'w') as f:
        json.dump(transactions, f, indent=2)

    print(f"\n💾 Saved to: {output_file}")
    print(f"📏 File size: {os.path.getsize(output_file) / 1024 / 1024:.2f} MB")
    print(f"\n🔍 Next steps:")
    print(f"   1. Insert into Elasticsearch: ./insert_to_elasticsearch.sh {output_file}")
    print(f"   2. Run detection queries from BEHAVIORAL_QUERIES.md")
    print(f"   3. Analyze patterns in Kibana dashboards")
