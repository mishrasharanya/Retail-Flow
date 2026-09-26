from dataclasses import dataclass
from decimal import Decimal

from sqlalchemy import create_engine, text

from config import get_database_url


@dataclass(frozen=True)
class QualityCheck:
    name: str
    sql: str
    expected: Decimal = Decimal("0")


CHECKS = [
    QualityCheck(
        "customer dimension has one row per unique customer",
        "SELECT ABS((SELECT COUNT(*) FROM analytics.dim_customers) - "
        "(SELECT COUNT(DISTINCT customer_unique_id) FROM staging.customers))",
    ),
    QualityCheck(
        "product dimension matches staging products",
        "SELECT ABS((SELECT COUNT(*) FROM analytics.dim_products) - "
        "(SELECT COUNT(*) FROM staging.products))",
    ),
    QualityCheck(
        "seller dimension matches staging sellers",
        "SELECT ABS((SELECT COUNT(*) FROM analytics.dim_sellers) - "
        "(SELECT COUNT(*) FROM staging.sellers))",
    ),
    QualityCheck(
        "order fact matches staging orders",
        "SELECT ABS((SELECT COUNT(*) FROM analytics.fact_orders) - "
        "(SELECT COUNT(*) FROM staging.orders))",
    ),
    QualityCheck(
        "order item fact matches staging items",
        "SELECT ABS((SELECT COUNT(*) FROM analytics.fact_order_items) - "
        "(SELECT COUNT(*) FROM staging.order_items))",
    ),
    QualityCheck(
        "fact order item counts reconcile",
        "SELECT ABS((SELECT SUM(item_count) FROM analytics.fact_orders) - "
        "(SELECT COUNT(*) FROM analytics.fact_order_items))",
    ),
    QualityCheck(
        "fact payment total reconciles to staging",
        "SELECT ABS((SELECT SUM(payment_value) FROM analytics.fact_orders) - "
        "(SELECT SUM(payment_value) FROM staging.order_payments))",
    ),
    QualityCheck(
        "fact product value reconciles to staging",
        "SELECT ABS((SELECT SUM(product_value) FROM analytics.fact_orders) - "
        "(SELECT SUM(price) FROM staging.order_items))",
    ),
    QualityCheck(
        "fact freight value reconciles to staging",
        "SELECT ABS((SELECT SUM(freight_value) FROM analytics.fact_orders) - "
        "(SELECT SUM(freight_value) FROM staging.order_items))",
    ),
    QualityCheck(
        "order item total equals price plus freight",
        "SELECT COUNT(*) FROM analytics.fact_order_items "
        "WHERE item_total_value <> price + freight_value",
    ),
    QualityCheck(
        "analytics monetary values are nonnegative",
        "SELECT COUNT(*) FROM analytics.fact_orders WHERE product_value < 0 "
        "OR freight_value < 0 OR payment_value < 0",
    ),
    QualityCheck(
        "late-delivery flag is present for delivered orders with dates",
        "SELECT COUNT(*) FROM analytics.fact_orders "
        "WHERE order_status = 'delivered' "
        "AND order_delivered_customer_date IS NOT NULL AND is_late IS NULL",
    ),
    QualityCheck(
        "monthly order counts reconcile to delivered orders",
        "SELECT ABS((SELECT SUM(order_count) FROM analytics.monthly_sales) - "
        "(SELECT COUNT(*) FROM analytics.fact_orders "
        "WHERE order_status = 'delivered'))",
    ),
    QualityCheck(
        "monthly revenue reconciles to delivered revenue",
        "SELECT ABS((SELECT SUM(revenue) FROM analytics.monthly_sales) - "
        "(SELECT SUM(payment_value) FROM analytics.fact_orders "
        "WHERE order_status = 'delivered'))",
    ),
    QualityCheck(
        "state order counts reconcile to delivered orders",
        "SELECT ABS((SELECT SUM(order_count) FROM analytics.state_performance) - "
        "(SELECT COUNT(*) FROM analytics.fact_orders "
        "WHERE order_status = 'delivered'))",
    ),
    QualityCheck(
        "category item counts reconcile to order item facts",
        "SELECT ABS((SELECT SUM(items_sold) FROM analytics.category_performance) - "
        "(SELECT COUNT(*) FROM analytics.fact_order_items))",
    ),
    QualityCheck(
        "seller item counts reconcile to order item facts",
        "SELECT ABS((SELECT SUM(items_sold) FROM analytics.seller_performance) - "
        "(SELECT COUNT(*) FROM analytics.fact_order_items))",
    ),
    QualityCheck(
        "dashboard late rate is between zero and one",
        "SELECT COUNT(*) FROM analytics.dashboard_summary "
        "WHERE late_delivery_rate NOT BETWEEN 0 AND 1",
    ),
    QualityCheck(
        "dashboard average review is between one and five",
        "SELECT COUNT(*) FROM analytics.dashboard_summary "
        "WHERE average_review_score NOT BETWEEN 1 AND 5",
    ),
]


def main() -> None:
    engine = create_engine(get_database_url())
    failures = []

    with engine.connect() as connection:
        for check in CHECKS:
            actual = connection.execute(text(check.sql)).scalar_one()
            actual = Decimal(str(actual))
            status = "PASS" if actual == check.expected else "FAIL"

            if status == "FAIL":
                failures.append(check.name)

            print(
                f"{status:4} | {check.name} "
                f"| expected={check.expected} actual={actual}"
            )

    print(f"\nSummary: {len(CHECKS)} checks, {len(failures)} failures")

    if failures:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
