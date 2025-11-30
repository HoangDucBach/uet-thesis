use chrono::{DateTime, Datelike, Timelike, Utc};
use serde::{Deserialize, Serialize};

use super::Transaction;

/// Elasticsearch-optimized transaction document (flattened for fast search)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ElasticsearchTransaction {
    // Core identifiers
    pub tx_digest: String,
    pub checkpoint_sequence_number: i64,
    #[serde(with = "chrono::serde::ts_milliseconds")]
    pub timestamp: DateTime<Utc>,

    // Basic metadata
    pub sender: String,
    pub gas_owner: Option<String>,
    pub gas_budget: i64,
    pub gas_used: Option<i64>,
    pub gas_price: i64,
    pub execution_status: String,

    // Transaction classification
    pub transaction_kind: String,
    pub is_system_tx: bool,
    pub is_sponsored_tx: bool,
    pub is_end_of_epoch_tx: bool,

    // Flattened arrays (for fast search)
    pub package_ids: Vec<String>,
    pub module_names: Vec<String>,
    pub function_names: Vec<String>,
    pub full_function_calls: Vec<String>, // "package::module::function"

    // Object data (flattened)
    pub input_object_ids: Vec<String>,
    pub shared_object_ids: Vec<String>,
    pub receiving_object_ids: Vec<String>,
    pub total_objects: i32,

    // Financial data (flattened)
    pub coin_types_involved: Vec<String>,
    pub max_balance_change: Option<i64>,
    pub total_balance_changes: i32,
    pub net_balance_change: Option<i64>,

    // Structural metrics (computed from data)
    pub function_count: i32,
    pub package_count: i32,
    pub object_count: i32,
    pub complexity_factor: i32,

    // Time-based fields for aggregations
    pub hour_of_day: u8,
    pub day_of_week: u8,
    pub day_of_month: u8,
    pub month: u8,
    pub year: u16,

    // Nested structures for complex queries
    pub move_calls: Vec<ElasticsearchMoveCall>,
    pub object_interactions: Vec<ElasticsearchObjectInteraction>,
    pub balance_changes: Vec<ElasticsearchBalanceChange>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ElasticsearchMoveCall {
    pub package: String,
    pub module: String,
    pub function: String,
    pub type_args: Vec<String>,
    pub sequence: i32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ElasticsearchObjectInteraction {
    pub object_id: String,
    pub object_type: String,
    pub interaction_type: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ElasticsearchBalanceChange {
    pub coin_type: String,
    pub amount: i64,
    pub owner: String,
}

impl From<&Transaction> for ElasticsearchTransaction {
    fn from(tx: &Transaction) -> Self {
        let timestamp = DateTime::<Utc>::from_timestamp_millis(tx.timestamp_ms).unwrap_or_default();

        ElasticsearchTransaction {
            tx_digest: tx.tx_digest.clone(),
            checkpoint_sequence_number: tx.checkpoint_sequence_number,
            timestamp,
            sender: tx.sender.clone(),
            gas_owner: tx.gas_owner.clone(),
            gas_budget: tx.gas_budget,
            gas_used: tx.gas_used,
            gas_price: tx.gas_price,
            execution_status: tx.execution_status.clone(),

            transaction_kind: tx.transaction_kind.clone(),
            is_system_tx: tx.is_system_tx,
            is_sponsored_tx: tx.is_sponsored_tx,
            is_end_of_epoch_tx: tx.is_end_of_epoch_tx,

            // Flatten arrays (will be populated from related tables)
            package_ids: vec![],
            module_names: vec![],
            function_names: vec![],
            full_function_calls: vec![],

            // Compute structural metrics
            function_count: tx.total_move_calls,
            package_count: 0, // Will be computed
            object_count: tx.total_input_objects + tx.total_shared_objects,
            complexity_factor: tx.total_move_calls * 1, // Will be updated

            // Time-based fields
            hour_of_day: timestamp.hour() as u8,
            day_of_week: timestamp.weekday().num_days_from_monday() as u8,
            day_of_month: timestamp.day() as u8,
            month: timestamp.month() as u8,
            year: timestamp.year() as u16,

            // Initialize nested structures
            move_calls: vec![],
            object_interactions: vec![],
            balance_changes: vec![],

            // Financial data (will be populated from effects)
            coin_types_involved: vec![],
            max_balance_change: None,
            total_balance_changes: 0,
            net_balance_change: None,

            // Object data
            input_object_ids: vec![],
            shared_object_ids: vec![],
            receiving_object_ids: vec![],
            total_objects: tx.total_input_objects + tx.total_shared_objects,
        }
    }
}

impl ElasticsearchTransaction {
    /// Add move call to the document
    pub fn add_move_call(&mut self, package: String, module: String, function: String, type_args: Vec<String>, sequence: i32) {
        let full_call = format!("{}::{}::{}", package, module, function);

        // Add to flattened arrays
        if !self.package_ids.contains(&package) {
            self.package_ids.push(package.clone());
        }
        if !self.module_names.contains(&module) {
            self.module_names.push(module.clone());
        }
        if !self.function_names.contains(&function) {
            self.function_names.push(function.clone());
        }
        if !self.full_function_calls.contains(&full_call) {
            self.full_function_calls.push(full_call);
        }

        // Add to nested structure
        self.move_calls.push(ElasticsearchMoveCall {
            package,
            module,
            function,
            type_args,
            sequence,
        });

        // Update counts
        self.function_count = self.move_calls.len() as i32;
        self.package_count = self.package_ids.len() as i32;
        self.complexity_factor = self.function_count * self.package_count;
    }

    /// Add object interaction to the document
    pub fn add_object_interaction(&mut self, object_id: String, object_type: String, interaction_type: String) {
        match interaction_type.as_str() {
            "input" => {
                if !self.input_object_ids.contains(&object_id) {
                    self.input_object_ids.push(object_id.clone());
                }
            }
            "shared" => {
                if !self.shared_object_ids.contains(&object_id) {
                    self.shared_object_ids.push(object_id.clone());
                }
            }
            "receiving" => {
                if !self.receiving_object_ids.contains(&object_id) {
                    self.receiving_object_ids.push(object_id.clone());
                }
            }
            _ => {}
        }

        self.object_interactions.push(ElasticsearchObjectInteraction {
            object_id,
            object_type,
            interaction_type,
        });

        self.object_count = self.object_interactions.len() as i32;
        self.total_objects = self.object_count;
    }

    /// Add balance change to the document
    pub fn add_balance_change(&mut self, coin_type: String, amount: i64, owner: String) {
        if !self.coin_types_involved.contains(&coin_type) {
            self.coin_types_involved.push(coin_type.clone());
        }

        self.balance_changes.push(ElasticsearchBalanceChange {
            coin_type,
            amount,
            owner,
        });

        self.total_balance_changes = self.balance_changes.len() as i32;

        // Update max balance change
        if let Some(max) = self.max_balance_change {
            if amount.abs() > max.abs() {
                self.max_balance_change = Some(amount);
            }
        } else {
            self.max_balance_change = Some(amount);
        }

        // Update net balance change
        let net: i64 = self.balance_changes.iter().map(|b| b.amount).sum();
        self.net_balance_change = Some(net);
    }
}
