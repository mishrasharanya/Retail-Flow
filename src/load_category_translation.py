from sqlalchemy import create_engine, text

from config import get_database_url
from validate_category_translation import csv_path, validate_csv

data = validate_csv()
data["source_file"] = csv_path.name

engine = create_engine(get_database_url())

with engine.begin() as connection:
    connection.execute(text("TRUNCATE TABLE raw.product_category_translation"))

    data.to_sql(
        name="product_category_translation",
        schema="raw",
        con=connection,
        if_exists="append",
        index=False,
    )

    database_row_count = connection.execute(
        text("SELECT COUNT(*) FROM raw.product_category_translation")
    ).scalar_one()

    if database_row_count != len(data):
        raise RuntimeError(
            f"Row-count mismatch: CSV={len(data)}, database={database_row_count}"
        )

print(f"Loaded {database_row_count} rows into raw.product_category_translation")
