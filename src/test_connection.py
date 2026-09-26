import os

from sqlalchemy import create_engine, text


user = os.getenv("POSTGRES_USER", "retailflow")
password = os.getenv("POSTGRES_PASSWORD", "retailflow_password")
host = os.getenv("POSTGRES_HOST", "localhost")
port = os.getenv("POSTGRES_PORT", "5432")
database = os.getenv("POSTGRES_DB", "retailflow")

database_url = (
    f"postgresql+psycopg2://{user}:{password}@{host}:{port}/{database}"
)

engine = create_engine(database_url)

with engine.connect() as connection:
    result = connection.execute(
        text("SELECT current_database(), current_user")
    ).one()

print("Connected successfully")
print(f"Database: {result[0]}")
print(f"User: {result[1]}")
