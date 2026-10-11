-- ==============================================================================
-- 02_silver_transformations.sql
-- ==============================================================================
USE ROLE ASSESSMENT_ENGINEER;
USE WAREHOUSE ASSESSMENT_WH;
USE DATABASE ASSESSMENT_DB;

-- ASSUMPTIONS (Silver Layer):
-- [A09] Deduplication: If duplicate order_ids arrive, we deterministically keep the first one based on _row_number from the source file.
-- [A10] Fatal Errors: Missing order_date or negative quantities are fatal. They are dropped from Silver and would be routed to a Quarantine table.
-- [A11] Orphans: Missing customer or product IDs in dimensions are kept as 'Unknown' to preserve financial actuals, but must be logged.
-- [A12] Standardization: Text fields are trimmed and standardized to handle dirty inputs (spaces, casing).

CREATE SCHEMA IF NOT EXISTS DQ;
CREATE TRANSIENT SCHEMA IF NOT EXISTS SILVER;

-- 1. SILVER DIMENSIONS (Standardized & Cleansed)
CREATE OR REPLACE TRANSIENT TABLE SILVER.dim_product AS
SELECT 
    TRIM(product_id) AS product_id,
    TRIM(product_name) AS product_name,
    TRIM(product_family) AS product_family,
    TRY_CAST(TRIM(standard_cost) AS NUMBER(38,2)) AS standard_cost
FROM RAW.raw_product_master;

CREATE OR REPLACE TRANSIENT TABLE SILVER.dim_account AS
SELECT 
    TRIM(customer_id) AS customer_id,
    TRIM(account_name) AS account_name,
    TRIM(region) AS region
FROM RAW.raw_salesforce_accounts;

-- 2. SILVER FACTS (Deduplicated, Typed, and Cleansed)
CREATE OR REPLACE TRANSIENT TABLE SILVER.fact_orders AS
WITH deduped_raw AS (
    -- Deterministic deduplication using _row_number [A09]
    SELECT *
    FROM RAW.raw_oracle_orders
    QUALIFY ROW_NUMBER() OVER(PARTITION BY TRIM(order_id) ORDER BY _row_number ASC) = 1
),
typed_orders AS (
    SELECT 
        TRIM(order_id) AS order_id,
        COALESCE(TRIM(customer_id), 'Unknown') AS customer_id, -- Handle orphans [A11]
        COALESCE(TRIM(product_id), 'Unknown') AS product_id,   -- Handle orphans [A11]
        TRY_CAST(TRIM(order_date) AS DATE) AS order_date,
        TRY_CAST(TRIM(actual_delivery_date) AS DATE) AS actual_delivery_date,
        TRY_CAST(TRIM(quantity) AS NUMBER(38,0)) AS quantity,
        TRY_CAST(TRIM(unit_price) AS NUMBER(38,2)) AS unit_price,
        TRIM(order_status) AS order_status
    FROM deduped_raw
)
SELECT * 
FROM typed_orders
WHERE order_date IS NOT NULL   -- Fatal error handling: drops ORD90107 [A10]
  AND quantity > 0;            -- Fatal error handling: drops negative/zero qty [A10]

-- 3. SILVER FORECAST (Standardized)
CREATE OR REPLACE TRANSIENT TABLE SILVER.fact_forecast AS
SELECT 
    TRIM(product_id) AS product_id,
    TRIM(region) AS region,
    TRY_CAST(TRIM(forecast_month) AS DATE) AS forecast_month,
    TRY_CAST(TRIM(forecast_revenue) AS NUMBER(38,2)) AS forecast_revenue
FROM RAW.raw_adaptive_forecast
WHERE TRY_CAST(TRIM(forecast_month) AS DATE) IS NOT NULL;
