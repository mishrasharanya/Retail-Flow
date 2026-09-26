# RetailFlow

RetailFlow is an end-to-end ELT data engineering project built with the Brazilian Olist ecommerce dataset. It loads CSV files into PostgreSQL, cleans and validates the data, creates business-ready analytics tables, orchestrates the pipeline with Apache Airflow, and displays results in a static HTML dashboard.

## Architecture

```text
Olist CSV files
      ↓
Python ingestion
      ↓
PostgreSQL raw layer
      ↓
SQL staging layer
      ↓
Data-quality checks
      ↓
Analytics dimensions and facts
      ↓
Analytics validation
      ↓
JSON export
      ↓
Static HTML dashboard
```

Apache Airflow runs the ingestion, transformation, and validation steps in dependency order.

## Dataset

The project processes nine Olist source files and **1,550,922 total raw records**.

The repository includes the nine anonymized public CSV files under `data/raw/`. They originate from the [Olist Brazilian E-Commerce dataset](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce).

| Dataset | Raw table | Rows |
|---|---|---:|
| Customers | `raw.customers` | 99,441 |
| Geolocation | `raw.geolocation` | 1,000,163 |
| Order items | `raw.order_items` | 112,650 |
| Payments | `raw.order_payments` | 103,886 |
| Reviews | `raw.order_reviews` | 99,224 |
| Orders | `raw.orders` | 99,441 |
| Products | `raw.products` | 32,951 |
| Sellers | `raw.sellers` | 3,095 |
| Product-category translations | `raw.product_category_translation` | 71 |

The main relationships are:

```text
customers
    ↓
orders
    ├── order_items ── products
    │        └──────── sellers
    ├── order_payments
    └── order_reviews

products ── product-category translations
customers/sellers ── ZIP prefixes ── geolocation
```

## What We Built

### Raw layer

Python loads all nine CSV files into PostgreSQL raw tables.

The reusable loader:

- Validates source filenames and columns.
- Reads large files in 50,000-row chunks.
- Stores the source filename and load timestamp.
- Reconciles CSV and database row counts.
- Runs all loads inside a PostgreSQL transaction.
- Truncates and reloads tables safely, making repeated runs idempotent.
- Rolls back the complete load if any dataset fails.

Raw values remain close to their source representation so the original records are preserved for auditing and reprocessing.

### Staging layer

The staging layer cleans, standardizes, and constrains the raw data.

| Staging table | Rows | Grain |
|---|---:|---|
| `staging.customers` | 99,441 | One row per order-specific customer ID |
| `staging.orders` | 99,441 | One row per order |
| `staging.order_items` | 112,650 | One row per order and item number |
| `staging.order_payments` | 103,886 | One row per order and payment sequence |
| `staging.order_reviews` | 99,224 | One row per review and order |
| `staging.products` | 32,951 | One row per product |
| `staging.sellers` | 3,095 | One row per seller |
| `staging.geolocation` | 19,015 | One row per ZIP prefix |

Staging transformations include:

- Converting timestamps, integers, and monetary values to proper types.
- Preserving five-character ZIP prefixes, including leading zeros.
- Standardizing city and state values.
- Correcting source column names such as `product_name_lenght`.
- Translating Portuguese product categories to English.
- Retaining untranslated categories instead of dropping products.
- Assigning `unknown` to 610 products without a source category.
- Aggregating 1,000,163 geolocation observations into 19,015 ZIP-prefix records.
- Enforcing primary keys, foreign keys, accepted values, and numeric ranges.

### Analytics layer

The analytics layer contains business-ready dimensions and facts.

| Analytics table | Rows | Grain |
|---|---:|---|
| `analytics.dim_customers` | 96,096 | One row per real customer |
| `analytics.dim_products` | 32,951 | One row per product |
| `analytics.dim_sellers` | 3,095 | One row per seller |
| `analytics.fact_orders` | 99,441 | One row per order |
| `analytics.fact_order_items` | 112,650 | One row per purchased item |

Reporting views include:

- `analytics.dashboard_summary`
- `analytics.monthly_sales`
- `analytics.category_performance`
- `analytics.state_performance`
- `analytics.seller_performance`

Measures from items, payments, and reviews are aggregated before they are joined to orders. This prevents revenue from being multiplied when an order contains multiple items or payment records.

## Data Quality

The staging suite performs **28 checks** covering:

- Raw-to-staging row-count reconciliation
- Missing business keys
- Duplicate keys
- Orders without customers
- Items without orders, products, or sellers
- Payments and reviews without orders
- Review scores outside 1–5
- Negative prices, freight, payments, or product measurements
- Timestamp ordering
- Geolocation and category coverage

Result:

```text
28 checks
0 critical failures
5 warnings
```

Known warnings:

| Warning | Rows |
|---|---:|
| Products with an unknown category | 610 |
| Customers without a matching geolocation ZIP prefix | 278 |
| Sellers without a matching geolocation ZIP prefix | 7 |
| Orders without a payment record | 1 |
| Delivered orders without a delivery timestamp | 8 |

The analytics suite performs **19 reconciliation checks** covering table grains, monetary totals, item counts, reporting views, review scores, and delivery rates.

```text
19 checks
0 failures
```

## Airflow Pipeline

The Airflow DAG is named `retailflow_elt`.

```text
load_raw
    ↓
build_staging
    ↓
check_staging_quality
    ↓
build_analytics
    ↓
check_analytics_quality
```

The DAG has:

- Two retries per failed task
- A two-minute retry delay
- No historical catchup
- One active run at a time
- Manual scheduling while the source files remain static

The first complete Airflow run succeeded across all five tasks in approximately 28 seconds on the development machine.

Airflow uses its own PostgreSQL metadata database, separate from the RetailFlow database.

## Dashboard

The static dashboard reads JSON exported from the analytics views. It does not connect directly to PostgreSQL and does not expose database credentials.

Headline metrics:

| Metric | Value |
|---|---:|
| Delivered orders | 96,478 |
| Customers with delivered orders | 93,358 |
| Delivered revenue | R$15,422,461.77 |
| Average order value | R$159.85 |
| Average review score | 4.16 / 5 |
| Late-delivery rate | 8.11% |
| Average delivery time | 12.56 days |

Interesting findings:

- November 2017 was the peak month, with R$1.15M from 7,289 delivered orders.
- November's 14.3% late-delivery rate was above the overall 8.1% rate.
- March 2018 had the highest meaningful monthly late-delivery rate at 21.4%.
- São Paulo generated 37.4% of delivered revenue from 40,501 orders.
- São Paulo's 5.9% late-delivery rate was below the overall result.
- Health and beauty was the leading category with R$1.26M in product value from 9,670 items.
- The most active customer placed 17 orders.
- 2,997 customers placed more than one order.

The dashboard contains KPI cards, a monthly revenue chart, category rankings, state performance, seller performance, and written insights generated from the exported data.

## Running the Project

Create local configuration before starting services:

```bash
cp .env.example .env
```

Replace every placeholder password in `.env`. This file is ignored by Git.

Start PostgreSQL:

```bash
docker compose up -d postgres
```

Run the pipeline locally:

```bash
venv/bin/python src/load_raw.py
venv/bin/python src/build_staging.py
venv/bin/python src/check_staging_quality.py
venv/bin/python src/build_analytics.py
venv/bin/python src/check_analytics_quality.py
venv/bin/python src/export_dashboard_data.py
```

Start Airflow:

```bash
docker compose up -d --build airflow-webserver airflow-scheduler
```

Open Airflow at [http://localhost:8080](http://localhost:8080).

```text
Username: value of AIRFLOW_ADMIN_USER in .env
Password: value of AIRFLOW_ADMIN_PASSWORD in .env
```

Start the dashboard:

```bash
venv/bin/python -m http.server 8000 --bind 127.0.0.1 --directory dashboard
```

Open the dashboard at [http://localhost:8000](http://localhost:8000).

## Project Structure

```text
RetailFlow/
├── dags/               Airflow DAG
├── dashboard/          Static HTML dashboard and exported JSON
├── data/raw/           Olist source CSV files
├── sql/                Schema, staging, analytics, and validation SQL
├── src/                Ingestion, transformation, checks, and export code
├── Dockerfile.airflow  Self-contained Airflow image
├── docker-compose.yml  PostgreSQL and Airflow services
└── requirements.txt    Local Python dependencies
```

## Current Limitations

- Raw loading is a transactional full refresh rather than row-level incremental ingestion.
- Dashboard export currently runs as a local command rather than the final Airflow task.
- Credentials are loaded from an ignored local `.env`; production deployments should use a secrets manager.
- The source CSV files are stored in the repository; production data would normally live in object storage.
