[![CircleCI](https://circleci.com/gh/mozilla/bigquery-etl.svg?style=shield&circle-token=742fb1108f7e6e5a28c11d43b21f62605037f5a4)](https://circleci.com/gh/mozilla/bigquery-etl)

BigQuery ETL
===

Bigquery UDFs and SQL queries for building derived datasets.

Recommended practices
---

### Queries

- Should be defined in files named as `sql/table_version.sql` e.g.
  `sql/core_clients_daily_v1.sql`
- May be generated using a python script that prints the query to stdout
  - Should save output as `sql/table_version.sql` as above
  - Should be named as `sql/query_type.sql.py` e.g. `sql/clients_daily.sql.py`
  - May use options to generate queries for different destination tables e.g.
    using `--source telemetry_core_parquet_v3` to generate
    `sql/core_clients_daily_v1.sql` and using `--source main_summary_v4` to
    generate `sql/clients_daily_v7.sql`
  - Should output a header indicating options used e.g.
    ```sql
    -- Query generated by: sql/clients_daily.sql.py --source telemetry_core_parquet
    ```
- Should not specify a project or dataset in table names to simplify testing
- Should be [incremental]
- Should filter input tables on partition and clustering columns
- Should use `_` prefix in generated column names not meant for output
- Should use `_bits` suffix for any integer column that represents a bit pattern
- Should not use `DATETIME` type, due to incompatiblity with
  [spark-bigquery-connector]
- Should use the earliest row for each `document_id` by `submission_timestamp`
  if filtering duplicates
- Should escape identifiers that match keywords, even if they aren't [reserved keywords]

### UDFs

- Should limit the number of [expression subqueries] to avoid: `BigQuery error
  in query operation: Resources exceeded during query execution: Not enough
  resources for query planning - too many subqueries or query is too complex.`
- Should be used to avoid code duplication
- Should use lower snake case names e.g. `udf_mode_last`
  - Should use a `udf_` prefix for naming temporary udfs
  - Should additionally use a `_js` suffix for naming temporary udfs implemented in JavaScript
- Should be defined in files named as `udfs/function.sql` e.g. `udfs/udf_mode_last.sql`
  or `udfs/udf_sum_buckets_with_ci_js.sql`
- Should use `SQL` over `js` for performance
- Must not be used for incremental queries with a _mostly materialized view_ (defined below)

### Backfills

- Should be avoided on large tables
  - Backfills may double storage cost for a table for 90 days by moving
    data from long-term storage to short-term storage
    - For example regenerating `clients_last_seen_v1` from scratch would cost
      about $1600 for the query and about $6800 for data moved to short-term
      storage
  - Should combine multiple backfills happening around the same time
  - Should delay column deletes until the next other backfill
    - Should use `NULL` for new data and `EXCEPT` to exclude from views until
      dropped
- Should use copy operations in append mode to change column order
  - Copy operations do not allow changing partitioning, changing clustering, or
    column deletes
- Should split backfilling into queries that finish in minutes not hours
- May use [script/generate_incremental_table] to automate backfilling incremental
  queries

Incremental Queries
---

### Benefits

- BigQuery billing discounts for destination table partitions not modified in
  the last 90 days
- May use [dags.utils.gcp.bigquery_etl_query] to simplify airflow configuration
  e.g. see [dags.main_summary.exact_mau28_by_dimensions]
- May use [script/generate_incremental_table] to automate backfilling
- Should use `WRITE_TRUNCATE` mode or `bq query --replace` to replace
  partitions atomically to prevent duplicate data
- Will have tooling to generate an optimized _mostly materialized view_ that
  only calculates the most recent partition
  - Note: incompatible with UDFs, which are not allowed in views

### Properties

- Must accept a date via `@submission_date` query parameter
  - Must output a column named `submission_date` matching the query parameter
- Must produce similar results when run multiple times
  - Should produce identical results when run multiple times
- May depend on the previous partition
  - If using previous partition, must include a `.init.sql` query to init the
    table
  - Should be impacted by values from a finite number of preceding partitions
    - This allows for backfilling in chunks instead of serially for all time
      and limiting backfills to a certain number of days following updated data
    - For example `sql/clients_last_seen_v1.sql` can be run serially on any 28 day
      period and the last day will be the same whether or not the partition
      preceding the first day was missing because values are only impacted by
      27 preceding days

Contributing
---

When adding or modifying a query in this repository, make your changes in the
`templates/` directory. Each time you run tests locally (see [Tests](#tests) below),
the `sql/` directory will be regenerated, inserting definitions of any UDFs
referenced by the query. To force recreation of the `sql/` directory without
running tests, invoke:

    ./script/generate_sql

You are expected to commit the generated content in `sql/` along with your
changes to the source in `templates/`, otherwise CI will fail. This matches
the strategy used by [mozilla-pipeline-schemas] and ensures that the final
queries being run by Airflow are directly available to reference via URL and
to view via the GitHub UI.

Tests
---

[See the documentation in tests/](tests/README.md)

[script/generate_incremental_table]: https://github.com/mozilla/bigquery-etl/blob/master/script/generate_incremental_table
[expression subqueries]: https://cloud.google.com/bigquery/docs/reference/standard-sql/expression_subqueries
[dags.utils.gcp.bigquery_etl_query]: https://github.com/mozilla/telemetry-airflow/blob/89a6dc3/dags/utils/gcp.py#L364
[dags.main_summary.exact_mau28_by_dimensions]: https://github.com/mozilla/telemetry-airflow/blob/89a6dc3/dags/main_summary.py#L385-L390
[incremental]: #incremental-queries
[spark-bigquery-connector]: https://github.com/GoogleCloudPlatform/spark-bigquery-connector/issues/5
[reserved keywords]: https://cloud.google.com/bigquery/docs/reference/standard-sql/lexical#reserved-keywords
[mozilla-pipeline-schemas]: https://github.com/mozilla-services/mozilla-pipeline-schemas
