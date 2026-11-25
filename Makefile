PY ?= python
export DBT_PROFILES_DIR := .
export DUCKDB_PATH := ../data/warehouse.duckdb

.PHONY: install data load1 load2 build demo test docs freshness lint clean

install:   ## dbt Core + DuckDB/Snowflake adapters
	$(PY) -m pip install -r requirements.txt

data:      ## Generate two synthetic extracts into data/raw
	$(PY) data_generator/generate_insurance_data.py --out data/raw

load1:     ## Append extract 1 into RAW (local stand-in for Snowpipe)
	$(PY) scripts/load_raw.py data/raw/load_1

load2:
	$(PY) scripts/load_raw.py data/raw/load_2

build:     ## dbt build: seeds, snapshot, models, unit + data tests
	cd dbt && dbt build

demo: clean data  ## Full two-load demo (incremental + SCD2)
	$(MAKE) load1 build
	$(MAKE) load2 build

test:
	cd dbt && dbt test

freshness:
	cd dbt && dbt source freshness

docs:      ## Generate and serve dbt docs with lineage graph
	cd dbt && dbt docs generate && dbt docs serve

lint:
	ruff check . && ruff format --check .

clean:
	rm -rf data dbt/target dbt/logs
