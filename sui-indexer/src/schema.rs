// @generated automatically by Diesel CLI.

diesel::table! {
    transaction_digests (tx_digest) {
        tx_digest -> Text,
        checkpoint_sequence_number -> Int8,
    }
}

diesel::table! {
    transactions (id) {
        id -> Int8,
        tx_digest -> Text,
        checkpoint_sequence_number -> Int8,
        sender -> Text,
        gas_owner -> Nullable<Text>,
        gas_budget -> Int8,
        gas_used -> Nullable<Int8>,
        gas_price -> Int8,
        execution_status -> Text,
        timestamp_ms -> Int8,
        transaction_kind -> Text,
        is_system_tx -> Bool,
        is_sponsored_tx -> Bool,
        is_end_of_epoch_tx -> Bool,
        total_move_calls -> Int4,
        total_input_objects -> Int4,
        total_shared_objects -> Int4,
        computation_cost -> Nullable<Int8>,
        storage_cost -> Nullable<Int8>,
        storage_rebate -> Nullable<Int8>,
        expiration_epoch -> Nullable<Int8>,
        raw_transaction_data -> Jsonb,
        processed_at -> Timestamptz,
        updated_at -> Nullable<Timestamptz>,
    }
}

diesel::table! {
    move_calls (id) {
        id -> Int8,
        tx_digest -> Text,
        call_sequence -> Int4,
        package_id -> Text,
        module_name -> Text,
        function_name -> Text,
        type_arguments -> Array<Text>,
        is_entry_function -> Bool,
        arguments -> Nullable<Jsonb>,
        created_at -> Timestamptz,
    }
}

diesel::table! {
    transaction_objects (id) {
        id -> Int8,
        tx_digest -> Text,
        object_sequence -> Int4,
        object_id -> Text,
        object_version -> Nullable<Int8>,
        object_digest -> Nullable<Text>,
        object_type -> Text,
        object_kind -> Nullable<Text>,
        owner_type -> Nullable<Text>,
        owner_address -> Nullable<Text>,
    }
}

diesel::table! {
    transaction_effects (id) {
        id -> Int8,
        tx_digest -> Text,
        effect_sequence -> Int4,
        effect_type -> Text,
        affected_object_id -> Nullable<Text>,
        object_type -> Nullable<Text>,
        coin_type -> Nullable<Text>,
        balance_change -> Nullable<Int8>,
        owner_address -> Nullable<Text>,
        event_type -> Nullable<Text>,
        event_data -> Nullable<Jsonb>,
    }
}

diesel::table! {
    detection_results (id) {
        id -> Int8,
        tx_digest -> Text,
        engine_name -> Text,
        detection_id -> Text,
        attack_type -> Text,
        confidence -> Float8,
        severity -> Text,
        evidence -> Array<Text>,
        metadata -> Nullable<Jsonb>,
        detected_at -> Timestamptz,
    }
}

// Note: joinable! macros removed because we're joining on tx_digest (not primary key)
// Joins can still be performed manually without type-safety macros

diesel::allow_tables_to_appear_in_same_query!(
    transaction_digests,
    transactions,
    move_calls,
    transaction_objects,
    transaction_effects,
    detection_results,
);
