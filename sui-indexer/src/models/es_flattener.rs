use chrono::{DateTime, Utc};
use serde_json::Value as JsonValue;
use std::collections::HashSet;

use super::{
    EsBalanceChange, EsEffects, EsEvent, EsGas, EsMoveCall, EsObject, EsTransaction, Transaction,
};

/// Flatten PostgreSQL Transaction (JSONB) to Elasticsearch document
pub struct EsFlattener;

impl EsFlattener {
    pub fn flatten(tx: &Transaction) -> EsTransaction {
        let timestamp = DateTime::<Utc>::from_timestamp_millis(tx.timestamp_ms)
            .unwrap_or_else(|| Utc::now());

        // Parse raw_transaction
        let gas = Self::extract_gas(&tx.raw_transaction);
        let move_calls = Self::extract_move_calls(&tx.raw_transaction);
        let objects = Self::extract_objects(&tx.raw_transaction);
        let events = Self::extract_events(&tx.raw_effects);
        let effects = Self::extract_effects(&tx.raw_effects);

        // Flatten for aggregation
        let packages = Self::extract_packages(&move_calls);
        let modules = Self::extract_modules(&move_calls);
        let functions = Self::extract_functions(&move_calls);
        let coin_types = Self::extract_coin_types(&effects);

        EsTransaction {
            tx_digest: tx.tx_digest.clone(),
            checkpoint_sequence_number: tx.checkpoint_sequence_number,
            timestamp,
            sender: tx.sender.clone(),
            execution_status: tx.execution_status.clone(),
            gas,
            move_calls,
            objects,
            effects,
            events,
            packages,
            modules,
            functions,
            coin_types,
        }
    }

    fn extract_gas(raw: &JsonValue) -> EsGas {
        let gas_data = &raw["transaction"]["data"]["gasData"];

        EsGas {
            owner: gas_data["owner"]
                .as_str()
                .unwrap_or("")
                .to_string(),
            budget: gas_data["budget"]
                .as_str()
                .and_then(|s| s.parse().ok())
                .unwrap_or(0),
            price: gas_data["price"]
                .as_str()
                .and_then(|s| s.parse().ok())
                .unwrap_or(0),
            used: None,
            computation_cost: None,
            storage_cost: None,
            storage_rebate: None,
        }
    }

    fn extract_move_calls(raw: &JsonValue) -> Vec<EsMoveCall> {
        let mut calls = Vec::new();

        if let Some(txs) = raw["transaction"]["data"]["programmableTransaction"]["transactions"]
            .as_array()
        {
            for tx in txs {
                if let Some(move_call) = tx["MoveCall"].as_object() {
                    let package = move_call["package"]
                        .as_str()
                        .unwrap_or("")
                        .to_string();
                    let module = move_call["module"]
                        .as_str()
                        .unwrap_or("")
                        .to_string();
                    let function = move_call["function"]
                        .as_str()
                        .unwrap_or("")
                        .to_string();

                    let full_name = format!("{}::{}::{}", package, module, function);

                    calls.push(EsMoveCall {
                        package,
                        module,
                        function,
                        full_name,
                    });
                }
            }
        }

        calls
    }

    fn extract_objects(raw: &JsonValue) -> Vec<EsObject> {
        let mut objects = Vec::new();

        // Extract from inputs
        if let Some(inputs) = raw["transaction"]["data"]["programmableTransaction"]["inputs"]
            .as_array()
        {
            for input in inputs {
                if let Some(obj) = input["Object"].as_object() {
                    objects.push(EsObject {
                        object_id: obj["objectId"]
                            .as_str()
                            .unwrap_or("")
                            .to_string(),
                        object_type: "input".to_string(),
                        owner: None,
                    });
                }
            }
        }

        objects
    }

    fn extract_events(raw_effects: &Option<JsonValue>) -> Vec<EsEvent> {
        let mut events = Vec::new();

        if let Some(effects) = raw_effects {
            if let Some(event_list) = effects["events"].as_array() {
                for event in event_list {
                    let event_type = event["type"]
                        .as_str()
                        .unwrap_or("")
                        .to_string();

                    // Parse event type (format: "package::module::EventName")
                    let parts: Vec<&str> = event_type.split("::").collect();
                    let package = parts.get(0).unwrap_or(&"").to_string();
                    let module = parts.get(1).unwrap_or(&"").to_string();

                    events.push(EsEvent {
                        event_type,
                        package,
                        module,
                        sender: event["sender"]
                            .as_str()
                            .unwrap_or("")
                            .to_string(),
                    });
                }
            }
        }

        events
    }

    fn extract_effects(raw_effects: &Option<JsonValue>) -> EsEffects {
        let mut balance_changes = Vec::new();
        let mut created_count = 0;
        let mut mutated_count = 0;
        let mut deleted_count = 0;

        if let Some(effects) = raw_effects {
            // Balance changes
            if let Some(changes) = effects["balanceChanges"].as_array() {
                for change in changes {
                    balance_changes.push(EsBalanceChange {
                        coin_type: change["coinType"]
                            .as_str()
                            .unwrap_or("0x2::sui::SUI")
                            .to_string(),
                        amount: change["amount"]
                            .as_str()
                            .and_then(|s| s.parse().ok())
                            .unwrap_or(0),
                        owner: change["owner"]["AddressOwner"]
                            .as_str()
                            .unwrap_or("")
                            .to_string(),
                    });
                }
            }

            // Count object changes
            if let Some(created) = effects["created"].as_array() {
                created_count = created.len() as i32;
            }
            if let Some(mutated) = effects["mutated"].as_array() {
                mutated_count = mutated.len() as i32;
            }
            if let Some(deleted) = effects["deleted"].as_array() {
                deleted_count = deleted.len() as i32;
            }
        }

        EsEffects {
            created_count,
            mutated_count,
            deleted_count,
            balance_changes,
        }
    }

    fn extract_packages(calls: &[EsMoveCall]) -> Vec<String> {
        calls
            .iter()
            .map(|c| c.package.clone())
            .collect::<HashSet<_>>()
            .into_iter()
            .collect()
    }

    fn extract_modules(calls: &[EsMoveCall]) -> Vec<String> {
        calls
            .iter()
            .map(|c| c.module.clone())
            .collect::<HashSet<_>>()
            .into_iter()
            .collect()
    }

    fn extract_functions(calls: &[EsMoveCall]) -> Vec<String> {
        calls
            .iter()
            .map(|c| c.function.clone())
            .collect::<HashSet<_>>()
            .into_iter()
            .collect()
    }

    fn extract_coin_types(effects: &EsEffects) -> Vec<String> {
        effects
            .balance_changes
            .iter()
            .map(|b| b.coin_type.clone())
            .collect::<HashSet<_>>()
            .into_iter()
            .collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn test_flatten_transaction() {
        let tx = Transaction {
            tx_digest: "test123".to_string(),
            checkpoint_sequence_number: 100,
            sender: "0xabc".to_string(),
            timestamp_ms: 1234567890000,
            execution_status: "success".to_string(),
            raw_transaction: json!({
                "transaction": {
                    "data": {
                        "gasData": {
                            "owner": "0xabc",
                            "budget": "1000000",
                            "price": "1000"
                        },
                        "programmableTransaction": {
                            "transactions": [{
                                "MoveCall": {
                                    "package": "0x2",
                                    "module": "coin",
                                    "function": "transfer"
                                }
                            }]
                        }
                    }
                }
            }),
            raw_effects: None,
            created_at: Utc::now(),
        };

        let es_tx = EsFlattener::flatten(&tx);

        assert_eq!(es_tx.tx_digest, "test123");
        assert_eq!(es_tx.packages.len(), 1);
        assert_eq!(es_tx.packages[0], "0x2");
    }
}
