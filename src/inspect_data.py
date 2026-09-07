import pandas as pd
from pathlib import Path


DATA_DIR = Path("data/raw")


def inspect_file(file_path):
    df = pd.read_csv(file_path)

    print("\n" + "=" * 70)
    print(f"FILE: {file_path.name}")
    print("=" * 70)

    print(f"\nRows: {df.shape[0]}")
    print(f"Columns: {df.shape[1]}")

    print("\nCOLUMN NAMES:")
    print(df.columns.tolist())

    print("\nDATA TYPES:")
    print(df.dtypes)

    print("\nMISSING VALUES:")
    print(df.isnull().sum())

    print("\nDUPLICATE ROWS:")
    print(df.duplicated().sum())

    print("\nFIRST 5 ROWS:")
    print(df.head())


def main():
    csv_files = sorted(DATA_DIR.glob("*.csv"))

    if not csv_files:
        print("No CSV files found in data/raw")
        return

    for file_path in csv_files:
        inspect_file(file_path)


if __name__ == "__main__":
    main()