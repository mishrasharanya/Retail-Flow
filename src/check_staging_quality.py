from dataclasses import dataclass

from sqlalchemy import create_engine, text

from config import get_database_url


@dataclass(frozen=True)
class QualityCheck:
    name: str
    sql: str
    severity: str = "FAIL"
    expected: int = 0


CHECKS = [
    # Row-count reconciliation for one-to-one staging models.
    QualityCheck(
        "customer raw/staging row counts match",
        "SELECT ABS((SELECT COUNT(*) FROM raw.customers) - "
        "(SELECT COUNT(*) FROM staging.customers))",
    ),
    QualityCheck(
        "order raw/staging row counts match",
        "SELECT ABS((SELECT COUNT(*) FROM raw.orders) - "
        "(SELECT COUNT(*) FROM staging.orders))",
    ),
    QualityCheck(
        "order item raw/staging row counts match",
        "SELECT ABS((SELECT COUNT(*) FROM raw.order_items) - "
        "(SELECT COUNT(*) FROM staging.order_items))",
    ),
    QualityCheck(
        "payment raw/staging row counts match",
        "SELECT ABS((SELECT COUNT(*) FROM raw.order_payments) - "
        "(SELECT COUNT(*) FROM staging.order_payments))",
    ),
    QualityCheck(
        "review raw/staging row counts match",
        "SELECT ABS((SELECT COUNT(*) FROM raw.order_reviews) - "
        "(SELECT COUNT(*) FROM staging.order_reviews))",
    ),
    QualityCheck(
        "product raw/staging row counts match",
        "SELECT ABS((SELECT COUNT(*) FROM raw.products) - "
        "(SELECT COUNT(*) FROM staging.products))",
    ),
    QualityCheck(
        "seller raw/staging row counts match",
        "SELECT ABS((SELECT COUNT(*) FROM raw.sellers) - "
        "(SELECT COUNT(*) FROM staging.sellers))",
    ),

    # Required keys and uniqueness.
    QualityCheck(
        "customer IDs are not null",
        "SELECT COUNT(*) FROM staging.customers WHERE customer_id IS NULL",
    ),
    QualityCheck(
        "order IDs are not null",
        "SELECT COUNT(*) FROM staging.orders WHERE order_id IS NULL",
    ),
    QualityCheck(
        "customer IDs are unique",
        "SELECT COUNT(*) FROM (SELECT customer_id FROM staging.customers "
        "GROUP BY customer_id HAVING COUNT(*) > 1) duplicates",
    ),
    QualityCheck(
        "order IDs are unique",
        "SELECT COUNT(*) FROM (SELECT order_id FROM staging.orders "
        "GROUP BY order_id HAVING COUNT(*) > 1) duplicates",
    ),

    # Referential integrity: these counts identify orphan child rows.
    QualityCheck(
        "orders have customers",
        "SELECT COUNT(*) FROM staging.orders o LEFT JOIN staging.customers c "
        "ON o.customer_id = c.customer_id WHERE c.customer_id IS NULL",
    ),
    QualityCheck(
        "order items have orders",
        "SELECT COUNT(*) FROM staging.order_items i LEFT JOIN staging.orders o "
        "ON i.order_id = o.order_id WHERE o.order_id IS NULL",
    ),
    QualityCheck(
        "order items have products",
        "SELECT COUNT(*) FROM staging.order_items i LEFT JOIN staging.products p "
        "ON i.product_id = p.product_id WHERE p.product_id IS NULL",
    ),
    QualityCheck(
        "order items have sellers",
        "SELECT COUNT(*) FROM staging.order_items i LEFT JOIN staging.sellers s "
        "ON i.seller_id = s.seller_id WHERE s.seller_id IS NULL",
    ),
    QualityCheck(
        "payments have orders",
        "SELECT COUNT(*) FROM staging.order_payments p LEFT JOIN staging.orders o "
        "ON p.order_id = o.order_id WHERE o.order_id IS NULL",
    ),
    QualityCheck(
        "reviews have orders",
        "SELECT COUNT(*) FROM staging.order_reviews r LEFT JOIN staging.orders o "
        "ON r.order_id = o.order_id WHERE o.order_id IS NULL",
    ),

    # Accepted values and numeric ranges.
    QualityCheck(
        "review scores are between 1 and 5",
        "SELECT COUNT(*) FROM staging.order_reviews "
        "WHERE review_score NOT BETWEEN 1 AND 5",
    ),
    QualityCheck(
        "item prices and freight are nonnegative",
        "SELECT COUNT(*) FROM staging.order_items "
        "WHERE price < 0 OR freight_value < 0",
    ),
    QualityCheck(
        "payment values are nonnegative",
        "SELECT COUNT(*) FROM staging.order_payments WHERE payment_value < 0",
    ),
    QualityCheck(
        "product measurements are nonnegative",
        "SELECT COUNT(*) FROM staging.products WHERE product_weight_g < 0 "
        "OR product_length_cm < 0 OR product_height_cm < 0 "
        "OR product_width_cm < 0",
    ),

    # Warnings are measured and reported but do not stop the pipeline.
    QualityCheck(
        "products use unknown category",
        "SELECT COUNT(*) FROM staging.products "
        "WHERE product_category_name = 'unknown'",
        severity="WARN",
    ),
    QualityCheck(
        "customer ZIP prefixes lack geolocation",
        "SELECT COUNT(*) FROM staging.customers c LEFT JOIN staging.geolocation g "
        "ON c.customer_zip_code_prefix = g.geolocation_zip_code_prefix "
        "WHERE g.geolocation_zip_code_prefix IS NULL",
        severity="WARN",
    ),
    QualityCheck(
        "seller ZIP prefixes lack geolocation",
        "SELECT COUNT(*) FROM staging.sellers s LEFT JOIN staging.geolocation g "
        "ON s.seller_zip_code_prefix = g.geolocation_zip_code_prefix "
        "WHERE g.geolocation_zip_code_prefix IS NULL",
        severity="WARN",
    ),
    QualityCheck(
        "orders have no payment record",
        "SELECT COUNT(*) FROM staging.orders o LEFT JOIN staging.order_payments p "
        "ON o.order_id = p.order_id WHERE p.order_id IS NULL",
        severity="WARN",
    ),
    QualityCheck(
        "delivered orders lack customer delivery timestamp",
        "SELECT COUNT(*) FROM staging.orders WHERE order_status = 'delivered' "
        "AND order_delivered_customer_date IS NULL",
        severity="WARN",
    ),
    QualityCheck(
        "order approval occurs before purchase",
        "SELECT COUNT(*) FROM staging.orders WHERE order_approved_at IS NOT NULL "
        "AND order_approved_at < order_purchase_timestamp",
        severity="WARN",
    ),
    QualityCheck(
        "customer delivery occurs before purchase",
        "SELECT COUNT(*) FROM staging.orders "
        "WHERE order_delivered_customer_date IS NOT NULL "
        "AND order_delivered_customer_date < order_purchase_timestamp",
        severity="WARN",
    ),
]


def main() -> None:
    engine = create_engine(get_database_url())
    failures = []
    warning_count = 0

    with engine.connect() as connection:
        for check in CHECKS:
            actual = connection.execute(text(check.sql)).scalar_one()

            if actual == check.expected:
                status = "PASS"
            elif check.severity == "WARN":
                status = "WARN"
                warning_count += 1
            else:
                status = "FAIL"
                failures.append(check.name)

            print(
                f"{status:4} | {check.name} "
                f"| expected={check.expected} actual={actual}"
            )

    print(
        f"\nSummary: {len(CHECKS)} checks, "
        f"{len(failures)} failures, {warning_count} warnings"
    )

    if failures:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
