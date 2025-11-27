diesel::table! {
    transaction_digests (tx_digest) {
        tx_digest -> Text,
        checkpoint_sequence_number -> Int8,
    }
}

diesel::table! {
    transactions (tx_digest) {
        tx_digest -> Text,
        checkpoint_sequence_number -> Int8,
        sender -> Nullable<Text>,
        gas_budget -> Nullable<Int8>,
        gas_used -> Nullable<Int8>,
        execution_status -> Text,
        timestamp_ms -> Nullable<Int8>,
        transaction_data -> Nullable<Jsonb>,
    }
}

diesel::allow_tables_to_appear_in_same_query!(
    transaction_digests,
    transactions,
);
