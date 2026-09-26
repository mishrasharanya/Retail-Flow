import pandas as pd
from sqlalchemy import create_engine, text

from config import RAW_DATA_DIR, get_database_url


DATASETS = {
    "olist_customers_dataset.csv": {
        "table": "customers",
        "columns": [
            "customer_id",
            "customer_unique_id",
            "customer_zip_code_prefix",
            "customer_city",
            "customer_state",
        ],
    },
    "olist_geolocation_dataset.csv": {
        "table": "geolocation",
        "columns": [
            "geolocation_zip_code_prefix",
            "geolocation_lat",
            "geolocation_lng",
            "geolocation_city",
            "geolocation_state",
        ],
    },
    "olist_order_items_dataset.csv": {
        "table": "order_items",
        "columns": [
            "order_id",
            "order_item_id",
            "product_id",
            "seller_id",
            "shipping_limit_date",
            "price",
            "freight_value",
        ],
    },
    "olist_order_payments_dataset.csv": {
        "table": "order_payments",
        "columns": [
            "order_id",
            "payment_sequential",
            "payment_type",
            "payment_installments",
            "payment_value",
        ],
    },
    "olist_order_reviews_dataset.csv": {
        "table": "order_reviews",
        "columns": [
            "review_id",
            "order_id",
            "review_score",
            "review_comment_title",
            "review_comment_message",
            "review_creation_date",
            "review_answer_timestamp",
        ],
    },
    "olist_orders_dataset.csv": {
        "table": "orders",
        "columns": [
            "order_id",
            "customer_id",
            "order_status",
            "order_purchase_timestamp",
            "order_approved_at",
            "order_delivered_carrier_date",
            "order_delivered_customer_date",
            "order_estimated_delivery_date",
        ],
    },
    "olist_products_dataset.csv": {
        "table": "products",
        "columns": [
            "product_id",
            "product_category_name",
            "product_name_lenght",
            "product_description_lenght",
            "product_photos_qty",
            "product_weight_g",
            "product_length_cm",
            "product_height_cm",
            "product_width_cm",
        ],
    },
    "olist_sellers_dataset.csv": {
        "table": "sellers",
        "columns": [
            "seller_id",
            "seller_zip_code_prefix",
            "seller_city",
            "seller_state",
        ],
    },
    "product_category_name_translation.csv": {
        "table": "product_category_translation",
        "columns": [
            "product_category_name",
            "product_category_name_english",
        ],
    },
}


def validate_header(csv_path, expected_columns):
    actual_columns = pd.read_csv(
        csv_path,
        encoding="utf-8-sig",
        nrows=0,
    ).columns.tolist()

    if actual_columns != expected_columns:
        raise ValueError(
            f"Unexpected columns in {csv_path.name}. "
            f"Expected {expected_columns}, got {actual_columns}"
        )


def load_dataset(connection, filename, dataset, chunk_size=50_000):
    csv_path = RAW_DATA_DIR / filename
    table_name = dataset["table"]
    expected_columns = dataset["columns"]

    if not csv_path.exists():
        raise FileNotFoundError(f"Source file not found: {csv_path}")

    validate_header(csv_path, expected_columns)
    connection.execute(text(f"TRUNCATE TABLE raw.{table_name}"))

    loaded_rows = 0
    chunks = pd.read_csv(
        csv_path,
        encoding="utf-8-sig",
        dtype=str,
        chunksize=chunk_size,
    )

    for chunk in chunks:
        chunk["source_file"] = filename
        chunk.to_sql(
            name=table_name,
            schema="raw",
            con=connection,
            if_exists="append",
            index=False,
        )
        loaded_rows += len(chunk)
        print(f"  {table_name}: loaded {loaded_rows:,} rows")

    database_rows = connection.execute(
        text(f"SELECT COUNT(*) FROM raw.{table_name}")
    ).scalar_one()

    if database_rows != loaded_rows:
        raise RuntimeError(
            f"Row-count mismatch for raw.{table_name}: "
            f"CSV={loaded_rows}, database={database_rows}"
        )

    print(f"PASS raw.{table_name}: {database_rows:,} rows")


def main():
    engine = create_engine(get_database_url())

    with engine.begin() as connection:
        for filename, dataset in DATASETS.items():
            print(f"Loading {filename}")
            load_dataset(connection, filename, dataset)

    print("All raw datasets loaded successfully")


if __name__ == "__main__":
    main()
