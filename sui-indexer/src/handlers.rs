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

use crate::models::{Transaction, EsFlattener, TransactionWithEs};
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
    type Value = TransactionWithEs;

    async fn process(&self, checkpoint: &Arc<Checkpoint>) -> Result<Vec<Self::Value>> {
        let checkpoint_seq = checkpoint.summary.sequence_number as i64;
        let checkpoint_ts = checkpoint.summary.timestamp_ms as i64;

        let txs = checkpoint.transactions.iter().map(|tx| {
            let effects = &tx.effects;
            // tx.transaction is already TransactionData (not Envelope)
            let transaction_data = &tx.transaction;

            // Get status from effects
            use sui_types::execution_status::ExecutionStatus;
            let status = match effects.status() {
                ExecutionStatus::Success { .. } => "success",
                _ => "failure",
            };
            
            // Get sender
            let sender = transaction_data.sender().to_string();

            // Serialize complete raw transaction and effects for DB
            // Need to serialize the full transaction envelope, not just TransactionData
            // For now, serialize transaction_data (we'll need to get the envelope if needed)
            let raw_transaction = serde_json::to_value(transaction_data).unwrap_or(json!({}));
            let raw_effects = serde_json::to_value(effects).unwrap_or(json!({}));

            // Get transaction digest - TransactionData has digest() method
            let tx_digest = transaction_data.digest().to_string();

            // Create DB transaction
            let db_transaction = Transaction {
                tx_digest: tx_digest.clone(),
                checkpoint_sequence_number: checkpoint_seq,
                sender: sender.clone(),
                timestamp_ms: checkpoint_ts,
                execution_status: status.to_string(),
                raw_transaction: raw_transaction.clone(),
                raw_effects: Some(raw_effects.clone()),
                created_at: chrono::Utc::now(),
            };

            // Flatten ES document DIRECTLY from ExecuteTransaction (type-safe)
            let es_transaction = EsFlattener::flatten(
                transaction_data,
                effects,
                checkpoint_seq,
                checkpoint_ts,
                &status,
                &tx_digest,
            );

            TransactionWithEs {
                db_transaction,
                es_transaction,
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

        if batch.is_empty() {
            return Ok(0);
        }

        // 1. Extract DB transactions and insert into PostgreSQL
        let db_transactions: Vec<Transaction> = batch.iter()
            .map(|tx_with_es| tx_with_es.db_transaction.clone())
            .collect();

        let inserted = diesel::insert_into(transactions)
            .values(&db_transactions)
            .on_conflict(tx_digest)
            .do_nothing()
            .execute(conn)
            .await?;

        // 2. Index pre-flattened ES documents (flattened directly from ExecuteTransaction)
        let es_docs: Vec<_> = batch
            .iter()
            .map(|tx_with_es| {
                serde_json::to_value(&tx_with_es.es_transaction).unwrap_or(json!({}))
            })
            .collect();

        // Bulk index to ES (don't fail if ES is down)
        match self.es_client.bulk_index_transactions(&es_docs).await {
            Ok(count) => {
                println!("✓ Indexed {} transactions to Elasticsearch (flattened from ExecuteTransaction)", count);
            }
            Err(e) => {
                eprintln!("⚠ Warning: Failed to index to Elasticsearch: {}", e);
            }
        }

        Ok(inserted)
    }
}