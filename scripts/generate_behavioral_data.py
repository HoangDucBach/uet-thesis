#!/usr/bin/env python3
"""
Generate DeFi transaction data focused on BEHAVIORAL PATTERN DETECTION
For Elasticsearch time-series analysis and long-term suspicious activity detection

Focus on:
- Wash Trading (fake volume)
- Money Laundering (layering, structuring)
- Circular Fund Flows
- High Frequency Manipulation
- Coordinated Attacks
- Suspicious Address Relationships
"""

import json
import random
import hashlib
from datetime import datetime, timedelta
from typing import List, Dict, Any, Set, Tuple

# ============================================================================
# CONSTANTS
# ============================================================================

PACKAGE_ID = "0x0a78ed73edcaca699f8ffead05a9626aadd6edb30d49523574c8016806b0530e"

# Pool IDs
FLASH_LOAN_POOL_USDC = "0xd8c8d2282cc2b2990b4e39709684ef9cfd9fe18a56167d0e32134d90d1e6892b"
DEX_POOL_USDC_USDT = "0xcd7c37355a73ace339b03847c860a43797a06cd675f051831562e39e2d4ba14e"
DEX_POOL_USDT_WETH = "0x14a22a54906f8efb546c5f01bcf0220cebbf3b36fc6a124edcefe01977eaed84"
DEX_POOL_WETH_USDC = "0x9e8326e5cf8b5ccb07f9c8bd39f4a9f95bc7b51f8ea8d70fdea0eb3f4ad92314"

# ============================================================================
# ADDRESS POOLS
# ============================================================================

# Money laundering ring (connected addresses)
LAUNDERING_RING = [
    f"0x{i:040x}" for i in range(0xAA00, 0xAA15)  # 21 addresses
]

# Wash trading pairs
WASH_TRADING_PAIRS = [
    (f"0x{i:040x}", f"0x{i+1000:040x}")
    for i in range(0xBB00, 0xBB10)  # 16 addresses (8 pairs)
]

# Normal users
NORMAL_USERS = [
    f"0x{i:040x}" for i in range(0xCC00, 0xCC50)  # 80 users
]

# High frequency traders
HFT_BOTS = [
    f"0x{i:040x}" for i in range(0xDD00, 0xDD05)  # 5 HFT bots
]

# Coordinated attack group
ATTACK_GROUP = [
    f"0x{i:040x}" for i in range(0xEE00, 0xEE08)  # 8 attackers
]

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

def generate_tx_digest() -> str:
    """Generate realistic transaction digest"""
    return hashlib.sha256(random.randbytes(32)).hexdigest()

def generate_checkpoint(base: int = 10000000) -> int:
    """Generate checkpoint number"""
    return base + random.randint(0, 100000)

# ============================================================================
# BEHAVIORAL PATTERN GENERATORS
# ============================================================================

def generate_wash_trading_sequence(pair_index: int = 0, duration_minutes: int = 30) -> List[Dict[str, Any]]:
    """
    Generate wash trading pattern: two addresses trading back and forth
    to create fake volume and manipulate price discovery

    Pattern:
    - Address A sells to Address B
    - Address B sells back to Address A
    - Repeat 10-30 times within 30 minutes
    - Same amounts, minimal price impact
    - No real economic benefit, just volume
    """

    addr_a, addr_b = WASH_TRADING_PAIRS[pair_index % len(WASH_TRADING_PAIRS)]
    pool_id = random.choice([DEX_POOL_USDC_USDT, DEX_POOL_WETH_USDC])

    base_time = datetime.now() - timedelta(minutes=random.randint(0, 1000))
    base_checkpoint = generate_checkpoint()

    transactions = []
    num_rounds = random.randint(10, 30)  # 10-30 back and forth trades
    trade_amount = random.randint(1_000_000_000, 5_000_000_000)  # Fixed amount

    reserve_a = 100_000_000_000
    reserve_b = 100_000_000_000

    for i in range(num_rounds):
        # Time between trades: 1-3 minutes
        time_offset = timedelta(minutes=i * random.uniform(1, 3))
        tx_time = base_time + time_offset

        # Alternate between A→B and B→A
        sender = addr_a if i % 2 == 0 else addr_b
        receiver_hint = addr_b if i % 2 == 0 else addr_a

        # Calculate minimal output (wash trading has minimal slippage)
        amount_out = int(trade_amount * 0.997)  # Only 0.3% fee loss

        swap_event = {
            "type": "SwapExecuted",
            "pool_id": pool_id,
            "sender": sender,
            "token_in": (i % 2 == 0),
            "amount_in": trade_amount,
            "amount_out": amount_out,
            "fee_amount": int(trade_amount * 0.003),
            "reserve_a": reserve_a,
            "reserve_b": reserve_b,
            "price_impact": random.randint(10, 50),  # Very low impact (0.1-0.5%)
            "timestamp": tx_time.isoformat()
        }

        tx = {
            "tx_digest": generate_tx_digest(),
            "checkpoint": base_checkpoint + i,
            "sender": sender,
            "timestamp_ms": int(tx_time.timestamp() * 1000),
            "execution_status": "success",
            "events": [swap_event],
            "package_id": PACKAGE_ID,
            "behavior_tag": "wash_trading",
            "wash_trading_pair": f"{addr_a}:{addr_b}",
            "wash_round": i,
            "related_address": receiver_hint
        }

        transactions.append(tx)

    return transactions

def generate_money_laundering_chain(chain_length: int = 8) -> List[Dict[str, Any]]:
    """
    Generate money laundering pattern: layering through multiple addresses

    Pattern:
    - Large initial amount from source
    - Split into smaller amounts
    - Transfer through 5-10 intermediary addresses
    - Different pools and timing to obscure trail
    - Final consolidation to destination
    - Total time: 20-40 minutes
    """

    # Select addresses from laundering ring
    chain = random.sample(LAUNDERING_RING, min(chain_length, len(LAUNDERING_RING)))

    base_time = datetime.now() - timedelta(minutes=random.randint(0, 1000))
    base_checkpoint = generate_checkpoint()

    transactions = []

    # Initial large amount
    initial_amount = random.randint(100_000_000_000, 500_000_000_000)  # 100k-500k
    current_amounts = [initial_amount]

    pools = [DEX_POOL_USDC_USDT, DEX_POOL_USDT_WETH, DEX_POOL_WETH_USDC]

    for hop_index in range(len(chain) - 1):
        sender = chain[hop_index]
        receiver = chain[hop_index + 1]

        # Time between hops: 2-5 minutes
        time_offset = timedelta(minutes=(hop_index + 1) * random.uniform(2, 5))
        tx_time = base_time + time_offset

        # Possibly split amounts in middle of chain
        if hop_index == len(chain) // 2 and random.random() < 0.6:
            # Split into 2-3 smaller amounts
            num_splits = random.randint(2, 3)
            split_amounts = []
            remaining = current_amounts[0]

            for i in range(num_splits - 1):
                split = remaining // num_splits
                split_amounts.append(split)
                remaining -= split
            split_amounts.append(remaining)

            current_amounts = split_amounts

        # Process each amount
        for amount_idx, amount in enumerate(current_amounts):
            pool = pools[hop_index % len(pools)]

            # Structuring: keep amounts under threshold
            if amount > 10_000_000_000:  # If over 10k
                # Break into smaller chunks
                num_chunks = random.randint(2, 4)
                chunk_size = amount // num_chunks

                for chunk_idx in range(num_chunks):
                    chunk_time = tx_time + timedelta(seconds=chunk_idx * 30)
                    chunk_amount = chunk_size if chunk_idx < num_chunks - 1 else (amount - chunk_size * (num_chunks - 1))

                    swap_event = {
                        "type": "SwapExecuted",
                        "pool_id": pool,
                        "sender": sender,
                        "token_in": True,
                        "amount_in": chunk_amount,
                        "amount_out": int(chunk_amount * 0.99),
                        "fee_amount": int(chunk_amount * 0.01),
                        "reserve_a": 100_000_000_000,
                        "reserve_b": 100_000_000_000,
                        "price_impact": random.randint(50, 200),
                        "timestamp": chunk_time.isoformat()
                    }

                    tx = {
                        "tx_digest": generate_tx_digest(),
                        "checkpoint": base_checkpoint + hop_index * 10 + chunk_idx,
                        "sender": sender,
                        "timestamp_ms": int(chunk_time.timestamp() * 1000),
                        "execution_status": "success",
                        "events": [swap_event],
                        "package_id": PACKAGE_ID,
                        "behavior_tag": "money_laundering",
                        "laundering_hop": hop_index,
                        "chain_id": chain[0],  # Source as chain identifier
                        "structuring": True,  # Breaking into small amounts
                        "related_address": receiver
                    }

                    transactions.append(tx)
            else:
                # Single transaction
                swap_event = {
                    "type": "SwapExecuted",
                    "pool_id": pool,
                    "sender": sender,
                    "token_in": True,
                    "amount_in": amount,
                    "amount_out": int(amount * 0.99),
                    "fee_amount": int(amount * 0.01),
                    "reserve_a": 100_000_000_000,
                    "reserve_b": 100_000_000_000,
                    "price_impact": random.randint(50, 200),
                    "timestamp": tx_time.isoformat()
                }

                tx = {
                    "tx_digest": generate_tx_digest(),
                    "checkpoint": base_checkpoint + hop_index * 10,
                    "sender": sender,
                    "timestamp_ms": int(tx_time.timestamp() * 1000),
                    "execution_status": "success",
                    "events": [swap_event],
                    "package_id": PACKAGE_ID,
                    "behavior_tag": "money_laundering",
                    "laundering_hop": hop_index,
                    "chain_id": chain[0],
                    "related_address": receiver
                }

                transactions.append(tx)

    return transactions

def generate_circular_flow_pattern() -> List[Dict[str, Any]]:
    """
    Generate circular fund flow pattern: A → B → C → D → A
    Suspicious when amounts are similar and timing is coordinated

    Pattern:
    - 4-6 addresses in a circle
    - Each transfers to next within 1-2 minutes
    - Similar amounts (with small losses due to fees)
    - Returns to original address
    - Used to obscure fund origin or create confusion
    """

    # Select 4-6 addresses
    num_addresses = random.randint(4, 6)
    circle = random.sample(LAUNDERING_RING + NORMAL_USERS, num_addresses)
    circle.append(circle[0])  # Complete the circle

    base_time = datetime.now() - timedelta(minutes=random.randint(0, 1000))
    base_checkpoint = generate_checkpoint()

    transactions = []

    initial_amount = random.randint(20_000_000_000, 100_000_000_000)
    current_amount = initial_amount

    pool = random.choice([DEX_POOL_USDC_USDT, DEX_POOL_WETH_USDC])

    for hop_index in range(len(circle) - 1):
        sender = circle[hop_index]
        receiver = circle[hop_index + 1]

        # Quick succession (1-2 minutes between hops)
        time_offset = timedelta(minutes=hop_index * random.uniform(1, 2))
        tx_time = base_time + time_offset

        # Lose small amount to fees each hop
        amount_out = int(current_amount * 0.997)
        current_amount = amount_out

        swap_event = {
            "type": "SwapExecuted",
            "pool_id": pool,
            "sender": sender,
            "token_in": True,
            "amount_in": current_amount,
            "amount_out": amount_out,
            "fee_amount": int(current_amount * 0.003),
            "reserve_a": 100_000_000_000,
            "reserve_b": 100_000_000_000,
            "price_impact": random.randint(30, 100),
            "timestamp": tx_time.isoformat()
        }

        tx = {
            "tx_digest": generate_tx_digest(),
            "checkpoint": base_checkpoint + hop_index,
            "sender": sender,
            "timestamp_ms": int(tx_time.timestamp() * 1000),
            "execution_status": "success",
            "events": [swap_event],
            "package_id": PACKAGE_ID,
            "behavior_tag": "circular_flow",
            "circle_id": circle[0],  # Use first address as ID
            "hop_in_circle": hop_index,
            "related_address": receiver,
            "final_return_amount": amount_out if hop_index == len(circle) - 2 else None
        }

        transactions.append(tx)

    return transactions

def generate_hft_manipulation_burst() -> List[Dict[str, Any]]:
    """
    Generate high-frequency trading manipulation pattern

    Pattern:
    - Burst of 20-50 transactions within 2-3 minutes
    - Same address, same pool
    - Small amounts but high frequency
    - Used to manipulate price or front-run other traders
    - Creates artificial volatility
    """

    bot = random.choice(HFT_BOTS)
    pool = random.choice([DEX_POOL_USDC_USDT, DEX_POOL_WETH_USDC])

    base_time = datetime.now() - timedelta(minutes=random.randint(0, 1000))
    base_checkpoint = generate_checkpoint()

    transactions = []

    num_trades = random.randint(20, 50)
    total_duration_seconds = random.randint(120, 180)  # 2-3 minutes

    reserve_a = 100_000_000_000
    reserve_b = 100_000_000_000

    for i in range(num_trades):
        # Evenly distributed in time
        time_offset = timedelta(seconds=(total_duration_seconds / num_trades) * i)
        tx_time = base_time + time_offset

        # Small amounts
        amount = random.randint(500_000_000, 2_000_000_000)  # 500-2000

        # Alternate buy/sell
        token_in = (i % 2 == 0)

        swap_event = {
            "type": "SwapExecuted",
            "pool_id": pool,
            "sender": bot,
            "token_in": token_in,
            "amount_in": amount,
            "amount_out": int(amount * 0.997),
            "fee_amount": int(amount * 0.003),
            "reserve_a": reserve_a,
            "reserve_b": reserve_b,
            "price_impact": random.randint(5, 30),  # Minimal impact each time
            "timestamp": tx_time.isoformat()
        }

        tx = {
            "tx_digest": generate_tx_digest(),
            "checkpoint": base_checkpoint + i,
            "sender": bot,
            "timestamp_ms": int(tx_time.timestamp() * 1000),
            "execution_status": "success",
            "events": [swap_event],
            "package_id": PACKAGE_ID,
            "behavior_tag": "hft_manipulation",
            "burst_id": f"{bot}:{int(base_time.timestamp())}",
            "trade_in_burst": i,
            "total_burst_trades": num_trades
        }

        transactions.append(tx)

    return transactions

def generate_coordinated_attack() -> List[Dict[str, Any]]:
    """
    Generate coordinated attack pattern: multiple addresses working together

    Pattern:
    - 5-8 addresses from attack group
    - All trade within 5-10 minute window
    - Targeting same pool
    - Similar amounts and timing suggests coordination
    - Combined effect manipulates price significantly
    """

    # Select attackers
    num_attackers = random.randint(5, 8)
    attackers = random.sample(ATTACK_GROUP, num_attackers)

    pool = random.choice([DEX_POOL_USDC_USDT, DEX_POOL_WETH_USDC])

    base_time = datetime.now() - timedelta(minutes=random.randint(0, 1000))
    base_checkpoint = generate_checkpoint()

    transactions = []

    # Attack window: 5-10 minutes
    attack_window_minutes = random.uniform(5, 10)

    reserve_a = 100_000_000_000
    reserve_b = 100_000_000_000

    for attacker_idx, attacker in enumerate(attackers):
        # Stagger timing slightly
        time_offset = timedelta(minutes=random.uniform(0, attack_window_minutes))
        tx_time = base_time + time_offset

        # Large coordinated amounts
        amount = random.randint(10_000_000_000, 30_000_000_000)

        swap_event = {
            "type": "SwapExecuted",
            "pool_id": pool,
            "sender": attacker,
            "token_in": True,
            "amount_in": amount,
            "amount_out": int(amount * 0.95),  # Significant impact
            "fee_amount": int(amount * 0.003),
            "reserve_a": reserve_a,
            "reserve_b": reserve_b,
            "price_impact": random.randint(500, 1500),  # 5-15% each
            "timestamp": tx_time.isoformat()
        }

        tx = {
            "tx_digest": generate_tx_digest(),
            "checkpoint": base_checkpoint + attacker_idx,
            "sender": attacker,
            "timestamp_ms": int(tx_time.timestamp() * 1000),
            "execution_status": "success",
            "events": [swap_event],
            "package_id": PACKAGE_ID,
            "behavior_tag": "coordinated_attack",
            "attack_id": f"attack:{int(base_time.timestamp())}",
            "attacker_index": attacker_idx,
            "total_attackers": num_attackers,
            "target_pool": pool
        }

        transactions.append(tx)

    return transactions

def generate_layering_spoofing() -> List[Dict[str, Any]]:
    """
    Generate layering/spoofing pattern (advanced market manipulation)

    Pattern:
    - Place many small orders on one side
    - Execute one real trade on opposite side
    - Cancel the fake orders
    - Creates false impression of supply/demand
    """

    manipulator = random.choice(HFT_BOTS)
    pool = random.choice([DEX_POOL_USDC_USDT, DEX_POOL_WETH_USDC])

    base_time = datetime.now() - timedelta(minutes=random.randint(0, 1000))
    base_checkpoint = generate_checkpoint()

    transactions = []

    # Phase 1: Create fake orders (10-15 small swaps on one side)
    num_fake_orders = random.randint(10, 15)

    for i in range(num_fake_orders):
        time_offset = timedelta(seconds=i * 5)  # 5 seconds apart
        tx_time = base_time + time_offset

        small_amount = random.randint(100_000_000, 500_000_000)

        swap_event = {
            "type": "SwapExecuted",
            "pool_id": pool,
            "sender": manipulator,
            "token_in": True,
            "amount_in": small_amount,
            "amount_out": int(small_amount * 0.997),
            "fee_amount": int(small_amount * 0.003),
            "reserve_a": 100_000_000_000,
            "reserve_b": 100_000_000_000,
            "price_impact": random.randint(1, 5),
            "timestamp": tx_time.isoformat()
        }

        tx = {
            "tx_digest": generate_tx_digest(),
            "checkpoint": base_checkpoint + i,
            "sender": manipulator,
            "timestamp_ms": int(tx_time.timestamp() * 1000),
            "execution_status": "success",
            "events": [swap_event],
            "package_id": PACKAGE_ID,
            "behavior_tag": "layering_spoofing",
            "phase": "layering",
            "layer_order": i
        }

        transactions.append(tx)

    # Phase 2: Real trade (opposite direction, larger amount)
    real_trade_time = base_time + timedelta(seconds=num_fake_orders * 5 + 10)
    large_amount = random.randint(20_000_000_000, 50_000_000_000)

    real_swap = {
        "type": "SwapExecuted",
        "pool_id": pool,
        "sender": manipulator,
        "token_in": False,  # Opposite direction
        "amount_in": large_amount,
        "amount_out": int(large_amount * 0.95),
        "fee_amount": int(large_amount * 0.003),
        "reserve_a": 100_000_000_000,
        "reserve_b": 100_000_000_000,
        "price_impact": random.randint(800, 1500),
        "timestamp": real_trade_time.isoformat()
    }

    real_tx = {
        "tx_digest": generate_tx_digest(),
        "checkpoint": base_checkpoint + num_fake_orders,
        "sender": manipulator,
        "timestamp_ms": int(real_trade_time.timestamp() * 1000),
        "execution_status": "success",
        "events": [real_swap],
        "package_id": PACKAGE_ID,
        "behavior_tag": "layering_spoofing",
        "phase": "real_trade"
    }

    transactions.append(real_tx)

    return transactions

# ============================================================================
# NORMAL ACTIVITY GENERATORS
# ============================================================================

def generate_normal_swap() -> Dict[str, Any]:
    """Generate normal legitimate swap"""

    user = random.choice(NORMAL_USERS)
    pool = random.choice([DEX_POOL_USDC_USDT, DEX_POOL_USDT_WETH, DEX_POOL_WETH_USDC])

    timestamp = datetime.now() - timedelta(minutes=random.randint(0, 10000))

    amount = random.randint(500_000_000, 10_000_000_000)

    swap_event = {
        "type": "SwapExecuted",
        "pool_id": pool,
        "sender": user,
        "token_in": random.choice([True, False]),
        "amount_in": amount,
        "amount_out": int(amount * 0.997),
        "fee_amount": int(amount * 0.003),
        "reserve_a": 100_000_000_000,
        "reserve_b": 100_000_000_000,
        "price_impact": random.randint(10, 200),
        "timestamp": timestamp.isoformat()
    }

    return {
        "tx_digest": generate_tx_digest(),
        "checkpoint": generate_checkpoint(),
        "sender": user,
        "timestamp_ms": int(timestamp.timestamp() * 1000),
        "execution_status": "success",
        "events": [swap_event],
        "package_id": PACKAGE_ID,
        "behavior_tag": "normal"
    }

# ============================================================================
# MAIN DATASET GENERATION
# ============================================================================

def generate_behavioral_dataset(num_transactions: int = 2000) -> List[Dict[str, Any]]:
    """
    Generate dataset focused on behavioral patterns

    Distribution:
    - 50% Normal activity
    - 15% Wash trading (multiple sequences)
    - 12% Money laundering chains
    - 8% Circular flows
    - 7% HFT manipulation
    - 5% Coordinated attacks
    - 3% Layering/spoofing
    """

    transactions = []

    # Calculate counts
    num_normal = int(num_transactions * 0.50)
    num_wash_trading_sequences = 8  # Each sequence = 10-30 txs
    num_laundering_chains = 6  # Each chain = 8-15 txs
    num_circular_flows = 10  # Each flow = 4-6 txs
    num_hft_bursts = 4  # Each burst = 20-50 txs
    num_coordinated_attacks = 5  # Each attack = 5-8 txs
    num_layering = 3  # Each layering = 10-20 txs

    print(f"Generating {num_transactions}+ transactions with behavioral patterns...")
    print(f"  - Normal swaps: {num_normal}")
    print(f"  - Wash trading sequences: {num_wash_trading_sequences}")
    print(f"  - Money laundering chains: {num_laundering_chains}")
    print(f"  - Circular flows: {num_circular_flows}")
    print(f"  - HFT manipulation bursts: {num_hft_bursts}")
    print(f"  - Coordinated attacks: {num_coordinated_attacks}")
    print(f"  - Layering/spoofing: {num_layering}")
    print()

    # Generate normal activity
    for _ in range(num_normal):
        transactions.append(generate_normal_swap())

    # Generate behavioral patterns
    for i in range(num_wash_trading_sequences):
        transactions.extend(generate_wash_trading_sequence(i, duration_minutes=30))

    for _ in range(num_laundering_chains):
        transactions.extend(generate_money_laundering_chain(chain_length=random.randint(6, 10)))

    for _ in range(num_circular_flows):
        transactions.extend(generate_circular_flow_pattern())

    for _ in range(num_hft_bursts):
        transactions.extend(generate_hft_manipulation_burst())

    for _ in range(num_coordinated_attacks):
        transactions.extend(generate_coordinated_attack())

    for _ in range(num_layering):
        transactions.extend(generate_layering_spoofing())

    # Shuffle to mix patterns
    random.shuffle(transactions)

    # Sort by timestamp for realistic ordering
    transactions.sort(key=lambda x: x["timestamp_ms"])

    return transactions

# ============================================================================
# OUTPUT
# ============================================================================

if __name__ == "__main__":
    print("=" * 80)
    print("DeFi Behavioral Pattern Data Generator")
    print("Focus: Time-series analysis and long-term suspicious activity detection")
    print("=" * 80)
    print()

    # Generate dataset
    dataset = generate_behavioral_dataset(2000)

    # Save to file
    output_file = "defi_behavioral_patterns_2000.json"
    with open(output_file, "w") as f:
        json.dump(dataset, f, indent=2)

    print(f"✅ Generated {len(dataset)} transactions")
    print(f"📁 Saved to: {output_file}")
    print()

    # Statistics
    behavior_counts = {}
    for tx in dataset:
        tag = tx.get("behavior_tag", "unknown")
        behavior_counts[tag] = behavior_counts.get(tag, 0) + 1

    print("📊 Behavior Distribution:")
    for behavior, count in sorted(behavior_counts.items(), key=lambda x: -x[1]):
        percentage = (count / len(dataset)) * 100
        print(f"  {behavior:25s}: {count:5d} txs ({percentage:5.2f}%)")
    print()

    print("🔍 Sample Patterns:")
    print()

    # Show sample of each pattern
    for behavior in ["wash_trading", "money_laundering", "circular_flow", "hft_manipulation"]:
        sample = next((tx for tx in dataset if tx.get("behavior_tag") == behavior), None)
        if sample:
            print(f"**{behavior.upper()}:**")
            print(json.dumps(sample, indent=2)[:400] + "...\n")
