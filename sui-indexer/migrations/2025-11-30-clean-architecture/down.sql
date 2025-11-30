-- Rollback Clean Data Architecture Migration

DROP VIEW IF EXISTS v_balance_changes_summary;
DROP VIEW IF EXISTS v_move_calls_enriched;
DROP VIEW IF EXISTS v_transaction_full;

DROP TABLE IF EXISTS detection_results CASCADE;
DROP TABLE IF EXISTS transaction_effects CASCADE;
DROP TABLE IF EXISTS transaction_objects CASCADE;
DROP TABLE IF EXISTS move_calls CASCADE;
DROP TABLE IF EXISTS transactions CASCADE;
