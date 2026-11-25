"""
Append one extract of CSV files into the RAW schema of the local DuckDB warehouse.

This is the local stand-in for Snowpipe (see snowflake/02_stage_and_snowpipe.sql):
files land as-is, every column as text (typing happens in dbt staging), and each
row is stamped with _loaded_at and _source_file. Loads only ever append, like
Snowpipe, so duplicates and late changes are the dbt models' job to handle.

Usage:
    python scripts/load_raw.py data/raw/load_1 --db data/warehouse.duckdb
"""

from __future__ import annotations

import argparse
from pathlib import Path

import duckdb


def load(extract_dir: Path, db_path: Path) -> dict[str, int]:
    db_path.parent.mkdir(parents=True, exist_ok=True)
    con = duckdb.connect(str(db_path))
    con.execute("create schema if not exists raw")
    counts = {}
    for csv in sorted(extract_dir.glob("*.csv")):
        table = f"raw.{csv.stem}"
        select = (
            f"select *, current_timestamp as _loaded_at, '{csv.name}' as _source_file "
            f"from read_csv('{csv.as_posix()}', header=true, all_varchar=true)"
        )
        exists = con.execute(
            "select count(*) from information_schema.tables where table_schema = 'raw' and table_name = ?",
            [csv.stem],
        ).fetchone()[0]
        if exists:
            con.execute(f"insert into {table} by name {select}")
        else:
            con.execute(f"create table {table} as {select}")
        counts[csv.stem] = con.execute(f"select count(*) from read_csv('{csv.as_posix()}', header=true)").fetchone()[0]
    con.close()
    return counts


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("extract_dir", type=Path)
    p.add_argument("--db", type=Path, default=Path("data/warehouse.duckdb"))
    a = p.parse_args()
    for table, n in load(a.extract_dir, a.db).items():
        print(f"loaded {n:>6} rows into raw.{table}")


if __name__ == "__main__":
    main()
