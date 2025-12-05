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
use sui_types::full_checkpoint_content::{Checkpoint, CheckpointTransaction};
use sui_types::effects::{TransactionEffectsAPI, TransactionEvents};
use sui_types::transaction::TransactionDataAPI;

use crate::models::{Transaction, EsFlattener, TransactionWithEs};
use crate::schema::transactions::dsl::transactions;
use crate::elasticsearch::SharedEsClient;
use crate::pipeline::{DetectionPipeline, FlashLoanDetector, PriceManipulationDetector, SandwichDetector, OracleManipulationDetector};
use crate::action::{ActionPipeline, LogAction, AlertAction};
use crate::risk::{DetectionContext, RiskLevel};
use crate::constants::SIMULATION_PACKAGE_ID;

// Type alias for the transaction type from checkpoint
// Checkpoint.transactions yields ExecutedTransaction which is the same as CheckpointTransaction
type TxType = CheckpointTransaction;

pub struct TransactionHandler {
    es_client: SharedEsClient,
    detection_pipeline: DetectionPipeline,
    action_pipeline: ActionPipeline,
}

impl TransactionHandler {
    pub fn new(es_client: SharedEsClient) -> Self {
        let detection_pipeline = DetectionPipeline::new()
            .add_detector(FlashLoanDetector::new())
            .add_detector(PriceManipulationDetector::new())
            .add_detector(SandwichDetector::new())
            .add_detector(OracleManipulationDetector::new());

        let webhook_url = std::env::var("ALERT_WEBHOOK_URL").ok();
        let action_pipeline = ActionPipeline::new()
            .add_handler(LogAction::new())
            .add_handler(AlertAction::new(webhook_url, RiskLevel::High));

        Self {
            es_client,
            detection_pipeline,
            action_pipeline,
        }
    }

    /// Check if a transaction involves the target package ID
    /// Returns true if any event emitted is from the target package
    /// Currently checks events only (sufficient for our detection purposes)
    fn involves_target_package(events: Option<&TransactionEvents>) -> bool {
        if let Some(event_wrapper) = events {
            for event in &event_wrapper.data {
                let package_id = event.type_.address.to_string();
                if package_id == SIMULATION_PACKAGE_ID {
                    return true;
                }
            }
        }
        false
    }
}

#[async_trait]
impl Processor for TransactionHandler {
    const NAME: &'static str = "transaction_handler";
    type Value = TransactionWithEs;

    async fn process(&self, checkpoint: &Arc<Checkpoint>) -> Result<Vec<Self::Value>> {
        let checkpoint_seq = checkpoint.summary.sequence_number as i64;
        let checkpoint_ts = checkpoint.summary.timestamp_ms as i64;

        let mut txs = Vec::new();

        for tx in &checkpoint.transactions {
            let effects = &tx.effects;
            let transaction_data = &tx.transaction;

            use sui_types::execution_status::ExecutionStatus;
            let status = match effects.status() {
                ExecutionStatus::Success { .. } => "success",
                _ => "failure",
            };

            let sender = transaction_data.sender().to_string();
            let raw_transaction = serde_json::to_value(transaction_data).unwrap_or(json!({}));
            let raw_effects = serde_json::to_value(effects).unwrap_or(json!({}));
            let tx_digest = transaction_data.digest().to_string();

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

            let es_transaction = EsFlattener::flatten(
                transaction_data,
                effects,
                tx.events.as_ref(),
                checkpoint_seq,
                checkpoint_ts,
                &status,
                &tx_digest,
            );

            // Only run detection for transactions involving the target package
            if Self::involves_target_package(tx.events.as_ref()) {
                let context = DetectionContext::new(
                    tx_digest.clone(),
                    sender.clone(),
                    checkpoint_seq,
                    checkpoint_ts,
                );

                let risk_events = self.detection_pipeline.run(tx, &context).await;

                if !risk_events.is_empty() {
                    println!("🔍 Detected {} risk events in tx {}", risk_events.len(), &tx_digest[..8]);
                }

                for event in risk_events {
                    self.action_pipeline.run(&event).await;
                }
            }

            txs.push(TransactionWithEs {
                db_transaction,
                es_transaction,
            });
        }

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
        // EsTransaction already implements Serialize, convert to JSON Value
        let es_docs: Vec<Value> = batch
            .iter()
            .map(|tx_with_es| {
                serde_json::to_value(&tx_with_es.es_transaction)
                    .unwrap_or_else(|e| {
                        eprintln!("Failed to serialize EsTransaction: {}", e);
                        json!({})
                    })
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