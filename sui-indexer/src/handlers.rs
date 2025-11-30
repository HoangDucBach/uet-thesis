use std::sync::Arc;
use anyhow::Result;
use async_trait::async_trait;
use diesel_async::RunQueryDsl;
use serde_json::json;
use sui_indexer_alt_framework::{
    pipeline::Processor,
    postgres::{Connection, Db},
    pipeline::sequential::Handler,
};
use sui_types::full_checkpoint_content::Checkpoint;
use sui_types::effects::TransactionEffectsAPI;
use sui_types::transaction::TransactionDataAPI;

use crate::models::{Transaction, EsFlattener};
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

            // Get sender
            let sender = transaction.sender().to_string();

            // Serialize complete raw transaction and effects
            let raw_transaction = serde_json::to_value(transaction).unwrap_or(json!({}));
            let raw_effects = serde_json::to_value(effects).unwrap_or(json!({}));

            Transaction {
                tx_digest: transaction.digest().to_string(),
                checkpoint_sequence_number: checkpoint_seq,
                sender,
                timestamp_ms: checkpoint_ts,
                execution_status: status.to_string(),
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

        // 1. Insert into PostgreSQL (raw JSONB)
        let inserted = diesel::insert_into(transactions)
            .values(batch)
            .on_conflict(tx_digest)
            .do_nothing()
            .execute(conn)
            .await?;

        // 2. Flatten and index into Elasticsearch
        if !batch.is_empty() {
            let es_docs: Vec<_> = batch
                .iter()
                .map(|tx| {
                    let es_tx = EsFlattener::flatten(tx);
                    serde_json::to_value(&es_tx).unwrap_or(json!({}))
                })
                .collect();

            // Bulk index to ES (don't fail if ES is down)
            match self.es_client.bulk_index_transactions(&es_docs).await {
                Ok(count) => {
                    println!("✓ Indexed {} transactions to Elasticsearch (flattened)", count);
                }
                Err(e) => {
                    eprintln!("⚠ Warning: Failed to index to Elasticsearch: {}", e);
                }
            }
        }

        Ok(inserted)
    }
}
