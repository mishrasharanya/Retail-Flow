CREATE TABLE IF NOT EXISTS raw.product_category_translation (
    product_category_name TEXT,
    product_category_name_english TEXT,
    source_file TEXT,
    loaded_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);
