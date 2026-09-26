from pathlib import Path

from sqlalchemy import create_engine

from config import PROJECT_ROOT, get_database_url


def execute_sql_file(relative_path: str) -> None:
    sql_path = PROJECT_ROOT / relative_path

    if not sql_path.exists():
        raise FileNotFoundError(f"SQL file not found: {sql_path}")

    sql = sql_path.read_text(encoding="utf-8")
    engine = create_engine(get_database_url())
    connection = engine.raw_connection()

    try:
        with connection.cursor() as cursor:
            cursor.execute(sql)
        connection.commit()
    except Exception:
        connection.rollback()
        raise
    finally:
        connection.close()
        engine.dispose()

    print(f"Successfully executed {Path(relative_path).name}")
