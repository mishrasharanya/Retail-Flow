from pathlib import Path

import pandas as pd


project_root = Path(__file__).resolve().parents[1]
csv_path = project_root / "data" / "raw" / "product_category_name_translation.csv"

REQUIRED_COLUMNS = [
    "product_category_name",
    "product_category_name_english",
]


def validate_csv() -> pd.DataFrame:
    data = pd.read_csv(csv_path, encoding="utf-8-sig")

    missing_columns = set(REQUIRED_COLUMNS) - set(data.columns)
    if missing_columns:
        raise ValueError(f"Missing required columns: {sorted(missing_columns)}")

    null_counts = data[REQUIRED_COLUMNS].isna().sum()
    duplicate_keys = data["product_category_name"].duplicated().sum()

    if null_counts.sum() > 0:
        raise ValueError(f"Required columns contain nulls:\n{null_counts}")

    if duplicate_keys > 0:
        raise ValueError(
            f"Found {duplicate_keys} duplicate product category keys"
        )

    print("CSV validation passed")
    print(f"File: {csv_path.name}")
    print(f"Rows: {len(data)}")
    print(f"Columns: {data.columns.tolist()}")
    print(f"Null values: {int(null_counts.sum())}")
    print(f"Duplicate category keys: {duplicate_keys}")
    return data


if __name__ == "__main__":
    validate_csv()
