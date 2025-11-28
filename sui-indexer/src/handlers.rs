use std::sync::Arc;
use anyhow::Result;
use async_trait::async_trait;
use sui_indexer_alt_framework::pipeline::Processor;
use sui_types::full_checkpoint_content::Checkpoint;
use sui_types::effects::TransactionEffectsAPI;
use sui_types::transaction::TransactionDataAPI;
use serde_json::json;

use crate::models::{StoredTransactionDigest, Transaction, JsonbValue};
use crate::schema::transaction_digests::dsl::transaction_digests;
use crate::schema::transactions::dsl::transactions;
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

pub struct TransactionHandler;

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
                sender: Some(sender),
                gas_budget: Some(gas_data.budget as i64),
                gas_used: Some(gas_summary.computation_cost as i64),
                execution_status: status.to_string(),
                timestamp_ms: Some(checkpoint_ts),
                transaction_data: Some(JsonbValue(json!({
                    "transaction_kind": format!("{:?}", transaction.kind()),
                    "gas_owner": gas_data.owner.to_string(),
                    "gas_price": gas_data.price,
                    "computation_cost": gas_summary.computation_cost,
                    "storage_cost": gas_summary.storage_cost,
                    "storage_rebate": gas_summary.storage_rebate,
                    "modified_objects_count": effects.modified_at_versions().len(),
                    "created_objects_count": effects.created().len(),
                    "deleted_objects_count": effects.deleted().len(),
                }))),
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

        let inserted = diesel::insert_into(transactions)
            .values(batch)
            .on_conflict(tx_digest)
            .do_nothing()
            .execute(conn)
            .await?;
        Ok(inserted)
    }
}
