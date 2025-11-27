mod models;
mod handlers;
pub mod schema;

use handlers::{TransactionDigestHandler, TransactionHandler};

use anyhow::Result;
use clap::Parser;
use diesel_migrations::{embed_migrations, EmbeddedMigrations};
use sui_indexer_alt_framework::{
    cluster::{Args, IndexerCluster},
    pipeline::sequential::SequentialConfig,
};
use tokio;
use url::Url;

const MIGRATIONS: EmbeddedMigrations = embed_migrations!("migrations");

#[tokio::main]
async fn main() -> Result<()> {
    dotenvy::dotenv().ok();

    let database_url = std::env::var("DATABASE_URL")
        .expect("DATABASE_URL must be set in the environment")
        .parse::<Url>()
        .expect("Invalid database URL");

    let args = Args::parse();

    let mut cluster = IndexerCluster::builder()
        .with_args(args)
        .with_database_url(database_url)
        .with_migrations(&MIGRATIONS)
        .build()
        .await?;

    cluster.sequential_pipeline(
        TransactionDigestHandler,
        SequentialConfig::default(),
    ).await?;

    cluster.sequential_pipeline(
        TransactionHandler,
        SequentialConfig::default(),
    ).await?;

    let handle = cluster.run().await?;
    handle.await?;

    Ok(())
}
