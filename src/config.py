import os
from pathlib import Path

from dotenv import load_dotenv
from sqlalchemy.engine import URL


PROJECT_ROOT = Path(__file__).resolve().parents[1]
RAW_DATA_DIR = PROJECT_ROOT / "data" / "raw"
load_dotenv(PROJECT_ROOT / ".env")


def get_database_url() -> URL:
    user = os.getenv("POSTGRES_USER", "retailflow")
    password = os.getenv("POSTGRES_PASSWORD")
    host = os.getenv("POSTGRES_HOST", "localhost")
    port = os.getenv("POSTGRES_PORT", "5432")
    database = os.getenv("POSTGRES_DB", "retailflow")

    if not password:
        raise RuntimeError(
            "POSTGRES_PASSWORD is required. Copy .env.example to .env "
            "and set a local password."
        )

    return URL.create(
        drivername="postgresql+psycopg2",
        username=user,
        password=password,
        host=host,
        port=int(port),
        database=database,
    )
