from datetime import datetime, timezone
import json

import pandas as pd
from sqlalchemy import create_engine, text

from config import PROJECT_ROOT, get_database_url


OUTPUT_DIR = PROJECT_ROOT / "dashboard" / "data"

EXPORTS = {
    "dashboard_summary.json": "SELECT * FROM analytics.dashboard_summary",
    "monthly_sales.json": """
        SELECT * FROM analytics.monthly_sales
        ORDER BY order_month
    """,
    "category_performance.json": """
        SELECT * FROM analytics.category_performance
        ORDER BY product_revenue DESC
        LIMIT 15
    """,
    "state_performance.json": """
        SELECT * FROM analytics.state_performance
        ORDER BY revenue DESC
    """,
    "seller_performance.json": """
        SELECT * FROM analytics.seller_performance
        ORDER BY product_revenue DESC
        LIMIT 10
    """,
}


def main() -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    engine = create_engine(get_database_url())

    with engine.connect() as connection:
        for filename, query in EXPORTS.items():
            data = pd.read_sql(text(query), connection)
            output_path = OUTPUT_DIR / filename
            data.to_json(
                output_path,
                orient="records",
                date_format="iso",
                indent=2,
            )
            print(f"Exported {len(data):,} rows to {output_path}")

    metadata = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "source": "RetailFlow PostgreSQL analytics layer",
    }
    (OUTPUT_DIR / "metadata.json").write_text(
        json.dumps(metadata, indent=2),
        encoding="utf-8",
    )

    engine.dispose()
    print("Dashboard export completed")


if __name__ == "__main__":
    main()
