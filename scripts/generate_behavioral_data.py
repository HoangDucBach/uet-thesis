#!/usr/bin/env python3
"""
DeFi Attack Data Generator v2
Based on real-world patterns from Chainalysis, Elliptic, and academic research.

Patterns:
1. Wash Trading (Self + Coordinated) - Victor & Weintraud methodology
2. Peel Chain Money Laundering - Chainalysis patterns
3. Sandwich Attacks - MEV extraction
4. Coordinated Pump - Volume manipulation
5. Normal Trading - Baseline legitimate activity
"""

import json
import random
import hashlib
from datetime import datetime, timedelta
from typing import List, Dict, Tuple
from dataclasses import dataclass, asdict

# Configuration
PACKAGE_ID = "0x0a78ed73edcaca699f8ffead05a9626aadd6edb30d49523574c8016806b0530e"

# Real pools from Sui network
POOLS = [
    "0xcd7c37355a73ace339b03847c860a43797a06cd675f051831562e39e2d4ba14e",  # DEX_POOL_USDC_USDT
    "0xd8c8d2282cc2b2990b4e39709684ef9cfd9fe18a56167d0e32134d90d1e6892b",  # FLASH_LOAN_POOL_USDC
    "0x14a22a54906f8efb546c5f01bcf0220cebbf3b36fc6a124edcefe01977eaed84",  # DEX_POOL_USDT_WETH
    "0x9e8326e5cf8b5ccb07f9c8bd39f4a9f95bc7b51f8ea8d70fdea0eb3f4ad92314",  # DEX_POOL_WETH_USDC
]

# Generate additional fake pools in correct Sui hex format (64 chars)
def generate_fake_pool(seed: str) -> str:
    """Generate fake pool ID in Sui hex format"""
    h = hashlib.sha256(seed.encode()).hexdigest()
    return f"0x{h[:64]}"

# Add fake pools for variety
FAKE_POOLS = [
    generate_fake_pool("sui_usdc_pool_1"),
    generate_fake_pool("sui_usdt_pool_1"),
    generate_fake_pool("usdc_weth_pool_1"),
]

POOLS.extend(FAKE_POOLS)

TOKENS = {
    "SUI": "0x2::sui::SUI",
    "USDC": "0xc8da7f40fd720b6b453e4c89c5aaa0a112f734a6db3a8e0a7a547f695d04945d",  # USDC_ID
    "USDT": "0xe3bcd755755ecac83bc682861282ed3b328b7c7ceadb817d481f43920b5ca37a",  # USDT_ID
    "WETH": "0x7365f07be9e0724d950d230a9dc2bddb93c512184601ef1e4c1f7250a2210a53",  # WETH_ID
}

# Global time tracker
current_time = datetime(2025, 12, 7, 10, 0, 0)

def advance_time(seconds: int):
    global current_time
    current_time += timedelta(seconds=seconds)

def generate_address(seed: str = None) -> str:
    if seed:
        h = hashlib.sha256(seed.encode()).hexdigest()
    else:
        h = hashlib.sha256(str(random.random()).encode()).hexdigest()
    return f"0x{h[:64]}"

def generate_tx_digest() -> str:
    return hashlib.sha256(str(random.random()).encode()).hexdigest()[:64]

def create_transaction(
    sender: str,
    pool_id: str,
    amount_in: int,
    direction: str = "swap_a_to_b",
    price_impact: int = None
) -> Dict:
    """Create a single DEX transaction"""
    # Price impact based on amount (larger = more impact)
    if price_impact is None:
        base_impact = int(amount_in * 0.003)  # 0.3% base
        price_impact = base_impact + random.randint(-base_impact//10, base_impact//10)
    
    # Amount out with slippage
    slippage = random.uniform(0.001, 0.005)
    amount_out = int(amount_in * (1 - slippage))
    
    return {
        "tx_digest": generate_tx_digest(),
        "timestamp_ms": current_time.isoformat() + "Z",
        "sender": sender,
        "gas_used": random.randint(1000000, 5000000),
        "modules": ["simple_dex"],
        "functions": [direction],
        "events": [{
            "type": f"{PACKAGE_ID}::simple_dex::SwapExecuted",
            "package": PACKAGE_ID,
            "module": "simple_dex",
            "sender": sender,
            "event_data": {
                "pool_id": pool_id,
                "sender": sender,
                "amount_in": amount_in,
                "amount_out": amount_out,
                "token_in": "a_to_b" in direction,
                "price_impact": price_impact
            }
        }]
    }


# =============================================================================
# Pattern 1: Wash Trading (Self-trades and Coordinated)
# =============================================================================

def generate_self_wash_trading(num_cycles: int = 15) -> List[Dict]:
    """
    Self wash trading: Single address alternating buy/sell
    
    Detection signals:
    - Same sender doing both directions
    - Near-zero net position change
    - Uniform amounts (low CV)
    - Tight time clustering
    """
    txs = []
    sender = generate_address("self_wash_trader")
    pool = random.choice(POOLS[:3])  # Use liquid pools
    
    base_amount = random.randint(2_000_000_000, 5_000_000_000)
    
    for i in range(num_cycles):
        # Buy
        amount = base_amount + random.randint(-base_amount//20, base_amount//20)  # 5% variance
        txs.append(create_transaction(sender, pool, amount, "swap_a_to_b"))
        advance_time(random.randint(10, 45))
        
        # Sell (similar amount)
        amount = base_amount + random.randint(-base_amount//20, base_amount//20)
        txs.append(create_transaction(sender, pool, amount, "swap_b_to_a"))
        advance_time(random.randint(10, 45))
    
    return txs

def generate_coordinated_wash_trading(num_pairs: int = 3, txs_per_pair: int = 10) -> List[Dict]:
    """
    Coordinated wash trading: Multiple addresses working together
    
    Pattern from Victor & Weintraud (WWW '21):
    - Forms closed cycles in transaction graph
    - Net position change = 0 for the group
    - Sequential timing
    """
    txs = []
    pool = random.choice(POOLS[:3])
    
    for pair_idx in range(num_pairs):
        addr1 = generate_address(f"coord_wash_a_{pair_idx}")
        addr2 = generate_address(f"coord_wash_b_{pair_idx}")
        
        base_amount = random.randint(3_000_000_000, 8_000_000_000)
        
        for i in range(txs_per_pair):
            # Address 1 buys
            amount = base_amount + random.randint(-base_amount//15, base_amount//15)
            txs.append(create_transaction(addr1, pool, amount, "swap_a_to_b"))
            advance_time(random.randint(15, 40))
            
            # Address 2 sells (completing the cycle)
            amount = base_amount + random.randint(-base_amount//15, base_amount//15)
            txs.append(create_transaction(addr2, pool, amount, "swap_b_to_a"))
            advance_time(random.randint(15, 40))
        
        advance_time(random.randint(60, 180))  # Gap between pairs
    
    return txs


# =============================================================================
# Pattern 2: Peel Chain Money Laundering
# =============================================================================

def generate_peel_chain(chain_length: int = 6, initial_amount: int = None) -> List[Dict]:
    """
    Peel chain pattern from Chainalysis research:
    - Large initial amount
    - Each hop "peels off" 5-25% of remaining funds
    - Amounts decrease at each step
    - Different address each hop
    - Uses multiple pools to obfuscate
    
    Real example: Bitfinex hack laundering used 30+ hops
    """
    txs = []
    
    if initial_amount is None:
        initial_amount = random.randint(80_000_000_000, 150_000_000_000)  # Large initial
    
    amount = initial_amount
    
    for i in range(chain_length):
        sender = generate_address(f"peel_{i}_{random.randint(1000,9999)}")
        pool = random.choice(POOLS)  # Different pools
        
        # Peel off 5-25%
        peel_ratio = random.uniform(0.05, 0.25)
        peel_amount = int(amount * peel_ratio)
        remaining = amount - peel_amount
        
        # Transaction with remaining funds (continuing the chain)
        txs.append(create_transaction(sender, pool, remaining, "swap_a_to_b"))
        amount = remaining * random.uniform(0.98, 0.995)  # Small fee loss
        
        # Time between hops: 2-8 minutes (realistic for manual/scripted laundering)
        advance_time(random.randint(120, 480))
    
    return txs

def generate_layering_activity(num_swaps: int = 8) -> List[Dict]:
    """
    Layering: Same address using multiple pools/tokens to obfuscate
    
    Pattern: A → B → C → D conversions through different pools
    """
    txs = []
    sender = generate_address("layering_actor")
    
    amount = random.randint(20_000_000_000, 50_000_000_000)
    
    for i in range(num_swaps):
        pool = POOLS[i % len(POOLS)]  # Rotate through pools
        direction = "swap_a_to_b" if i % 2 == 0 else "swap_b_to_a"
        
        txs.append(create_transaction(sender, pool, amount, direction))
        amount = int(amount * random.uniform(0.985, 0.995))  # Fees/slippage
        advance_time(random.randint(30, 120))
    
    return txs


# =============================================================================
# Pattern 3: Sandwich Attacks (MEV)
# =============================================================================

def generate_sandwich_attack() -> List[Dict]:
    """
    Sandwich attack pattern:
    1. Attacker front-runs victim's large swap (push price)
    2. Victim's swap executes at worse price
    3. Attacker back-runs (profit from price movement)
    
    Time constraint: All within ~30 seconds (same block or consecutive)
    """
    txs = []
    
    attacker = generate_address("sandwich_attacker")
    victim = generate_address("sandwich_victim")
    pool = random.choice(POOLS[:3])  # Liquid pool
    
    # Front-run: Attacker buys to push price up
    front_amount = random.randint(5_000_000_000, 15_000_000_000)
    txs.append(create_transaction(attacker, pool, front_amount, "swap_a_to_b", 
                                   price_impact=int(front_amount * 0.005)))
    advance_time(random.randint(2, 5))
    
    # Victim's transaction (larger, gets worse price)
    victim_amount = random.randint(10_000_000_000, 30_000_000_000)
    txs.append(create_transaction(victim, pool, victim_amount, "swap_a_to_b",
                                   price_impact=int(victim_amount * 0.008)))  # Higher impact
    advance_time(random.randint(2, 5))
    
    # Back-run: Attacker sells for profit
    back_amount = int(front_amount * 1.02)  # Slightly more due to price increase
    txs.append(create_transaction(attacker, pool, back_amount, "swap_b_to_a",
                                   price_impact=int(back_amount * 0.004)))
    advance_time(random.randint(30, 60))
    
    return txs


# =============================================================================
# Pattern 4: Coordinated Pump
# =============================================================================

def generate_coordinated_pump(num_addresses: int = 5, txs_per_address: int = 4) -> List[Dict]:
    """
    Coordinated pump pattern:
    - Multiple addresses buy aggressively in short window
    - Creates volume spike and price increase
    - Amounts relatively similar (coordination signal)
    """
    txs = []
    pool = random.choice(POOLS[-2:])  # Target less liquid pools
    
    addresses = [generate_address(f"pump_{i}") for i in range(num_addresses)]
    base_amount = random.randint(5_000_000_000, 12_000_000_000)
    
    # All addresses buy in rapid succession
    for round_idx in range(txs_per_address):
        random.shuffle(addresses)  # Randomize order each round
        for addr in addresses:
            amount = base_amount + random.randint(-base_amount//10, base_amount//10)
            txs.append(create_transaction(addr, pool, amount, "swap_a_to_b",
                                          price_impact=int(amount * 0.01)))  # High impact
            advance_time(random.randint(5, 20))
        advance_time(random.randint(30, 90))
    
    return txs


# =============================================================================
# Pattern 5: Normal Trading (Baseline)
# =============================================================================

def generate_normal_trade() -> Dict:
    """Single legitimate trade with natural variance"""
    sender = generate_address()
    pool = random.choice(POOLS)
    
    # Pareto-like distribution for amounts (many small, few large)
    amount = int(random.paretovariate(1.5) * 500_000_000)
    amount = min(amount, 100_000_000_000)  # Cap at 100B
    amount = max(amount, 100_000_000)  # Min 100M
    
    direction = random.choice(["swap_a_to_b", "swap_b_to_a"])
    
    return create_transaction(sender, pool, amount, direction)

def generate_normal_trading_batch(count: int) -> List[Dict]:
    """Generate batch of normal trades with natural time distribution"""
    txs = []
    for _ in range(count):
        txs.append(generate_normal_trade())
        # Exponential inter-arrival times
        advance_time(int(random.expovariate(1/30) + 5))  # Avg 35 sec between trades
    return txs


# =============================================================================
# Pattern 6: Benford's Law Violating Data
# =============================================================================

def generate_benford_violation_trades(count: int = 50) -> List[Dict]:
    """
    Generate trades that violate Benford's Law
    Signal for automated/fake trading
    
    Real trades follow Benford's: ~30% start with 1, ~18% with 2, etc.
    Fake trades often cluster at round numbers
    """
    txs = []
    sender = generate_address("benford_violator")
    pool = random.choice(POOLS)
    
    # Cluster amounts at round numbers (violation pattern)
    round_amounts = [1_000_000_000, 2_000_000_000, 5_000_000_000, 
                    10_000_000_000, 20_000_000_000, 50_000_000_000]
    
    for _ in range(count):
        base = random.choice(round_amounts)
        # Small variance around round number
        amount = base + random.randint(-base//100, base//100)
        direction = random.choice(["swap_a_to_b", "swap_b_to_a"])
        txs.append(create_transaction(sender, pool, amount, direction))
        advance_time(random.randint(20, 60))
    
    return txs


# =============================================================================
# Main Generator
# =============================================================================

def generate_dataset(total_txs: int = 2000) -> List[Dict]:
    """
    Generate mixed dataset with realistic attack patterns
    
    Distribution:
    - 50% Normal trading
    - 12% Self wash trading
    - 10% Coordinated wash trading
    - 8% Peel chain laundering
    - 5% Layering
    - 8% Sandwich attacks
    - 5% Coordinated pump
    - 2% Benford violations
    """
    global current_time
    current_time = datetime(2025, 12, 7, 10, 0, 0)
    
    all_txs = []
    
    # Normal trading (50%)
    print("Generating normal trading...")
    all_txs.extend(generate_normal_trading_batch(int(total_txs * 0.50)))
    
    # Self wash trading (12%)
    print("Generating self wash trading...")
    for _ in range(int(total_txs * 0.12 / 30)):
        advance_time(random.randint(300, 900))
        all_txs.extend(generate_self_wash_trading(num_cycles=15))
    
    # Coordinated wash trading (10%)
    print("Generating coordinated wash trading...")
    for _ in range(int(total_txs * 0.10 / 60)):
        advance_time(random.randint(300, 900))
        all_txs.extend(generate_coordinated_wash_trading(num_pairs=3, txs_per_pair=10))
    
    # Peel chains (8%)
    print("Generating peel chain laundering...")
    for _ in range(int(total_txs * 0.08 / 6)):
        advance_time(random.randint(600, 1800))
        all_txs.extend(generate_peel_chain(chain_length=6))
    
    # Layering (5%)
    print("Generating layering activity...")
    for _ in range(int(total_txs * 0.05 / 8)):
        advance_time(random.randint(300, 900))
        all_txs.extend(generate_layering_activity(num_swaps=8))
    
    # Sandwich attacks (8%)
    print("Generating sandwich attacks...")
    for _ in range(int(total_txs * 0.08 / 3)):
        advance_time(random.randint(60, 300))
        all_txs.extend(generate_sandwich_attack())
    
    # Coordinated pump (5%)
    print("Generating coordinated pump...")
    for _ in range(int(total_txs * 0.05 / 20)):
        advance_time(random.randint(600, 1800))
        all_txs.extend(generate_coordinated_pump(num_addresses=5, txs_per_address=4))
    
    # Benford violations (2%)
    print("Generating Benford violations...")
    for _ in range(int(total_txs * 0.02 / 50)):
        advance_time(random.randint(300, 900))
        all_txs.extend(generate_benford_violation_trades(count=50))
    
    # Sort by timestamp
    all_txs.sort(key=lambda x: x['timestamp_ms'])
    
    print(f"\nGenerated {len(all_txs)} transactions")
    return all_txs


def print_dataset_stats(txs: List[Dict]):
    """Print summary statistics"""
    from collections import Counter
    
    senders = Counter(tx['sender'] for tx in txs)
    pools = Counter(tx['events'][0]['event_data']['pool_id'] for tx in txs)
    directions = Counter(tx['functions'][0] for tx in txs)
    
    amounts = [tx['events'][0]['event_data']['amount_in'] for tx in txs]
    
    print("\n=== Dataset Statistics ===")
    print(f"Total transactions: {len(txs)}")
    print(f"Unique senders: {len(senders)}")
    print(f"Unique pools: {len(pools)}")
    print(f"\nDirection distribution:")
    for d, c in directions.items():
        print(f"  {d}: {c} ({c/len(txs)*100:.1f}%)")
    print(f"\nAmount statistics:")
    print(f"  Min: {min(amounts):,}")
    print(f"  Max: {max(amounts):,}")
    print(f"  Avg: {sum(amounts)/len(amounts):,.0f}")
    print(f"\nTop 5 most active senders:")
    for sender, count in senders.most_common(5):
        print(f"  {sender[:16]}...: {count} txs")
    print(f"\nPool activity:")
    for pool, count in pools.most_common():
        print(f"  {pool[:30]}...: {count} txs")
    
    # Time range
    times = sorted(tx['timestamp_ms'] for tx in txs)
    print(f"\nTime range: {times[0]} to {times[-1]}")


if __name__ == "__main__":
    txs = generate_dataset(2000)
    print_dataset_stats(txs)
    
    # Save to file
    output_path = "behavioral_defi_data_2000.json"
    with open(output_path, 'w') as f:
        json.dump(txs, f, indent=2)
    print(f"\nData saved to {output_path}")
    
    # Also create NDJSON for ES bulk import
    ndjson_path = "behavioral_defi_data_2000.ndjson"
    with open(ndjson_path, 'w') as f:
        for tx in txs:
            f.write(json.dumps({"index": {"_index": "sui-transactions"}}) + "\n")
            f.write(json.dumps(tx) + "\n")
    print(f"NDJSON saved to {ndjson_path}")