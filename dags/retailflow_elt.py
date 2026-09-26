import os
from datetime import datetime, timedelta

from airflow import DAG
from airflow.operators.bash import BashOperator


PROJECT_ROOT = os.getenv("RETAILFLOW_ROOT", "/opt/airflow/retailflow")

default_args = {
    "owner": "retailflow",
    "retries": 2,
    "retry_delay": timedelta(minutes=2),
}

with DAG(
    dag_id="retailflow_elt",
    description="Load, transform, and validate the Olist RetailFlow dataset",
    default_args=default_args,
    start_date=datetime(2026, 1, 1),
    schedule=None,
    catchup=False,
    max_active_runs=1,
    tags=["retailflow", "olist", "elt"],
) as dag:
    load_raw = BashOperator(
        task_id="load_raw",
        bash_command="python src/load_raw.py",
        cwd=PROJECT_ROOT,
    )

    build_staging = BashOperator(
        task_id="build_staging",
        bash_command="python src/build_staging.py",
        cwd=PROJECT_ROOT,
    )

    check_staging_quality = BashOperator(
        task_id="check_staging_quality",
        bash_command="python src/check_staging_quality.py",
        cwd=PROJECT_ROOT,
    )

    build_analytics = BashOperator(
        task_id="build_analytics",
        bash_command="python src/build_analytics.py",
        cwd=PROJECT_ROOT,
    )

    check_analytics_quality = BashOperator(
        task_id="check_analytics_quality",
        bash_command="python src/check_analytics_quality.py",
        cwd=PROJECT_ROOT,
    )

    (
        load_raw
        >> build_staging
        >> check_staging_quality
        >> build_analytics
        >> check_analytics_quality
    )
