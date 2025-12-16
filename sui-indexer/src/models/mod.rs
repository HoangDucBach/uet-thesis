pub mod transaction;
pub mod es_transaction;
pub mod es_flattener;

pub use transaction::Transaction;
pub use es_transaction::{
    EsTransaction, EsGas, EsMoveCall, EsObject, EsEffects, EsEvent,
    EsChangedObject, EsRemovedObject,
};
pub use es_flattener::EsFlattener;

/// Transaction with pre-flattened ES document
/// ES document is flattened directly from ExecuteTransaction in checkpoint
#[derive(Debug, Clone)]
pub struct TransactionWithEs {
    pub db_transaction: Transaction,
    pub es_transaction: EsTransaction,
}
