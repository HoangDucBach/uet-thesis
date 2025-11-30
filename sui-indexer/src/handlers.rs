use std::sync::Arc;
use anyhow::Result;
use async_trait::async_trait;
use diesel_async::RunQueryDsl;
use serde_json::{json, Value};
use sui_indexer_alt_framework::{
    pipeline::Processor,
    postgres::{Connection, Db},
    pipeline::sequential::Handler,
};
use sui_types::full_checkpoint_content::Checkpoint;
use sui_types::effects::TransactionEffectsAPI;
use sui_types::transaction::TransactionDataAPI;

use crate::models::Transaction;
use crate::schema::transactions::dsl::transactions;
use crate::elasticsearch::SharedEsClient;

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

    async fn process(&self, checkpoint: &Arc<Checkpoint>) -> Result<Vec<Self::Value>> {
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

            // Serialize raw transaction and effects
            let raw_transaction = serde_json::to_value(transaction).unwrap_or(json!({}));
            let raw_effects = serde_json::to_value(effects).unwrap_or(json!({}));

            Transaction {
                tx_digest: transaction.digest().to_string(),
                checkpoint_sequence_number: checkpoint_seq,
                sender,
                gas_owner: Some(gas_data.owner.to_string()),
                gas_budget: gas_data.budget as i64,
                gas_price: gas_data.price as i64,
                execution_status: status.to_string(),
                gas_used: Some(gas_summary.computation_cost as i64),
                timestamp_ms: checkpoint_ts,
                raw_transaction,
                raw_effects: Some(raw_effects),
                created_at: chrono::Utc::now(),
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
                    "sender": tx.sender,
                    "gas_budget": tx.gas_budget,
                    "gas_price": tx.gas_price,
                    "execution_status": tx.execution_status,
                    "gas_used": tx.gas_used,
                    "timestamp_ms": tx.timestamp_ms,
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
