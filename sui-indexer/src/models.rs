use diesel::prelude::*;
use diesel::sql_types::Jsonb;
use diesel::deserialize::{self, FromSql, FromSqlRow};
use diesel::serialize::{self, ToSql, Output};
use diesel::expression::AsExpression;
use diesel::pg::{Pg, PgValue};
use serde::{Deserialize, Serialize};
use serde_json::Value as JsonValue;
use sui_indexer_alt_framework::FieldCount;
use crate::schema::{transaction_digests, transactions};
use std::io::Write;

#[derive(Insertable, Debug, Clone, FieldCount)]
#[diesel(table_name = transaction_digests)]
pub struct StoredTransactionDigest {
    pub tx_digest: String,
    pub checkpoint_sequence_number: i64,
}

// Wrapper type for JsonValue to work with Diesel Jsonb
#[derive(Debug, Clone, Serialize, Deserialize, AsExpression, FromSqlRow)]
#[diesel(sql_type = Jsonb)]
pub struct JsonbValue(pub JsonValue);

impl FromSql<Jsonb, Pg> for JsonbValue {
    fn from_sql(bytes: PgValue<'_>) -> deserialize::Result<Self> {
        let bytes = bytes.as_bytes();
        // Skip the version byte (0x01) for JSONB
        let json_value: JsonValue = serde_json::from_slice(&bytes[1..])?;
        Ok(JsonbValue(json_value))
    }
}

impl ToSql<Jsonb, Pg> for JsonbValue {
    fn to_sql<'b>(&'b self, out: &mut Output<'b, '_, Pg>) -> serialize::Result {
        // Write version byte (0x01) for JSONB
        out.write_all(&[0x01])?;
        serde_json::to_writer(out, &self.0)?;
        Ok(serialize::IsNull::No)
    }
}

impl From<JsonValue> for JsonbValue {
    fn from(value: JsonValue) -> Self {
        JsonbValue(value)
    }
}

impl From<JsonbValue> for JsonValue {
    fn from(value: JsonbValue) -> Self {
        value.0
    }
}

#[derive(Insertable, Queryable, Serialize, Deserialize, Debug, Clone, FieldCount)]
#[diesel(table_name = transactions)]
pub struct Transaction {
    pub tx_digest: String,
    pub checkpoint_sequence_number: i64,
    pub sender: Option<String>,
    pub gas_budget: Option<i64>,
    pub gas_used: Option<i64>,
    pub execution_status: String,
    pub timestamp_ms: Option<i64>,
    pub transaction_data: Option<JsonbValue>,
}
