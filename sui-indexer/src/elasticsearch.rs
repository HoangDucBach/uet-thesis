use anyhow::{Context, Result};
use elasticsearch::{
    Elasticsearch,
    http::transport::{SingleNodeConnectionPool, TransportBuilder},
    BulkParts,
};
use serde_json::{json, Value};
use std::sync::Arc;
use url::Url;

/// Elasticsearch client wrapper
pub struct EsClient {
    client: Elasticsearch,
    index_name: String,
}

impl EsClient {
    /// Create a new Elasticsearch client
    pub fn new(url: &str, index_name: &str) -> Result<Self> {
        let url = Url::parse(url)
            .context("Failed to parse Elasticsearch URL")?;

        let conn_pool = SingleNodeConnectionPool::new(url);
        let transport = TransportBuilder::new(conn_pool)
            .disable_proxy()
            .build()?;

        let client = Elasticsearch::new(transport);

        Ok(Self {
            client,
            index_name: index_name.to_string(),
        })
    }

    /// Bulk index transactions into Elasticsearch
    pub async fn bulk_index_transactions(&self, transactions: &[Value]) -> Result<usize> {
        if transactions.is_empty() {
            return Ok(0);
        }

        let mut body: Vec<elasticsearch::http::request::JsonBody<Value>> = Vec::with_capacity(transactions.len() * 2);

        for tx in transactions {
            // Extract tx_digest for document ID
            let tx_digest = tx.get("tx_digest")
                .and_then(|v| v.as_str())
                .unwrap_or("unknown");

            // Add index operation header
            body.push(json!({
                "index": {
                    "_id": tx_digest
                }
            }).into());

            // Add document
            body.push(tx.clone().into());
        }

        let response = self.client
            .bulk(BulkParts::Index(&self.index_name))
            .body(body)
            .send()
            .await
            .context("Failed to send bulk request to Elasticsearch")?;

        let response_body = response.json::<Value>().await
            .context("Failed to parse Elasticsearch bulk response")?;

        // Check for errors
        let has_errors = response_body.get("errors")
            .and_then(|v| v.as_bool())
            .unwrap_or(false);

        if has_errors {
            // Log errors but don't fail the entire batch
            if let Some(items) = response_body.get("items").and_then(|v| v.as_array()) {
                for item in items {
                    if let Some(index_result) = item.get("index") {
                        if let Some(error) = index_result.get("error") {
                            eprintln!("ES indexing error: {:?}", error);
                        }
                    }
                }
            }
        }

        // Return count of successfully indexed documents
        let indexed_count = response_body.get("items")
            .and_then(|v| v.as_array())
            .map(|arr| arr.len())
            .unwrap_or(0);

        Ok(indexed_count)
    }

    /// Create the index with appropriate mappings if it doesn't exist
    pub async fn ensure_index(&self) -> Result<()> {
        let exists_response = self.client
            .indices()
            .exists(elasticsearch::indices::IndicesExistsParts::Index(&[&self.index_name]))
            .send()
            .await?;

        if exists_response.status_code().is_success() {
            // Index already exists
            return Ok(());
        }

        // Create index with mappings - full structure
        let mappings = json!({
            "mappings": {
                "properties": {
                    "tx_digest": { "type": "keyword" },
                    "checkpoint_sequence_number": { "type": "long" },
                    "timestamp_ms": { "type": "date", "format": "epoch_millis" },
                    "sender": { "type": "keyword" },
                    "execution_status": { "type": "keyword" },
                    "kind": { "type": "keyword" },
                    "is_system_tx": { "type": "boolean" },
                    "is_sponsored_tx": { "type": "boolean" },
                    "is_end_of_epoch_tx": { "type": "boolean" },
                    "gas": {
                        "properties": {
                            "owner": { "type": "keyword" },
                            "budget": { "type": "long" },
                            "price": { "type": "long" },
                            "used": { "type": "long" },
                            "computation_cost": { "type": "long" },
                            "storage_cost": { "type": "long" },
                            "storage_rebate": { "type": "long" }
                        }
                    },
                    "move_calls": {
                        "type": "nested",
                        "properties": {
                            "package": { "type": "keyword" },
                            "module": { "type": "keyword" },
                            "function": { "type": "keyword" },
                            "full_name": { "type": "keyword" }
                        }
                    },
                    "objects": {
                        "type": "nested",
                        "properties": {
                            "object_id": { "type": "keyword" },
                            "type": { "type": "keyword" },
                            "owner": { "type": "keyword" }
                        }
                    },
                    "effects": {
                        "properties": {
                            "created_count": { "type": "integer" },
                            "mutated_count": { "type": "integer" },
                            "deleted_count": { "type": "integer" },
                            "all_changed_objects": {
                                "type": "nested",
                                "properties": {
                                    "object_id": { "type": "keyword" },
                                    "input_version": { "type": "long" },
                                    "input_digest": { "type": "keyword" },
                                    "input_owner": { "type": "keyword" },
                                    "input_state_type": { "type": "keyword" },
                                    "output_version": { "type": "long" },
                                    "output_digest": { "type": "keyword" },
                                    "output_owner": { "type": "keyword" },
                                    "output_state_type": { "type": "keyword" },
                                    "id_operation": { "type": "keyword" }
                                }
                            },
                            "all_removed_objects": {
                                "type": "nested",
                                "properties": {
                                    "object_id": { "type": "keyword" },
                                    "version": { "type": "long" },
                                    "digest": { "type": "keyword" },
                                    "remove_kind": { "type": "keyword" }
                                }
                            }
                        }
                    },
                    "events": {
                        "type": "nested",
                        "properties": {
                            "type": { "type": "keyword" },
                            "package": { "type": "keyword" },
                            "module": { "type": "keyword" },
                            "sender": { "type": "keyword" }
                        }
                    },
                    "packages": { "type": "keyword" },
                    "modules": { "type": "keyword" },
                    "functions": { "type": "keyword" }
                }
            },
            "settings": {
                "number_of_shards": 3,
                "number_of_replicas": 0,
                "refresh_interval": "30s"
            }
        });

        self.client
            .indices()
            .create(elasticsearch::indices::IndicesCreateParts::Index(&self.index_name))
            .body(mappings)
            .send()
            .await
            .context("Failed to create Elasticsearch index")?;

        println!("Created Elasticsearch index: {}", self.index_name);
        Ok(())
    }
}

/// Shared Elasticsearch client instance
pub type SharedEsClient = Arc<EsClient>;
