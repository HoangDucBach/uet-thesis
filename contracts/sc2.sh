#!/bin/bash
set -e
source .env

ATTACKER=$(sui client active-address)
USDC_TYPE="$PACKAGE_ID::usdc::USDC"
WETH_TYPE="$PACKAGE_ID::weth::WETH"

# Find a victim address (different from attacker)
VICTIM=$(sui client addresses --json | jq -r --arg active "$ATTACKER" '.addresses[] | select(.[1] != $active) | .[1]' | head -n 1)

if [ -z "$VICTIM" ]; then
    VICTIM=$(sui client new-address ed25519 --json | jq -r .address)
fi

GAS_COIN=$(sui client gas --json | jq -r '.[] | select(.mistBalance > 150000000) | .gasCoinId' | head -n 1)
if [ -z "$GAS_COIN" ]; then
    echo "Error: No gas coin with sufficient balance found."
    exit 1
fi
sui client pay-sui --input-coins $GAS_COIN --recipients $VICTIM --amounts 100000000 --gas-budget 10000000 --json

# Scenario 2: Sandwich Attack Simulation

FRONT_RUN_USDC=200000000000 # 200,000 USDC
VICTIM_USDC=50000000000  # 50,000 USDC
BACK_RUN_WETH=1900000000   # 1,900 WETH

# Front-run (Attacker)
RES_1=$(sui client ptb \
    --move-call "$PACKAGE_ID::coin_factory::mint_usdc" @$COIN_FACTORY_ID $FRONT_RUN_USDC \
    --assign usdc_in \
    --move-call "$PACKAGE_ID::simple_dex::swap_b_to_a<$WETH_TYPE,$USDC_TYPE>" \
        @$DEX_POOL_WETH_USDC usdc_in 0 \
    --assign weth_out \
    --transfer-objects "[weth_out]" @$ATTACKER \
    --gas-budget 100000000 --json)

echo "$RES_1"

# Extract WETH amount bought to sell back later
# Look for balance change of WETH for the attacker
WETH_BOUGHT=$(echo "$RES_1" | jq -r --arg owner "$ATTACKER" --arg type "$WETH_TYPE" '.balanceChanges[] | select(.owner.AddressOwner == $owner and .coinType == $type) | .amount')

# If jq fails or returns empty (e.g. if balance change format is different), fallback to a safe estimate or the hardcoded value
if [ -z "$WETH_BOUGHT" ] || [ "$WETH_BOUGHT" == "null" ]; then
    echo "Warning: Could not parse WETH bought. Using default."
    BACK_RUN_WETH=6000000000 # Fallback to ~6 WETH
else
    # Remove any leading + sign if present
    BACK_RUN_WETH=${WETH_BOUGHT#+}
    echo "Attacker bought $BACK_RUN_WETH WETH. Will sell it back."
fi

# Victim Trade (Switch to Victim)
sui client switch --address $VICTIM

# Check if victim has gas, if not try to fund again or warn
VICTIM_GAS=$(sui client gas --json | jq -r '.[0].mistBalance')
if [ -z "$VICTIM_GAS" ] || [ "$VICTIM_GAS" -lt 10000000 ]; then
    echo "Victim has insufficient gas. Attempting to fund..."
    sui client switch --address $ATTACKER
    GAS_COIN=$(sui client gas --json | jq -r '.[] | select(.mistBalance > 150000000) | .gasCoinId' | head -n 1)
    sui client pay-sui --input-coins $GAS_COIN --recipients $VICTIM --amounts 100000000 --gas-budget 10000000 --json
    sui client switch --address $VICTIM
fi

sui client ptb \
    --move-call "$PACKAGE_ID::coin_factory::mint_usdc" @$COIN_FACTORY_ID $VICTIM_USDC \
    --assign usdc_in \
    --move-call "$PACKAGE_ID::simple_dex::swap_b_to_a<$WETH_TYPE,$USDC_TYPE>" \
        @$DEX_POOL_WETH_USDC usdc_in 0 \
    --assign weth_out \
    --transfer-objects "[weth_out]" @$VICTIM \
    --gas-budget 100000000 --json

# Back-run (Switch back to Attacker)
sui client switch --address $ATTACKER

sui client ptb \
    --move-call "$PACKAGE_ID::coin_factory::mint_weth" @$COIN_FACTORY_ID $BACK_RUN_WETH \
    --assign weth_in \
    --move-call "$PACKAGE_ID::simple_dex::swap_a_to_b<$WETH_TYPE,$USDC_TYPE>" \
        @$DEX_POOL_WETH_USDC weth_in 0 \
    --assign usdc_out \
    --transfer-objects "[usdc_out]" @$ATTACKER \
    --gas-budget 100000000 --json
