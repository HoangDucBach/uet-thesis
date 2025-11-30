use anyhow::Result;
use serde_json::Value as JsonValue;

use crate::models::{
    NewTransaction, NewMoveCall, NewTransactionObject, NewTransactionEffect,
    ExecutionStatus, ObjectType, EffectType,
};

/// Extract transaction data from Sui RPC response
pub struct SuiTransactionExtractor;

impl SuiTransactionExtractor {
    /// Extract core transaction data from JSON response
    pub fn extract_transaction(
        tx_data: &JsonValue,
        checkpoint: i64,
        timestamp_ms: i64,
    ) -> Result<NewTransaction> {
        let tx_digest = tx_data["digest"]
            .as_str()
            .ok_or_else(|| anyhow::anyhow!("Missing tx_digest"))?
            .to_string();

        let transaction = tx_data["transaction"].as_object()
            .ok_or_else(|| anyhow::anyhow!("Missing transaction object"))?;

        let data = transaction["data"].as_object()
            .ok_or_else(|| anyhow::anyhow!("Missing transaction data"))?;

        // Extract sender
        let sender = data["sender"]
            .as_str()
            .ok_or_else(|| anyhow::anyhow!("Missing sender"))?
            .to_string();

        // Extract gas data
        let gas_data = data["gasData"].as_object()
            .ok_or_else(|| anyhow::anyhow!("Missing gas data"))?;

        let gas_budget = gas_data["budget"]
            .as_str()
            .and_then(|s| s.parse::<i64>().ok())
            .ok_or_else(|| anyhow::anyhow!("Invalid gas_budget"))?;

        let gas_price = gas_data["price"]
            .as_str()
            .and_then(|s| s.parse::<i64>().ok())
            .ok_or_else(|| anyhow::anyhow!("Invalid gas_price"))?;

        let gas_owner = gas_data["owner"].as_str().map(|s| s.to_string());

        // Extract execution status and gas used from effects
        let effects = tx_data["effects"].as_object();
        let execution_status = effects
            .and_then(|e| e["status"]["status"].as_str())
            .unwrap_or("pending");

        let gas_used = effects
            .and_then(|e| e["gasUsed"]["computationCost"].as_str())
            .and_then(|s| s.parse::<i64>().ok());

        let computation_cost = effects
            .and_then(|e| e["gasUsed"]["computationCost"].as_str())
            .and_then(|s| s.parse::<i64>().ok());

        let storage_cost = effects
            .and_then(|e| e["gasUsed"]["storageCost"].as_str())
            .and_then(|s| s.parse::<i64>().ok());

        let storage_rebate = effects
            .and_then(|e| e["gasUsed"]["storageRebate"].as_str())
            .and_then(|s| s.parse::<i64>().ok());

        // Determine transaction kind
        let transaction_kind = if data.contains_key("programmableTransaction") {
            "ProgrammableTransaction"
        } else if data.contains_key("systemTransaction") {
            "SystemTransaction"
        } else {
            "Unknown"
        }.to_string();

        // Transaction classifications
        let is_system_tx = transaction_kind == "SystemTransaction";
        let is_sponsored_tx = gas_owner.is_some() && gas_owner.as_ref() != Some(&sender);
        let is_end_of_epoch_tx = false; // Extract from actual data if available

        // Count move calls and objects
        let mut total_move_calls = 0;
        let mut total_input_objects = 0;
        let mut total_shared_objects = 0;

        if let Some(prog_tx) = data["programmableTransaction"].as_object() {
            if let Some(transactions) = prog_tx["transactions"].as_array() {
                total_move_calls = transactions.iter()
                    .filter(|t| t["MoveCall"].is_object())
                    .count() as i32;
            }

            if let Some(inputs) = prog_tx["inputs"].as_array() {
                total_input_objects = inputs.len() as i32;
            }
        }

        // Extract shared objects
        if let Some(inputs) = data["inputs"].as_array() {
            total_shared_objects = inputs.iter()
                .filter(|i| i["type"].as_str() == Some("shared"))
                .count() as i32;
        }

        Ok(NewTransaction {
            tx_digest,
            checkpoint_sequence_number: checkpoint,
            sender,
            gas_owner,
            gas_budget,
            gas_used,
            gas_price,
            execution_status: execution_status.to_string(),
            timestamp_ms,
            transaction_kind,
            is_system_tx,
            is_sponsored_tx,
            is_end_of_epoch_tx,
            total_move_calls,
            total_input_objects,
            total_shared_objects,
            computation_cost,
            storage_cost,
            storage_rebate,
            expiration_epoch: None,
            raw_transaction_data: tx_data.clone(),
        })
    }

    /// Extract move calls from transaction data
    pub fn extract_move_calls(tx_data: &JsonValue) -> Result<Vec<NewMoveCall>> {
        let mut move_calls = Vec::new();

        let tx_digest = tx_data["digest"]
            .as_str()
            .ok_or_else(|| anyhow::anyhow!("Missing tx_digest"))?
            .to_string();

        let transaction = tx_data["transaction"].as_object()
            .ok_or_else(|| anyhow::anyhow!("Missing transaction object"))?;

        let data = transaction["data"].as_object()
            .ok_or_else(|| anyhow::anyhow!("Missing transaction data"))?;

        if let Some(prog_tx) = data["programmableTransaction"].as_object() {
            if let Some(transactions) = prog_tx["transactions"].as_array() {
                let mut sequence = 0;
                for tx in transactions {
                    if let Some(move_call) = tx["MoveCall"].as_object() {
                        let package_id = move_call["package"]
                            .as_str()
                            .unwrap_or("")
                            .to_string();

                        let module_name = move_call["module"]
                            .as_str()
                            .unwrap_or("")
                            .to_string();

                        let function_name = move_call["function"]
                            .as_str()
                            .unwrap_or("")
                            .to_string();

                        let type_arguments = move_call["typeArguments"]
                            .as_array()
                            .map(|arr| arr.iter()
                                .filter_map(|v| v.as_str().map(|s| s.to_string()))
                                .collect())
                            .unwrap_or_default();

                        let arguments = move_call["arguments"].clone();

                        move_calls.push(NewMoveCall {
                            tx_digest: tx_digest.clone(),
                            call_sequence: sequence,
                            package_id,
                            module_name,
                            function_name,
                            type_arguments,
                            is_entry_function: false, // Extract if available
                            arguments: Some(arguments),
                        });

                        sequence += 1;
                    }
                }
            }
        }

        Ok(move_calls)
    }

    /// Extract transaction objects
    pub fn extract_transaction_objects(tx_data: &JsonValue) -> Result<Vec<NewTransactionObject>> {
        let mut objects = Vec::new();

        let tx_digest = tx_data["digest"]
            .as_str()
            .ok_or_else(|| anyhow::anyhow!("Missing tx_digest"))?
            .to_string();

        let transaction = tx_data["transaction"].as_object()
            .ok_or_else(|| anyhow::anyhow!("Missing transaction object"))?;

        let data = transaction["data"].as_object()
            .ok_or_else(|| anyhow::anyhow!("Missing transaction data"))?;

        let mut sequence = 0;

        // Extract input objects
        if let Some(prog_tx) = data["programmableTransaction"].as_object() {
            if let Some(inputs) = prog_tx["inputs"].as_array() {
                for input in inputs {
                    if let Some(obj) = input["Object"].as_object() {
                        let object_id = obj["objectId"]
                            .as_str()
                            .unwrap_or("")
                            .to_string();

                        objects.push(NewTransactionObject {
                            tx_digest: tx_digest.clone(),
                            object_sequence: sequence,
                            object_id,
                            object_version: None,
                            object_digest: None,
                            object_type: ObjectType::Input.to_string(),
                            object_kind: None,
                            owner_type: None,
                            owner_address: None,
                        });

                        sequence += 1;
                    }
                }
            }
        }

        Ok(objects)
    }

    /// Extract transaction effects
    pub fn extract_transaction_effects(tx_data: &JsonValue) -> Result<Vec<NewTransactionEffect>> {
        let mut effects_list = Vec::new();

        let tx_digest = tx_data["digest"]
            .as_str()
            .ok_or_else(|| anyhow::anyhow!("Missing tx_digest"))?
            .to_string();

        let effects = match tx_data["effects"].as_object() {
            Some(e) => e,
            None => return Ok(effects_list),
        };

        let mut sequence = 0;

        // Extract balance changes
        if let Some(balance_changes) = effects["balanceChanges"].as_array() {
            for change in balance_changes {
                let coin_type = change["coinType"]
                    .as_str()
                    .unwrap_or("0x2::sui::SUI")
                    .to_string();

                let amount = change["amount"]
                    .as_str()
                    .and_then(|s| s.parse::<i64>().ok())
                    .unwrap_or(0);

                let owner = change["owner"]["AddressOwner"]
                    .as_str()
                    .unwrap_or("")
                    .to_string();

                effects_list.push(NewTransactionEffect {
                    tx_digest: tx_digest.clone(),
                    effect_sequence: sequence,
                    effect_type: EffectType::BalanceChange.to_string(),
                    affected_object_id: None,
                    object_type: None,
                    coin_type: Some(coin_type),
                    balance_change: Some(amount),
                    owner_address: Some(owner),
                    event_type: None,
                    event_data: None,
                });

                sequence += 1;
            }
        }

        // Extract created objects
        if let Some(created) = effects["created"].as_array() {
            for obj in created {
                let object_id = obj["reference"]["objectId"]
                    .as_str()
                    .unwrap_or("")
                    .to_string();

                effects_list.push(NewTransactionEffect {
                    tx_digest: tx_digest.clone(),
                    effect_sequence: sequence,
                    effect_type: EffectType::ObjectCreation.to_string(),
                    affected_object_id: Some(object_id),
                    object_type: None,
                    coin_type: None,
                    balance_change: None,
                    owner_address: None,
                    event_type: None,
                    event_data: None,
                });

                sequence += 1;
            }
        }

        // Extract mutated objects
        if let Some(mutated) = effects["mutated"].as_array() {
            for obj in mutated {
                let object_id = obj["reference"]["objectId"]
                    .as_str()
                    .unwrap_or("")
                    .to_string();

                effects_list.push(NewTransactionEffect {
                    tx_digest: tx_digest.clone(),
                    effect_sequence: sequence,
                    effect_type: EffectType::ObjectMutation.to_string(),
                    affected_object_id: Some(object_id),
                    object_type: None,
                    coin_type: None,
                    balance_change: None,
                    owner_address: None,
                    event_type: None,
                    event_data: None,
                });

                sequence += 1;
            }
        }

        // Extract deleted objects
        if let Some(deleted) = effects["deleted"].as_array() {
            for obj in deleted {
                let object_id = obj["objectId"]
                    .as_str()
                    .unwrap_or("")
                    .to_string();

                effects_list.push(NewTransactionEffect {
                    tx_digest: tx_digest.clone(),
                    effect_sequence: sequence,
                    effect_type: EffectType::ObjectDeletion.to_string(),
                    affected_object_id: Some(object_id),
                    object_type: None,
                    coin_type: None,
                    balance_change: None,
                    owner_address: None,
                    event_type: None,
                    event_data: None,
                });

                sequence += 1;
            }
        }

        Ok(effects_list)
    }
}
