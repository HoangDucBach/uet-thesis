use std::sync::Arc;
use anyhow::Result;
use async_trait::async_trait;
use sui_indexer_alt_framework::pipeline::Processor;
use sui_types::full_checkpoint_content::Checkpoint;
use sui_types::effects::TransactionEffectsAPI;
use sui_types::transaction::TransactionDataAPI;
use serde_json::{json, Value};

use crate::models::{StoredTransactionDigest, LegacyTransaction as Transaction, JsonbValue};
use crate::schema::transaction_digests::dsl::transaction_digests;
use crate::schema::transactions::dsl::transactions;
use crate::elasticsearch::SharedEsClient;
use diesel_async::RunQueryDsl;
use sui_indexer_alt_framework::{
    postgres::{Connection, Db},
    pipeline::sequential::Handler,
};

pub struct TransactionDigestHandler;

#[async_trait]
impl Processor for TransactionDigestHandler {
    const NAME: &'static str = "transaction_digest_handler";
    type Value = StoredTransactionDigest;

    async fn process(&self, checkpoint: &Arc<Checkpoint>) -> anyhow::Result<Vec<Self::Value>> {
        let checkpoint_seq = checkpoint.summary.sequence_number as i64;
        let digests = checkpoint.transactions.iter().map(|tx| {
            StoredTransactionDigest {
                tx_digest: tx.transaction.digest().to_string(),
                checkpoint_sequence_number: checkpoint_seq,
            }
        }).collect();
        Ok(digests)
    }
}

#[async_trait]
impl Handler for TransactionDigestHandler {
    type Store = Db;
    type Batch = Vec<Self::Value>;

    fn batch(&self, batch: &mut Self::Batch, values: std::vec::IntoIter<Self::Value>) {
        batch.extend(values);
    }

    async fn commit<'a>(
        &self,
        batch: &Self::Batch,
        conn: &mut Connection<'a>,
    ) -> Result<usize> {
        use crate::schema::transaction_digests::dsl::tx_digest;
        let inserted = diesel::insert_into(transaction_digests)
            .values(batch)
            .on_conflict(tx_digest)
            .do_nothing()
            .execute(conn)
            .await?;
        Ok(inserted)
    }
}

pub struct TransactionHandler {
    es_client: SharedEsClient,
}

impl TransactionHandler {
    pub fn new(es_client: SharedEsClient) -> Self {
        Self { es_client }
    }
}

#[async_trait]
impl Processor for TransactionHandler {
    const NAME: &'static str = "transaction_handler";
    type Value = Transaction;

    async fn process(&self, checkpoint: &Arc<Checkpoint>) -> anyhow::Result<Vec<Self::Value>> {
        let checkpoint_seq = checkpoint.summary.sequence_number as i64;
        let checkpoint_ts = checkpoint.summary.timestamp_ms as i64;

        let txs = checkpoint.transactions.iter().map(|tx| {
            let effects = &tx.effects;
            let transaction = &tx.transaction;
            
            // Get status from effects
            use sui_types::execution_status::ExecutionStatus;
            let status = match effects.status() {
                ExecutionStatus::Success { .. } => "success",
                _ => "failure",
            };

            // Get transaction data
            let sender = transaction.sender().to_string();
            let gas_data = transaction.gas_data();
            
            // Get gas cost summary from effects
            let gas_summary = effects.gas_cost_summary();

            Transaction {
                tx_digest: transaction.digest().to_string(),
                checkpoint_sequence_number: checkpoint_seq,
                sender,
                gas_owner: Some(gas_data.owner.to_string()),
                gas_budget: gas_data.budget as i64,
                gas_used: Some(gas_summary.computation_cost as i64),
                gas_price: gas_data.price as i64,
                execution_status: status.to_string(),
                timestamp_ms: checkpoint_ts,
                transaction_kind: format!("{:?}", transaction.kind()),
                is_system_tx: false,
                is_sponsored_tx: false,
                is_end_of_epoch_tx: false,
                total_move_calls: 0,
                total_input_objects: 0,
                total_shared_objects: 0,
                computation_cost: Some(gas_summary.computation_cost as i64),
                storage_cost: Some(gas_summary.storage_cost as i64),
                storage_rebate: Some(gas_summary.storage_rebate as i64),
                expiration_epoch: None,
                raw_transaction_data: serde_json::to_value(json!({
                    "transaction_kind": format!("{:?}", transaction.kind()),
                    "gas_owner": gas_data.owner.to_string(),
                    "gas_price": gas_data.price,
                    "computation_cost": gas_summary.computation_cost,
                    "storage_cost": gas_summary.storage_cost,
                    "storage_rebate": gas_summary.storage_rebate,
                    "modified_objects_count": effects.modified_at_versions().len(),
                    "created_objects_count": effects.created().len(),
                    "deleted_objects_count": effects.deleted().len(),
                })).unwrap(),
            }
        }).collect();

        Ok(txs)
    }
}

#[async_trait]
impl Handler for TransactionHandler {
    type Store = Db;
    type Batch = Vec<Self::Value>;

    fn batch(&self, batch: &mut Self::Batch, values: std::vec::IntoIter<Self::Value>) {
        batch.extend(values);
    }

    async fn commit<'a>(
        &self,
        batch: &Self::Batch,
        conn: &mut Connection<'a>,
    ) -> Result<usize> {
        use crate::schema::transactions::dsl::tx_digest;

        // Insert into PostgreSQL
        let inserted = diesel::insert_into(transactions)
            .values(batch)
            .on_conflict(tx_digest)
            .do_nothing()
            .execute(conn)
            .await?;

        // Index into Elasticsearch (async, best effort)
        if !batch.is_empty() {
            let es_docs: Vec<Value> = batch.iter().map(|tx| {
                json!({
                    "tx_digest": tx.tx_digest,
                    "checkpoint_sequence_number": tx.checkpoint_sequence_number,
                    "execution_status": tx.execution_status,
                    "sender": tx.sender,
                    "gas_budget": tx.gas_budget,
                    "gas_used": tx.gas_used,
                    "gas_price": tx.gas_price,
                    "timestamp_ms": tx.timestamp_ms,
                    "transaction_kind": tx.transaction_kind,
                    "raw_transaction_data": tx.raw_transaction_data,
                })
            }).collect();

            // Bulk index to ES (don't fail if ES is down)
            match self.es_client.bulk_index_transactions(&es_docs).await {
                Ok(count) => {
                    println!("Indexed {} transactions to Elasticsearch", count);
                }
                Err(e) => {
                    eprintln!("Warning: Failed to index to Elasticsearch: {}", e);
                }
            }
        }

        Ok(inserted)
    }
}
