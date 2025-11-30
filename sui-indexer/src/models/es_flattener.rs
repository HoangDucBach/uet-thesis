use chrono::{DateTime, Utc};
use std::collections::HashSet;
use sui_types::{
    transaction::TransactionDataAPI,
    transaction::TransactionData,
    effects::TransactionEffects,
    event::Event,
};

use super::{
    EsEffects, EsEvent, EsGas, EsMoveCall, EsObject, EsTransaction,
};

/// Flatten Sui transaction data to Elasticsearch document (type-safe)
pub struct EsFlattener;

impl EsFlattener {
    /// Flatten directly from sui_types objects - TYPE-SAFE
    pub fn flatten(
        transaction_data: &TransactionData,
        effects: &TransactionEffects,
        checkpoint_seq: i64,
        timestamp_ms: i64,
        execution_status: &str,
        tx_digest: &str,
    ) -> EsTransaction {
        let timestamp = DateTime::<Utc>::from_timestamp_millis(timestamp_ms)
            .unwrap_or_else(|| Utc::now());

        // Extract using type-safe APIs
        let mut gas = Self::extract_gas(transaction_data);
        // Fill gas used and costs from effects
        Self::fill_gas_from_effects(&mut gas, effects);
        
        let move_calls = Self::extract_move_calls(transaction_data);
        let objects = Self::extract_objects(transaction_data);
        let events = Self::extract_events(effects);
        let effects_data = Self::extract_effects(effects);

        // Flatten for aggregation
        let packages = Self::extract_packages(&move_calls);
        let modules = Self::extract_modules(&move_calls);
        let functions = Self::extract_functions(&move_calls);
        let coin_types = Self::extract_coin_types(&effects_data);

        EsTransaction {
            tx_digest: tx_digest.to_string(),
            checkpoint_sequence_number: checkpoint_seq,
            timestamp,
            sender: transaction_data.sender().to_string(),
            execution_status: execution_status.to_string(),
            gas,
            move_calls,
            objects,
            effects: effects_data,
            events,
            packages,
            modules,
            functions,
            coin_types,
        }
    }

    fn fill_gas_from_effects(gas: &mut EsGas, effects: &TransactionEffects) {
        use sui_types::effects::TransactionEffectsAPI;
        
        // Get gas cost summary from effects
        let gas_summary = effects.gas_cost_summary();
        
        // Fill gas used and costs
        gas.used = Some(gas_summary.gas_used() as i64);
        gas.computation_cost = Some(gas_summary.computation_cost as i64);
        gas.storage_cost = Some(gas_summary.storage_cost as i64);
        gas.storage_rebate = Some(gas_summary.storage_rebate as i64);
    }

    // ============================================================================
    // Extract from sui_types objects (TYPE-SAFE)
    // ============================================================================

    fn extract_gas(transaction_data: &TransactionData) -> EsGas {
        let gas_data = transaction_data.gas_data();
        
        EsGas {
            owner: gas_data.owner.to_string(),
            budget: gas_data.budget as i64,
            price: gas_data.price as i64,
            used: None, // Will be filled from effects
            computation_cost: None,
            storage_cost: None,
            storage_rebate: None,
        }
    }

    fn extract_move_calls(transaction_data: &TransactionData) -> Vec<EsMoveCall> {
        let mut calls = Vec::new();

        // Get transaction kind
        if let sui_types::transaction::TransactionKind::ProgrammableTransaction(pt) = transaction_data.kind() {
            // Iterate through commands in the programmable transaction
            for cmd in pt.commands.iter() {
                if let sui_types::transaction::Command::MoveCall(move_call) = cmd {
                    let package = move_call.package.to_string();
                    let module = move_call.module.to_string();
                    let function = move_call.function.to_string();
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

    fn extract_objects(transaction_data: &TransactionData) -> Vec<EsObject> {
        let mut objects = Vec::new();

        if let sui_types::transaction::TransactionKind::ProgrammableTransaction(pt) = transaction_data.kind() {
            // Extract from inputs
            for input in pt.inputs.iter() {
                match input {
                    sui_types::transaction::CallArg::Object(obj_arg) => {
                        // ObjectArg variants: ImmOrOwnedObject(ObjectRef), SharedObject { id, .. }, Receiving(ObjectRef)
                        // ObjectRef is a tuple (ObjectID, SequenceNumber, ObjectDigest)
                        let object_id = match obj_arg {
                            sui_types::transaction::ObjectArg::ImmOrOwnedObject((id, _, _)) => *id,
                            sui_types::transaction::ObjectArg::SharedObject { id, .. } => *id,
                            sui_types::transaction::ObjectArg::Receiving((id, _, _)) => *id,
                        };
                        objects.push(EsObject {
                            object_id: object_id.to_string(),
                            object_type: "input".to_string(),
                            owner: None,
                        });
                    }
                    _ => {}
                }
            }
        }

        objects
    }

    fn extract_events(_effects: &TransactionEffects) -> Vec<EsEvent> {
        // NOTE: TransactionEffects only has events_digest(), not the actual events
        // Events are stored separately in TransactionEvents and need to be fetched separately
        // from the checkpoint or parsed from raw_effects JSON if needed
        // For now, return empty vector - events can be added later if needed
        Vec::new()
    }

    fn extract_effects(effects: &TransactionEffects) -> EsEffects {
        use sui_types::effects::TransactionEffectsAPI;
        
        // Count object changes using API
        let created_count = effects.created().len() as i32;
        let mutated_count = effects.mutated().len() as i32;
        let deleted_count = effects.deleted().len() as i32;

        // NOTE: TransactionEffectsAPI doesn't have balance_changes() method
        // Balance changes need to be calculated from object changes or parsed from raw_effects JSON
        // For now, return empty vector - balance_changes can be added later if needed
        let balance_changes = Vec::new();

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
