// @generated automatically by Diesel CLI.

diesel::table! {
    transactions (id) {
        id -> Int8,
        tx_digest -> Text,
        checkpoint_sequence_number -> Int8,
        sender -> Text,
        timestamp_ms -> Int8,
        execution_status -> Text,
        raw_transaction -> Jsonb,
        raw_effects -> Nullable<Jsonb>,
        created_at -> Timestamptz,
    }
}

diesel::table! {
    watermarks (pipeline) {
        pipeline -> Text,
        epoch_hi_inclusive -> Int8,
        checkpoint_hi_inclusive -> Int8,
        tx_hi -> Int8,
        timestamp_ms_hi_inclusive -> Int8,
        reader_lo -> Int8,
        pruner_timestamp -> Timestamp,
        pruner_hi -> Int8,
    }
}

diesel::allow_tables_to_appear_in_same_query!(transactions, watermarks,);
