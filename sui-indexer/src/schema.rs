// @generated automatically by Diesel CLI.

diesel::table! {
    transactions (tx_digest) {
        tx_digest -> Text,
        checkpoint_sequence_number -> Int8,
        sender -> Text,
        gas_owner -> Nullable<Text>,
        gas_budget -> Int8,
        gas_price -> Int8,
        execution_status -> Text,
        gas_used -> Nullable<Int8>,
        timestamp_ms -> Int8,
        raw_transaction -> Jsonb,
        raw_effects -> Nullable<Jsonb>,
        created_at -> Timestamptz,
    }
}

diesel::table! {
    move_calls (id) {
        id -> Int8,
        tx_digest -> Text,
        package -> Text,
        module -> Text,
        function -> Text,
        type_arguments -> Nullable<Jsonb>,
        arguments -> Nullable<Jsonb>,
    }
}

diesel::table! {
    objects (id) {
        id -> Int8,
        tx_digest -> Text,
        object_id -> Text,
        version -> Nullable<Int8>,
        digest -> Nullable<Text>,
        object_type -> Text,
        owner -> Nullable<Jsonb>,
        raw_object -> Nullable<Jsonb>,
    }
}

diesel::table! {
    events (id) {
        id -> Int8,
        tx_digest -> Text,
        event_type -> Text,
        package -> Text,
        module -> Text,
        sender -> Text,
        raw_event -> Jsonb,
    }
}

diesel::allow_tables_to_appear_in_same_query!(
    transactions,
    move_calls,
    objects,
    events,
);
