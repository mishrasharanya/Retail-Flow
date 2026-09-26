-- 1. Row counts and ingestion lineage
SELECT 'customers' AS table_name, COUNT(*) AS row_count,
       COUNT(*) FILTER (WHERE source_file IS NULL) AS missing_source_file,
       COUNT(*) FILTER (WHERE loaded_at IS NULL) AS missing_loaded_at
FROM raw.customers
UNION ALL
SELECT 'geolocation', COUNT(*), COUNT(*) FILTER (WHERE source_file IS NULL), COUNT(*) FILTER (WHERE loaded_at IS NULL) FROM raw.geolocation
UNION ALL
SELECT 'order_items', COUNT(*), COUNT(*) FILTER (WHERE source_file IS NULL), COUNT(*) FILTER (WHERE loaded_at IS NULL) FROM raw.order_items
UNION ALL
SELECT 'order_payments', COUNT(*), COUNT(*) FILTER (WHERE source_file IS NULL), COUNT(*) FILTER (WHERE loaded_at IS NULL) FROM raw.order_payments
UNION ALL
SELECT 'order_reviews', COUNT(*), COUNT(*) FILTER (WHERE source_file IS NULL), COUNT(*) FILTER (WHERE loaded_at IS NULL) FROM raw.order_reviews
UNION ALL
SELECT 'orders', COUNT(*), COUNT(*) FILTER (WHERE source_file IS NULL), COUNT(*) FILTER (WHERE loaded_at IS NULL) FROM raw.orders
UNION ALL
SELECT 'products', COUNT(*), COUNT(*) FILTER (WHERE source_file IS NULL), COUNT(*) FILTER (WHERE loaded_at IS NULL) FROM raw.products
UNION ALL
SELECT 'sellers', COUNT(*), COUNT(*) FILTER (WHERE source_file IS NULL), COUNT(*) FILTER (WHERE loaded_at IS NULL) FROM raw.sellers
UNION ALL
SELECT 'product_category_translation', COUNT(*), COUNT(*) FILTER (WHERE source_file IS NULL), COUNT(*) FILTER (WHERE loaded_at IS NULL) FROM raw.product_category_translation
ORDER BY table_name;

-- 2. Required-key nulls and duplicates
SELECT 'customers.customer_id' AS key_name,
       COUNT(*) FILTER (WHERE customer_id IS NULL) AS null_key_rows,
       COUNT(*) - COUNT(DISTINCT customer_id) AS duplicate_key_rows
FROM raw.customers
UNION ALL
SELECT 'orders.order_id', COUNT(*) FILTER (WHERE order_id IS NULL), COUNT(*) - COUNT(DISTINCT order_id) FROM raw.orders
UNION ALL
SELECT 'order_items.(order_id, order_item_id)',
       COUNT(*) FILTER (WHERE order_id IS NULL OR order_item_id IS NULL),
       COUNT(*) - COUNT(DISTINCT (order_id, order_item_id))
FROM raw.order_items
UNION ALL
SELECT 'order_payments.(order_id, payment_sequential)',
       COUNT(*) FILTER (WHERE order_id IS NULL OR payment_sequential IS NULL),
       COUNT(*) - COUNT(DISTINCT (order_id, payment_sequential))
FROM raw.order_payments
UNION ALL
SELECT 'order_reviews.(review_id, order_id)',
       COUNT(*) FILTER (WHERE review_id IS NULL OR order_id IS NULL),
       COUNT(*) - COUNT(DISTINCT (review_id, order_id))
FROM raw.order_reviews
UNION ALL
SELECT 'products.product_id', COUNT(*) FILTER (WHERE product_id IS NULL), COUNT(*) - COUNT(DISTINCT product_id) FROM raw.products
UNION ALL
SELECT 'sellers.seller_id', COUNT(*) FILTER (WHERE seller_id IS NULL), COUNT(*) - COUNT(DISTINCT seller_id) FROM raw.sellers
UNION ALL
SELECT 'translation.product_category_name', COUNT(*) FILTER (WHERE product_category_name IS NULL), COUNT(*) - COUNT(DISTINCT product_category_name) FROM raw.product_category_translation
ORDER BY key_name;

-- 3. Referential-integrity observations
SELECT 'orders without customers' AS relationship, COUNT(*) AS orphan_rows
FROM raw.orders o LEFT JOIN raw.customers c ON o.customer_id = c.customer_id
WHERE c.customer_id IS NULL
UNION ALL
SELECT 'items without orders', COUNT(*)
FROM raw.order_items i LEFT JOIN raw.orders o ON i.order_id = o.order_id
WHERE o.order_id IS NULL
UNION ALL
SELECT 'items without products', COUNT(*)
FROM raw.order_items i LEFT JOIN raw.products p ON i.product_id = p.product_id
WHERE p.product_id IS NULL
UNION ALL
SELECT 'items without sellers', COUNT(*)
FROM raw.order_items i LEFT JOIN raw.sellers s ON i.seller_id = s.seller_id
WHERE s.seller_id IS NULL
UNION ALL
SELECT 'payments without orders', COUNT(*)
FROM raw.order_payments p LEFT JOIN raw.orders o ON p.order_id = o.order_id
WHERE o.order_id IS NULL
UNION ALL
SELECT 'reviews without orders', COUNT(*)
FROM raw.order_reviews r LEFT JOIN raw.orders o ON r.order_id = o.order_id
WHERE o.order_id IS NULL
UNION ALL
SELECT 'product categories without translation', COUNT(*)
FROM raw.products p LEFT JOIN raw.product_category_translation t
  ON p.product_category_name = t.product_category_name
WHERE p.product_category_name IS NOT NULL
  AND t.product_category_name IS NULL
ORDER BY relationship;
