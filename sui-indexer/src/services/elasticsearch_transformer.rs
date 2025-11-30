use anyhow::Result;

use crate::models::{
    Transaction, MoveCall, TransactionObject, TransactionEffect,
    ElasticsearchTransaction, ElasticsearchMoveCall, ElasticsearchObjectInteraction,
    ElasticsearchBalanceChange,
};

/// Transform PostgreSQL data to Elasticsearch documents
pub struct ElasticsearchTransformer;

impl ElasticsearchTransformer {
    /// Transform a full transaction with all related data to Elasticsearch document
    pub fn transform_transaction(
        transaction: &Transaction,
        move_calls: &[MoveCall],
        objects: &[TransactionObject],
        effects: &[TransactionEffect],
    ) -> Result<ElasticsearchTransaction> {
        let mut es_tx = ElasticsearchTransaction::from(transaction);

        // Add move calls
        for call in move_calls {
            es_tx.add_move_call(
                call.package_id.clone(),
                call.module_name.clone(),
                call.function_name.clone(),
                call.type_arguments.clone(),
                call.call_sequence,
            );
        }

        // Add object interactions
        for obj in objects {
            es_tx.add_object_interaction(
                obj.object_id.clone(),
                obj.object_type.clone(),
                obj.object_type.clone(), // interaction_type same as object_type
            );
        }

        // Add balance changes
        for effect in effects {
            if effect.effect_type == "balance_change" {
                if let (Some(coin_type), Some(balance_change), Some(owner_address)) = (
                    &effect.coin_type,
                    effect.balance_change,
                    &effect.owner_address,
                ) {
                    es_tx.add_balance_change(
                        coin_type.clone(),
                        balance_change,
                        owner_address.clone(),
                    );
                }
            }
        }

        Ok(es_tx)
    }

    /// Transform move calls to Elasticsearch nested structure
    pub fn transform_move_calls(move_calls: &[MoveCall]) -> Vec<ElasticsearchMoveCall> {
        move_calls
            .iter()
            .map(|call| ElasticsearchMoveCall {
                package: call.package_id.clone(),
                module: call.module_name.clone(),
                function: call.function_name.clone(),
                type_args: call.type_arguments.clone(),
                sequence: call.call_sequence,
            })
            .collect()
    }

    /// Transform object interactions to Elasticsearch nested structure
    pub fn transform_object_interactions(objects: &[TransactionObject]) -> Vec<ElasticsearchObjectInteraction> {
        objects
            .iter()
            .map(|obj| ElasticsearchObjectInteraction {
                object_id: obj.object_id.clone(),
                object_type: obj.object_type.clone(),
                interaction_type: obj.object_type.clone(),
            })
            .collect()
    }

    /// Transform balance changes to Elasticsearch nested structure
    pub fn transform_balance_changes(effects: &[TransactionEffect]) -> Vec<ElasticsearchBalanceChange> {
        effects
            .iter()
            .filter(|e| e.effect_type == "balance_change")
            .filter_map(|e| {
                match (&e.coin_type, e.balance_change, &e.owner_address) {
                    (Some(coin_type), Some(amount), Some(owner)) => Some(ElasticsearchBalanceChange {
                        coin_type: coin_type.clone(),
                        amount,
                        owner: owner.clone(),
                    }),
                    _ => None,
                }
            })
            .collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::Utc;
    use serde_json::json;

    #[test]
    fn test_transform_transaction() {
        let transaction = Transaction {
            id: Some(1),
            tx_digest: "test_digest".to_string(),
            checkpoint_sequence_number: 100,
            sender: "0x123".to_string(),
            gas_owner: None,
            gas_budget: 1000000,
            gas_used: Some(500000),
            gas_price: 1000,
            execution_status: "success".to_string(),
            timestamp_ms: 1234567890000,
            transaction_kind: "ProgrammableTransaction".to_string(),
            is_system_tx: false,
            is_sponsored_tx: false,
            is_end_of_epoch_tx: false,
            total_move_calls: 1,
            total_input_objects: 2,
            total_shared_objects: 0,
            computation_cost: Some(500000),
            storage_cost: Some(100000),
            storage_rebate: Some(50000),
            expiration_epoch: None,
            raw_transaction_data: json!({}),
            processed_at: Utc::now(),
            updated_at: None,
        };

        let move_calls = vec![
            MoveCall {
                id: Some(1),
                tx_digest: "test_digest".to_string(),
                call_sequence: 0,
                package_id: "0x2".to_string(),
                module_name: "coin".to_string(),
                function_name: "transfer".to_string(),
                type_arguments: vec!["0x2::sui::SUI".to_string()],
                is_entry_function: true,
                arguments: None,
                created_at: Utc::now(),
            }
        ];

        let result = ElasticsearchTransformer::transform_transaction(
            &transaction,
            &move_calls,
            &[],
            &[],
        );

        assert!(result.is_ok());
        let es_tx = result.unwrap();
        assert_eq!(es_tx.tx_digest, "test_digest");
        assert_eq!(es_tx.function_count, 1);
        assert_eq!(es_tx.package_ids.len(), 1);
        assert_eq!(es_tx.move_calls.len(), 1);
    }
}
