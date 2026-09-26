from sqlalchemy import create_engine, text

from config import get_database_url

engine = create_engine(get_database_url())

with engine.connect() as connection:
    result = connection.execute(
        text("SELECT current_database(), current_user")
    ).one()

print("Connected successfully")
print(f"Database: {result[0]}")
print(f"User: {result[1]}")
