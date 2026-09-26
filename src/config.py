import os
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[1]
RAW_DATA_DIR = PROJECT_ROOT / "data" / "raw"


def get_database_url() -> str:
    user = os.getenv("POSTGRES_USER", "retailflow")
    password = os.getenv("POSTGRES_PASSWORD", "retailflow_password")
    host = os.getenv("POSTGRES_HOST", "localhost")
    port = os.getenv("POSTGRES_PORT", "5432")
    database = os.getenv("POSTGRES_DB", "retailflow")

    return (
        f"postgresql+psycopg2://{user}:{password}"
        f"@{host}:{port}/{database}"
    )
