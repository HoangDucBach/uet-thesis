mod models;
mod handlers;
mod elasticsearch;
mod constants;
mod risk;
mod analyzer;
mod pipeline;
mod action;
mod events;  // NEW: Strongly-typed event structs
pub mod schema;

use handlers::TransactionHandler;
use elasticsearch::EsClient;

use anyhow::Result;
use clap::Parser;
use diesel_migrations::{embed_migrations, EmbeddedMigrations};
use std::sync::Arc;
use sui_indexer_alt_framework::{
    cluster::{Args, IndexerCluster},
    pipeline::sequential::SequentialConfig,
};
use url::Url;

const MIGRATIONS: EmbeddedMigrations = embed_migrations!("migrations");

#[tokio::main]
async fn main() -> Result<()> {
    dotenvy::dotenv().ok();

    let database_url = std::env::var("DATABASE_URL")
        .expect("DATABASE_URL must be set in the environment")
        .parse::<Url>()
        .expect("Invalid database URL");

    // Initialize Elasticsearch client
    let es_url = std::env::var("ELASTICSEARCH_URL")
        .unwrap_or_else(|_| "http://localhost:9200".to_string());
    let es_index = std::env::var("ELASTICSEARCH_INDEX")
        .unwrap_or_else(|_| "sui-transactions".to_string());

    let es_client = Arc::new(EsClient::new(&es_url, &es_index)?);

    // Ensure index exists with proper mappings
    es_client.ensure_index().await?;
    println!("Elasticsearch client initialized: {} -> {}", es_url, es_index);

    let args = Args::parse();

    let mut cluster = IndexerCluster::builder()
        .with_args(args)
        .with_database_url(database_url)
        .with_migrations(&MIGRATIONS)
        .build()
        .await?;

    cluster.sequential_pipeline(
        TransactionHandler::new(es_client),
        SequentialConfig::default(),
    ).await?;

    let handle = cluster.run().await?;
    handle.await?;

    Ok(())
}