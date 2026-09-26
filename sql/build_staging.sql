BEGIN;

-- Drop child tables first because they reference parent tables.
DROP TABLE IF EXISTS staging.order_reviews;
DROP TABLE IF EXISTS staging.order_payments;
DROP TABLE IF EXISTS staging.order_items;
DROP TABLE IF EXISTS staging.orders;
DROP TABLE IF EXISTS staging.geolocation;
DROP TABLE IF EXISTS staging.sellers;
DROP TABLE IF EXISTS staging.products;
DROP TABLE IF EXISTS staging.customers;

CREATE TABLE staging.customers (
    customer_id TEXT PRIMARY KEY,
    customer_unique_id TEXT NOT NULL,
    customer_zip_code_prefix TEXT NOT NULL CHECK (customer_zip_code_prefix ~ '^[0-9]{5}$'),
    customer_city TEXT NOT NULL,
    customer_state TEXT NOT NULL CHECK (customer_state ~ '^[A-Z]{2}$'),
    source_loaded_at TIMESTAMPTZ NOT NULL,
    staged_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO staging.customers
    (customer_id, customer_unique_id, customer_zip_code_prefix,
     customer_city, customer_state, source_loaded_at)
SELECT TRIM(customer_id), TRIM(customer_unique_id),
       TRIM(customer_zip_code_prefix), LOWER(TRIM(customer_city)),
       UPPER(TRIM(customer_state)), loaded_at
FROM raw.customers;

CREATE TABLE staging.products (
    product_id TEXT PRIMARY KEY,
    product_category_name_original TEXT,
    product_category_name TEXT NOT NULL,
    product_name_length INTEGER,
    product_description_length INTEGER,
    product_photos_qty INTEGER,
    product_weight_g NUMERIC(12,2),
    product_length_cm NUMERIC(12,2),
    product_height_cm NUMERIC(12,2),
    product_width_cm NUMERIC(12,2),
    source_loaded_at TIMESTAMPTZ NOT NULL,
    staged_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO staging.products
SELECT TRIM(p.product_id), NULLIF(TRIM(p.product_category_name), ''),
       COALESCE(NULLIF(TRIM(t.product_category_name_english), ''),
                NULLIF(TRIM(p.product_category_name), ''), 'unknown'),
       NULLIF(p.product_name_lenght, '')::NUMERIC::INTEGER,
       NULLIF(p.product_description_lenght, '')::NUMERIC::INTEGER,
       NULLIF(p.product_photos_qty, '')::NUMERIC::INTEGER,
       NULLIF(p.product_weight_g, '')::NUMERIC(12,2),
       NULLIF(p.product_length_cm, '')::NUMERIC(12,2),
       NULLIF(p.product_height_cm, '')::NUMERIC(12,2),
       NULLIF(p.product_width_cm, '')::NUMERIC(12,2),
       p.loaded_at, CURRENT_TIMESTAMP
FROM raw.products p
LEFT JOIN raw.product_category_translation t
  ON p.product_category_name = t.product_category_name;

CREATE TABLE staging.sellers (
    seller_id TEXT PRIMARY KEY,
    seller_zip_code_prefix TEXT NOT NULL CHECK (seller_zip_code_prefix ~ '^[0-9]{5}$'),
    seller_city TEXT NOT NULL,
    seller_state TEXT NOT NULL CHECK (seller_state ~ '^[A-Z]{2}$'),
    source_loaded_at TIMESTAMPTZ NOT NULL,
    staged_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO staging.sellers
SELECT TRIM(seller_id), TRIM(seller_zip_code_prefix),
       LOWER(TRIM(seller_city)), UPPER(TRIM(seller_state)),
       loaded_at, CURRENT_TIMESTAMP
FROM raw.sellers;

-- Raw geolocation contains many observations per ZIP prefix.
-- Staging publishes one representative record per ZIP prefix.
CREATE TABLE staging.geolocation (
    geolocation_zip_code_prefix TEXT PRIMARY KEY CHECK (geolocation_zip_code_prefix ~ '^[0-9]{5}$'),
    geolocation_lat NUMERIC(10,7) NOT NULL,
    geolocation_lng NUMERIC(10,7) NOT NULL,
    geolocation_city TEXT NOT NULL,
    geolocation_state TEXT NOT NULL CHECK (geolocation_state ~ '^[A-Z]{2}$'),
    source_loaded_at TIMESTAMPTZ NOT NULL,
    staged_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO staging.geolocation
SELECT TRIM(geolocation_zip_code_prefix),
       AVG(geolocation_lat::NUMERIC)::NUMERIC(10,7),
       AVG(geolocation_lng::NUMERIC)::NUMERIC(10,7),
       MODE() WITHIN GROUP (ORDER BY LOWER(TRIM(geolocation_city))),
       MODE() WITHIN GROUP (ORDER BY UPPER(TRIM(geolocation_state))),
       MAX(loaded_at), CURRENT_TIMESTAMP
FROM raw.geolocation
GROUP BY TRIM(geolocation_zip_code_prefix);

CREATE TABLE staging.orders (
    order_id TEXT PRIMARY KEY,
    customer_id TEXT NOT NULL REFERENCES staging.customers(customer_id),
    order_status TEXT NOT NULL CHECK (
        order_status IN ('approved', 'canceled', 'created', 'delivered',
                         'invoiced', 'processing', 'shipped', 'unavailable')
    ),
    order_purchase_timestamp TIMESTAMP NOT NULL,
    order_approved_at TIMESTAMP,
    order_delivered_carrier_date TIMESTAMP,
    order_delivered_customer_date TIMESTAMP,
    order_estimated_delivery_date TIMESTAMP NOT NULL,
    source_loaded_at TIMESTAMPTZ NOT NULL,
    staged_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO staging.orders
SELECT TRIM(order_id), TRIM(customer_id), LOWER(TRIM(order_status)),
       order_purchase_timestamp::TIMESTAMP,
       NULLIF(order_approved_at, '')::TIMESTAMP,
       NULLIF(order_delivered_carrier_date, '')::TIMESTAMP,
       NULLIF(order_delivered_customer_date, '')::TIMESTAMP,
       order_estimated_delivery_date::TIMESTAMP,
       loaded_at, CURRENT_TIMESTAMP
FROM raw.orders;

CREATE TABLE staging.order_items (
    order_id TEXT NOT NULL REFERENCES staging.orders(order_id),
    order_item_id INTEGER NOT NULL,
    product_id TEXT NOT NULL REFERENCES staging.products(product_id),
    seller_id TEXT NOT NULL REFERENCES staging.sellers(seller_id),
    shipping_limit_date TIMESTAMP NOT NULL,
    price NUMERIC(12,2) NOT NULL CHECK (price >= 0),
    freight_value NUMERIC(12,2) NOT NULL CHECK (freight_value >= 0),
    source_loaded_at TIMESTAMPTZ NOT NULL,
    staged_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (order_id, order_item_id)
);

INSERT INTO staging.order_items
SELECT TRIM(order_id), order_item_id::INTEGER, TRIM(product_id),
       TRIM(seller_id), shipping_limit_date::TIMESTAMP,
       price::NUMERIC(12,2), freight_value::NUMERIC(12,2),
       loaded_at, CURRENT_TIMESTAMP
FROM raw.order_items;

CREATE TABLE staging.order_payments (
    order_id TEXT NOT NULL REFERENCES staging.orders(order_id),
    payment_sequential INTEGER NOT NULL,
    payment_type TEXT NOT NULL,
    payment_installments INTEGER NOT NULL CHECK (payment_installments >= 0),
    payment_value NUMERIC(12,2) NOT NULL CHECK (payment_value >= 0),
    source_loaded_at TIMESTAMPTZ NOT NULL,
    staged_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (order_id, payment_sequential)
);

INSERT INTO staging.order_payments
SELECT TRIM(order_id), payment_sequential::INTEGER,
       LOWER(TRIM(payment_type)), payment_installments::INTEGER,
       payment_value::NUMERIC(12,2), loaded_at, CURRENT_TIMESTAMP
FROM raw.order_payments;

CREATE TABLE staging.order_reviews (
    review_id TEXT NOT NULL,
    order_id TEXT NOT NULL REFERENCES staging.orders(order_id),
    review_score INTEGER NOT NULL CHECK (review_score BETWEEN 1 AND 5),
    review_comment_title TEXT,
    review_comment_message TEXT,
    review_creation_date TIMESTAMP NOT NULL,
    review_answer_timestamp TIMESTAMP NOT NULL,
    source_loaded_at TIMESTAMPTZ NOT NULL,
    staged_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (review_id, order_id)
);

INSERT INTO staging.order_reviews
SELECT TRIM(review_id), TRIM(order_id), review_score::INTEGER,
       NULLIF(TRIM(review_comment_title), ''),
       NULLIF(TRIM(review_comment_message), ''),
       review_creation_date::TIMESTAMP,
       review_answer_timestamp::TIMESTAMP,
       loaded_at, CURRENT_TIMESTAMP
FROM raw.order_reviews;

COMMIT;
