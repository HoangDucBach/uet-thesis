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
