"""
data_loader.py
==============
Handles data ingestion from CSV and PostgreSQL.

In a real company environment, this would be connected to:
- A data warehouse (Snowflake, BigQuery, Redshift)
- dbt-built models
- An internal data catalog

For this portfolio project, we support CSV + PostgreSQL.
"""

import os
import pandas as pd
from pathlib import Path
from sqlalchemy import create_engine, text
from dotenv import load_dotenv

# Load environment variables for DB credentials
load_dotenv()

# ── Project paths ──────────────────────────────────────────────────────────────
PROJECT_ROOT = Path(__file__).resolve().parent.parent
RAW_DATA_PATH = PROJECT_ROOT / "data" / "raw" / "WA_Fn-UseC_-Telco-Customer-Churn.csv"
PROCESSED_DATA_PATH = PROJECT_ROOT / "data" / "processed"


def load_raw_csv(path: Path = RAW_DATA_PATH) -> pd.DataFrame:
    """
    Load the raw Kaggle CSV into a DataFrame.
    Performs minimal dtype coercion so the cleaning step stays separate.

    Parameters
    ----------
    path : Path
        Path to the raw CSV file.

    Returns
    -------
    pd.DataFrame
        Raw DataFrame with original column names.
    """
    if not path.exists():
        raise FileNotFoundError(
            f"Dataset not found at {path}\n"
            f"Download from: https://www.kaggle.com/datasets/blastchar/telco-customer-churn\n"
            f"Place the CSV in: data/raw/"
        )

    df = pd.read_csv(path)
    print(f"✅ Loaded {len(df):,} rows × {df.shape[1]} columns from {path.name}")
    return df


def get_pg_engine(
    host: str = None,
    port: int = 5432,
    database: str = "saas_churn",
    user: str = None,
    password: str = None
):
    """
    Create a SQLAlchemy engine for PostgreSQL.
    Reads credentials from environment variables if not passed directly.

    Environment variables (set in .env):
        PG_HOST, PG_PORT, PG_DB, PG_USER, PG_PASSWORD

    Returns
    -------
    sqlalchemy.Engine
    """
    host     = host     or os.getenv("PG_HOST", "localhost")
    user     = user     or os.getenv("PG_USER", "postgres")
    password = password or os.getenv("PG_PASSWORD", "")
    port     = port     or int(os.getenv("PG_PORT", 5432))
    database = database or os.getenv("PG_DB", "saas_churn")

    conn_string = f"postgresql+psycopg2://{user}:{password}@{host}:{port}/{database}"
    engine = create_engine(conn_string, echo=False)
    print(f"✅ PostgreSQL engine created → {host}:{port}/{database}")
    return engine


def load_from_postgres(query: str, engine) -> pd.DataFrame:
    """
    Execute a SQL query and return results as a DataFrame.

    Parameters
    ----------
    query : str
        SQL query string (schema-qualified e.g. SELECT * FROM saas_churn.customers)
    engine : sqlalchemy.Engine

    Returns
    -------
    pd.DataFrame
    """
    with engine.connect() as conn:
        df = pd.read_sql(text(query), conn)
    print(f"✅ Query returned {len(df):,} rows")
    return df


def save_processed(df: pd.DataFrame, filename: str) -> Path:
    """
    Save a processed DataFrame to the data/processed/ directory as parquet.
    Parquet is preferred over CSV for preserving dtypes.

    Parameters
    ----------
    df : pd.DataFrame
    filename : str  (without extension)

    Returns
    -------
    Path to the saved file
    """
    PROCESSED_DATA_PATH.mkdir(parents=True, exist_ok=True)
    out_path = PROCESSED_DATA_PATH / f"{filename}.parquet"
    df.to_parquet(out_path, index=False)
    print(f"✅ Saved {len(df):,} rows → {out_path}")
    return out_path


def load_processed(filename: str) -> pd.DataFrame:
    """Load a previously saved processed parquet file."""
    path = PROCESSED_DATA_PATH / f"{filename}.parquet"
    df = pd.read_parquet(path)
    print(f"✅ Loaded processed dataset: {filename} ({len(df):,} rows)")
    return df
