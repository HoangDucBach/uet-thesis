use chrono::{DateTime, Utc};
use std::collections::HashSet;
use sui_types::{
    transaction::TransactionDataAPI,
    transaction::TransactionData,
    effects::{TransactionEffects, TransactionEvents},
    base_types::ObjectID,
    object::Owner,
};

use super::{
    EsChangedObject, EsEffects, EsEvent, EsGas, EsMoveCall, EsObject, EsRemovedObject, EsTransaction,
};

/// Flatten Sui transaction data to Elasticsearch document (type-safe)
pub struct EsFlattener;

impl EsFlattener {
    /// Flatten directly from sui_types objects - TYPE-SAFE
    pub fn flatten(
        transaction_data: &TransactionData,
        effects: &TransactionEffects,
        events: Option<&TransactionEvents>,
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
        let events = Self::extract_events(events);
        let effects_data = Self::extract_effects(effects);

        // Flatten for aggregation
        let packages = Self::extract_packages(&move_calls);
        let modules = Self::extract_modules(&move_calls);
        let functions = Self::extract_functions(&move_calls);

        // Extract transaction kind and metadata
        let kind = transaction_data.kind().name().to_string();
        let is_system_tx = transaction_data.kind().is_system_tx();
        let is_sponsored_tx = transaction_data.is_sponsored_tx();
        let is_end_of_epoch_tx = transaction_data.kind().is_end_of_epoch_tx();

        EsTransaction {
            tx_digest: tx_digest.to_string(),
            checkpoint_sequence_number: checkpoint_seq,
            timestamp_ms: timestamp,
            sender: transaction_data.sender().to_string(),
            execution_status: execution_status.to_string(),
            kind,
            is_system_tx,
            is_sponsored_tx,
            is_end_of_epoch_tx,
            gas,
            move_calls,
            objects,
            effects: effects_data,
            events,
            packages,
            modules,
            functions,
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
                        let (object_id, object_type) = match obj_arg {
                            sui_types::transaction::ObjectArg::ImmOrOwnedObject((id, _, _)) => (*id, "ImmOrOwnedObject"),
                            sui_types::transaction::ObjectArg::SharedObject { id, .. } => (*id, "SharedObject"),
                            sui_types::transaction::ObjectArg::Receiving((id, _, _)) => (*id, "Receiving"),
                        };
                        objects.push(EsObject {
                            object_id: object_id.to_string(),
                            object_type: object_type.to_string(),
                            owner: None,
                        });
                    }
                    _ => {}
                }
            }
        }

        objects
    }

    fn extract_events(events: Option<&TransactionEvents>) -> Vec<EsEvent> {
        let mut es_events = Vec::new();
        
        if let Some(transaction_events) = events {
            // TransactionEvents has data: Vec<Event>
            for event in &transaction_events.data {
                // Event has type_: StructTag - parse to get package and module
                let event_type = event.type_.to_string();
                let package = event.type_.address.to_string();
                let module = event.type_.module.to_string();
                
                es_events.push(EsEvent {
                    event_type,
                    package,
                    module,
                    sender: event.sender.to_string(),
                });
            }
        }
        
        es_events
    }

    fn extract_effects(effects: &TransactionEffects) -> EsEffects {
        use sui_types::effects::TransactionEffectsAPI;
        use std::mem;
        use sui_types::effects::ObjectRemoveKind;
        
        // Count object changes using API
        let created_count = effects.created().len() as i32;
        let mutated_count = effects.mutated().len() as i32;
        let deleted_count = effects.deleted().len() as i32;

        // Convert all_changed_objects to serializable format
        // Get old object metadata for input state (V2 has this info)
        // old_object_metadata returns &[((ObjectID, SequenceNumber, ObjectDigest), Owner)]
        let old_metadata = effects.old_object_metadata();
        let old_owner_map: std::collections::HashMap<ObjectID, &Owner> = old_metadata
            .iter()
            .map(|((id, _, _), owner)| (*id, owner))
            .collect();

        let all_changed_objects: Vec<EsChangedObject> = effects.all_changed_objects()
            .iter()
            .map(|((object_id, version, digest), owner, write_kind)| {
                // Get input state from old_metadata if available
                // For V2, we can get old owner, but version/digest may not be available
                // object_id is &ObjectID from the tuple, dereference to get ObjectID
                let (input_version, input_digest, input_owner, input_state_type) = 
                    if let Some(old_owner) = old_owner_map.get(&*object_id) {
                        // Object existed before - we have owner but may not have version/digest
                        (None, None, Some(old_owner.to_string()), "Exist".to_string())
                    } else {
                        // Object didn't exist before (newly created)
                        (None, None, None, "NotExist".to_string())
                    };

                // Output state from current changed object
                let output_version = Some(version.value());
                let output_digest = Some(digest.to_string());
                let output_owner = Some(owner.to_string());
                
                // Convert WriteKind to clear string representation
                use sui_types::storage::WriteKind;
                let output_state_type = match write_kind {
                    WriteKind::Mutate => "Mutate".to_string(),
                    WriteKind::Create => "Create".to_string(),
                    WriteKind::Unwrap => "Unwrap".to_string(),
                };

                // Determine ID operation based on input_state_type and output
                // Since input_version is always None (old_metadata only has owner),
                // we use input_state_type to determine if object existed before
                let id_operation = if input_state_type == "NotExist" && output_version.is_some() {
                    "Created".to_string()
                } else if input_state_type == "Exist" && output_version.is_some() {
                    "Mutated".to_string()  // Object existed and was changed
                } else {
                    "None".to_string()
                };

                EsChangedObject {
                    object_id: object_id.to_string(),
                    input_version,
                    input_digest,
                    input_owner,
                    input_state_type,
                    output_version,
                    output_digest,
                    output_owner,
                    output_state_type,
                    id_operation,
                }
            })
            .collect();

        // Convert all_removed_objects to serializable format
        let all_removed_objects: Vec<EsRemovedObject> = effects.all_removed_objects()
            .iter()
            .map(|((object_id, version, digest), remove_kind)| {
                let remove_kind_str = match mem::discriminant(remove_kind) {
                    d if d == mem::discriminant(&ObjectRemoveKind::Wrap) => "Wrap",
                    d if d == mem::discriminant(&ObjectRemoveKind::Delete) => "Delete",
                    _ => "Unknown",
                };
                EsRemovedObject {
                    object_id: object_id.to_string(),
                    version: version.value(),
                    digest: digest.to_string(),
                    remove_kind: remove_kind_str.to_string(),
                }
            })
            .collect();

        EsEffects {
            created_count,
            mutated_count,
            deleted_count,
            all_changed_objects,
            all_removed_objects,
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
}
