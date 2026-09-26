BEGIN;

DROP VIEW IF EXISTS analytics.dashboard_summary;
DROP VIEW IF EXISTS analytics.seller_performance;
DROP VIEW IF EXISTS analytics.state_performance;
DROP VIEW IF EXISTS analytics.category_performance;
DROP VIEW IF EXISTS analytics.monthly_sales;
DROP TABLE IF EXISTS analytics.fact_order_items;
DROP TABLE IF EXISTS analytics.fact_orders;
DROP TABLE IF EXISTS analytics.dim_sellers;
DROP TABLE IF EXISTS analytics.dim_products;
DROP TABLE IF EXISTS analytics.dim_customers;

-- One row per real customer, using the latest observed order location.
CREATE TABLE analytics.dim_customers (
    customer_unique_id TEXT PRIMARY KEY,
    latest_zip_code_prefix TEXT NOT NULL,
    latest_city TEXT NOT NULL,
    latest_state TEXT NOT NULL,
    first_order_at TIMESTAMP NOT NULL,
    last_order_at TIMESTAMP NOT NULL,
    lifetime_order_count INTEGER NOT NULL CHECK (lifetime_order_count > 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

WITH customer_orders AS (
    SELECT c.customer_unique_id, c.customer_zip_code_prefix,
           c.customer_city, c.customer_state, o.order_id,
           o.order_purchase_timestamp,
           ROW_NUMBER() OVER (
               PARTITION BY c.customer_unique_id
               ORDER BY o.order_purchase_timestamp DESC, o.order_id DESC
           ) AS location_rank
    FROM staging.customers c
    JOIN staging.orders o ON c.customer_id = o.customer_id
),
customer_history AS (
    SELECT customer_unique_id,
           MIN(order_purchase_timestamp) AS first_order_at,
           MAX(order_purchase_timestamp) AS last_order_at,
           COUNT(*)::INTEGER AS lifetime_order_count
    FROM customer_orders
    GROUP BY customer_unique_id
)
INSERT INTO analytics.dim_customers
SELECT h.customer_unique_id, latest.customer_zip_code_prefix,
       latest.customer_city, latest.customer_state,
       h.first_order_at, h.last_order_at, h.lifetime_order_count,
       CURRENT_TIMESTAMP
FROM customer_history h
JOIN customer_orders latest
  ON h.customer_unique_id = latest.customer_unique_id
 AND latest.location_rank = 1;

-- One row per product.
CREATE TABLE analytics.dim_products (
    product_id TEXT PRIMARY KEY,
    product_category_name TEXT NOT NULL,
    product_category_name_original TEXT,
    product_weight_g NUMERIC(12,2),
    product_length_cm NUMERIC(12,2),
    product_height_cm NUMERIC(12,2),
    product_width_cm NUMERIC(12,2),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO analytics.dim_products
SELECT product_id, product_category_name, product_category_name_original,
       product_weight_g, product_length_cm, product_height_cm,
       product_width_cm, CURRENT_TIMESTAMP
FROM staging.products;

-- One row per seller.
CREATE TABLE analytics.dim_sellers (
    seller_id TEXT PRIMARY KEY,
    seller_zip_code_prefix TEXT NOT NULL,
    seller_city TEXT NOT NULL,
    seller_state TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO analytics.dim_sellers
SELECT seller_id, seller_zip_code_prefix, seller_city, seller_state,
       CURRENT_TIMESTAMP
FROM staging.sellers;

-- One row per order. Child-table measures are aggregated before joining
-- so orders with multiple items, payments, or reviews are not multiplied.
CREATE TABLE analytics.fact_orders (
    order_id TEXT PRIMARY KEY,
    customer_unique_id TEXT NOT NULL REFERENCES analytics.dim_customers(customer_unique_id),
    customer_state TEXT NOT NULL,
    order_status TEXT NOT NULL,
    order_purchase_timestamp TIMESTAMP NOT NULL,
    order_approved_at TIMESTAMP,
    order_delivered_customer_date TIMESTAMP,
    order_estimated_delivery_date TIMESTAMP NOT NULL,
    item_count INTEGER NOT NULL,
    product_value NUMERIC(14,2) NOT NULL,
    freight_value NUMERIC(14,2) NOT NULL,
    payment_value NUMERIC(14,2) NOT NULL,
    average_review_score NUMERIC(3,2),
    delivery_days NUMERIC(10,2),
    is_late BOOLEAN,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

WITH item_totals AS (
    SELECT order_id, COUNT(*)::INTEGER AS item_count,
           SUM(price)::NUMERIC(14,2) AS product_value,
           SUM(freight_value)::NUMERIC(14,2) AS freight_value
    FROM staging.order_items
    GROUP BY order_id
),
payment_totals AS (
    SELECT order_id, SUM(payment_value)::NUMERIC(14,2) AS payment_value
    FROM staging.order_payments
    GROUP BY order_id
),
review_totals AS (
    SELECT order_id, AVG(review_score)::NUMERIC(3,2) AS average_review_score
    FROM staging.order_reviews
    GROUP BY order_id
)
INSERT INTO analytics.fact_orders
SELECT o.order_id, c.customer_unique_id, c.customer_state, o.order_status,
       o.order_purchase_timestamp, o.order_approved_at,
       o.order_delivered_customer_date, o.order_estimated_delivery_date,
       COALESCE(i.item_count, 0), COALESCE(i.product_value, 0),
       COALESCE(i.freight_value, 0), COALESCE(p.payment_value, 0),
       r.average_review_score,
       CASE WHEN o.order_delivered_customer_date IS NOT NULL
            THEN (EXTRACT(EPOCH FROM (
                o.order_delivered_customer_date - o.order_purchase_timestamp
            )) / 86400)::NUMERIC(10,2)
       END,
       CASE WHEN o.order_delivered_customer_date IS NOT NULL
            THEN o.order_delivered_customer_date > o.order_estimated_delivery_date
       END,
       CURRENT_TIMESTAMP
FROM staging.orders o
JOIN staging.customers c ON o.customer_id = c.customer_id
LEFT JOIN item_totals i ON o.order_id = i.order_id
LEFT JOIN payment_totals p ON o.order_id = p.order_id
LEFT JOIN review_totals r ON o.order_id = r.order_id;

CREATE INDEX fact_orders_purchase_timestamp_idx
    ON analytics.fact_orders(order_purchase_timestamp);
CREATE INDEX fact_orders_customer_idx
    ON analytics.fact_orders(customer_unique_id);

-- One row per purchased order item.
CREATE TABLE analytics.fact_order_items (
    order_id TEXT NOT NULL REFERENCES analytics.fact_orders(order_id),
    order_item_id INTEGER NOT NULL,
    product_id TEXT NOT NULL REFERENCES analytics.dim_products(product_id),
    seller_id TEXT NOT NULL REFERENCES analytics.dim_sellers(seller_id),
    shipping_limit_date TIMESTAMP NOT NULL,
    price NUMERIC(12,2) NOT NULL,
    freight_value NUMERIC(12,2) NOT NULL,
    item_total_value NUMERIC(12,2) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (order_id, order_item_id)
);

INSERT INTO analytics.fact_order_items
SELECT order_id, order_item_id, product_id, seller_id,
       shipping_limit_date, price, freight_value,
       (price + freight_value)::NUMERIC(12,2), CURRENT_TIMESTAMP
FROM staging.order_items;

CREATE INDEX fact_order_items_product_idx
    ON analytics.fact_order_items(product_id);
CREATE INDEX fact_order_items_seller_idx
    ON analytics.fact_order_items(seller_id);

-- Dashboard-ready reporting views.
CREATE VIEW analytics.monthly_sales AS
SELECT DATE_TRUNC('month', order_purchase_timestamp)::DATE AS order_month,
       COUNT(*) AS order_count,
       SUM(payment_value)::NUMERIC(16,2) AS revenue,
       AVG(payment_value)::NUMERIC(12,2) AS average_order_value,
       AVG(average_review_score)::NUMERIC(3,2) AS average_review_score,
       AVG(is_late::INTEGER)::NUMERIC(7,4) AS late_delivery_rate
FROM analytics.fact_orders
WHERE order_status = 'delivered'
GROUP BY 1;

CREATE VIEW analytics.category_performance AS
SELECT p.product_category_name,
       COUNT(*) AS items_sold,
       COUNT(DISTINCT i.order_id) AS order_count,
       SUM(i.price)::NUMERIC(16,2) AS product_revenue,
       AVG(o.average_review_score)::NUMERIC(3,2) AS average_review_score
FROM analytics.fact_order_items i
JOIN analytics.dim_products p ON i.product_id = p.product_id
JOIN analytics.fact_orders o ON i.order_id = o.order_id
GROUP BY p.product_category_name;

CREATE VIEW analytics.state_performance AS
SELECT o.customer_state,
       COUNT(*) AS order_count,
       SUM(o.payment_value)::NUMERIC(16,2) AS revenue,
       AVG(o.payment_value)::NUMERIC(12,2) AS average_order_value,
       AVG(o.is_late::INTEGER)::NUMERIC(7,4) AS late_delivery_rate
FROM analytics.fact_orders o
WHERE o.order_status = 'delivered'
GROUP BY o.customer_state;

CREATE VIEW analytics.seller_performance AS
SELECT s.seller_id, s.seller_city, s.seller_state,
       COUNT(DISTINCT i.order_id) AS order_count,
       COUNT(*) AS items_sold,
       SUM(i.price)::NUMERIC(16,2) AS product_revenue,
       AVG(o.average_review_score)::NUMERIC(3,2) AS average_review_score
FROM analytics.fact_order_items i
JOIN analytics.dim_sellers s ON i.seller_id = s.seller_id
JOIN analytics.fact_orders o ON i.order_id = o.order_id
GROUP BY s.seller_id, s.seller_city, s.seller_state;

CREATE VIEW analytics.dashboard_summary AS
SELECT COUNT(*) AS delivered_orders,
       COUNT(DISTINCT customer_unique_id) AS customers,
       SUM(payment_value)::NUMERIC(16,2) AS revenue,
       AVG(payment_value)::NUMERIC(12,2) AS average_order_value,
       AVG(average_review_score)::NUMERIC(3,2) AS average_review_score,
       AVG(is_late::INTEGER)::NUMERIC(7,4) AS late_delivery_rate,
       AVG(delivery_days)::NUMERIC(10,2) AS average_delivery_days
FROM analytics.fact_orders
WHERE order_status = 'delivered';

COMMIT;
