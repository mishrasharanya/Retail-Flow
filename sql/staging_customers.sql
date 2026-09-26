BEGIN;

CREATE TABLE IF NOT EXISTS staging.customers (
    customer_id TEXT PRIMARY KEY,
    customer_unique_id TEXT NOT NULL,
    customer_zip_code_prefix INTEGER NOT NULL,
    customer_city TEXT NOT NULL,
    customer_state TEXT NOT NULL CHECK (customer_state ~ '^[A-Z]{2}$'),
    source_loaded_at TIMESTAMPTZ NOT NULL,
    staged_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

TRUNCATE TABLE staging.customers;

INSERT INTO staging.customers (
    customer_id,
    customer_unique_id,
    customer_zip_code_prefix,
    customer_city,
    customer_state,
    source_loaded_at
)
SELECT
    TRIM(customer_id),
    TRIM(customer_unique_id),
    TRIM(customer_zip_code_prefix)::INTEGER,
    LOWER(TRIM(customer_city)),
    UPPER(TRIM(customer_state)),
    loaded_at
FROM raw.customers;

COMMIT;
