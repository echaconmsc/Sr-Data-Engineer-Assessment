# Snowflake Analytical Data Engineering Solution
**Candidate:** Estivent Chacón | **Role:** Senior Data Engineer | **Location:** Alajuela, CR
**Submission:** Option A (GitHub Repository) 

## Project Overview:
This repository contains the technical assessment for the Senior Data Engineer role. The objective is to design and implement a Snowflake-based analytical solution to support business reporting, handling intentionally injected data quality issues.

## 1. Architecture & Tech Stack
For this Snowflake analytical solution, I am proposing a **Medallion Architecture (Bronze/Raw, Silver, Gold)**. This structure guarantees data lineage, error isolation, and analytical flexibility.

**End-to-End Data Flow:**
1. **Source Layer:** Source systems represented by local files (`oracle_orders`, `salesforce_accounts`, `adaptive_forecast`, `product_master`).
2. **Ingestion Layer (Bronze/Raw):** Raw ingestion (1:1) into Snowflake via `COPY INTO` from an External Stage (AWS S3). Data is stored in tabular format with no heavy transformations, adding only ingestion metadata (`_ingested_at`, `_file_name`).
3. **Transformation Layer (Silver/Cleansed):** Structured models (ideally orchestrated with **dbt**). We apply:
   - Cleansing and standardization.
   - Resolution of Data Quality (DQ) issues.
   - Data type casting.
4. **Analytical Layer (Gold/Mart):** Fact and Dimension tables modeled in a **Star Schema**. The final aggregation (`analytics.mart_revenue_performance`) resides here, ready for consumption by Power BI.

## 2. Data Model
The proposed model is a **Star Schema** optimized for high-performance analytical queries in Snowflake.

*   **Dimensions:**
    *   `dim_account`: Customer details, region, and segment.
    *   `dim_product`: Product family and `standard_cost`.
    *   `dim_date`: Standard time dimension.
*   **Facts:**
    *   `fact_orders`: Transactional grain (Item level per purchase order).
    *   `fact_forecast`: Monthly aggregated grain per region and product.

**Handling Granularity Differences:**
The main challenge is that orders are transactional (daily, per customer), while the forecast is monthly, per region and product. To solve this in the `mart_revenue_performance`, `fact_orders` data is **rolled up (aggregated)** to the `Month`, `Region`, and `Product` level. This enables a `FULL OUTER JOIN` with the forecast to accurately calculate *Revenue Variance*.

## 3. Data Quality Analysis
Following an exploratory data analysis, these anomalies were identified and handled in the Silver layer:

1. **Duplicates:** Found identical or versioned duplicate rows (e.g., order `ORD00005`). 
   - *Resolution:* Handled using `QUALIFY ROW_NUMBER() OVER(PARTITION BY order_id ORDER BY order_date DESC) = 1` to keep the most recent truth.
2. **Invalid Numeric Values:** Identified negative quantities (e.g., `-15`) and null prices.
   - *Resolution:* Applied `WHERE quantity > 0 AND unit_price IS NOT NULL` filters.
3. **Inconsistent Dates:** Actual delivery dates occurring before the order date.
   - *Resolution:* Implemented logical checks `(actual_delivery_date IS NULL OR actual_delivery_date >= order_date)`.
4. **Data Type Casting:** Text fields attempting to masquerade as numbers or dates.
   - *Resolution:* Used safe-casting functions (`TRY_CAST`) to gracefully handle nulls without breaking the pipeline.
5. **Delivery Inconsistencies:** 1 record where `actual_delivery_date` is earlier than `order_date`. Marked as a DQ error and sent to quarantine.
6. **Orphan Records:** Orders with `customer_id` or `product_id` missing in dimension tables. Handled via `LEFT JOIN` and surrogate keys (`-1` or `Unknown`) to prevent revenue loss in financial reporting.

## 4. Repository Structure:

The project is structured to reflect a simplified dbt-like model separation:

The SQL scripts containing the transformation logic and the final analytical output can be found in the `sql/` directory:
  - `01_architecture_and_ingestion.sql`: Environment setup (Database, Schemas, Warehouse) and Bronze layer table DDLs.
 - `02_silver_transformations.sql`: Silver layer casting, generation of the time dimension (dim_date), Data Quality (DQ) quarantine logic, and Fact/Dimension tables creation.
 - `03_gold_mart.sql`: Gold layer business mart (mart_revenue_performance) aggregation and final validation.
- `README.md`: Project documentation.
- `snowflake_results.png`: Evidence of successful script execution generating the final mart.

*Note: The SQL logic is provided as scripts, but in a production environment, this would be part of my dbt project.*

## 5. Key Decisions & Considerations

**Design Decisions:**
*   **Revenue Recognition:** `Actual_Revenue` is only recognized when `order_status` is 'Shipped'. 'Open' orders represent backlog.
*   **Gross Margin:** Calculated using the latest available `standard_cost`.
*   **Full Outer Join:** Used to compare actuals and forecasts, assuming forecasts might exist for unsold products or unexpected sales might occur without a forecast.

**Production & Enterprise Vision (Bonus):**
- **dbt Project & Automated Testing:** The logic in `02` and `03` scripts translates directly into dbt models. I would implement generic tests (`not_null`, `unique`) on keys and singular tests (e.g., `qty > 0`) to enforce DQ.
- **Quarantine/Error-handling Framework:** Implemented natively in `02_silver_transformations.sql` using the `quarantine_orders` table to catch logic/type failures without breaking the pipeline.
- **Data Lineage Documentation:** Inherently supported by the Medallion architecture (Raw -> Silver -> Gold). Tools like dbt docs or Monte Carlo would visualize this DAG.
- **Data Reconciliation Controls:** Row-count and revenue-sum checks between Silver (`fact_orders`) and Gold (`mart_revenue_performance`) to ensure no revenue is dropped during the `FULL OUTER JOIN`.
- **Incremental Processing Strategy:** Replacing `CREATE OR REPLACE` with `MERGE` statements (or dbt `is_incremental()`) using `order_date` as a water-mark for the `fact_orders` table.
- **Snowflake Streams and Tasks:** Used for CDC (Change Data Capture) from the RAW layer, feeding only net-new records into the Silver layer automatically.
- **CI/CD Concepts:** Leveraging GitHub Actions to run `sqlfluff` for linting and triggering a dry-run compilation before merging PRs into the main branch.
- **Observability and monitoring framework:** Integration with Snowflake Alerts to notify Data Stewards via Slack/Email when the `quarantine_orders` table exceeds a specific threshold.
- **Power BI semantic model & Dashboarding:** The `mart_revenue_performance` acts as the direct import/DirectQuery source for Power BI. Row-Level Security (RLS) would be applied on the `dim_account.region` so regional managers only see their respective forecast variance.

## 6. Scalability & Production Considerations

While this assessment represents a static load, in a production environment, I would enhance this architecture with:

1. **Orchestration:** Using Snowflake Tasks or other tools like (Apache Airflow, Dagster) to automate the DAG execution.
2. **CI/CD:** Implement GitHub Actions to automate testing and deployment of SQL scripts (or dbt models) across DEV, QA, and PROD environments.
3. **Incremental Loading:** Transition from `CREATE OR REPLACE` to `MERGE` statements in the Silver and Gold layers to handle massive datasets efficiently.

## Execution Evidence:
![Snowflake Mart Execution](snowflake_results.png)