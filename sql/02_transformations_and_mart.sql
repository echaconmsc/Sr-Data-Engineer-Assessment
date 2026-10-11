USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COMPUTE_WH;
USE DATABASE ASSESSMENT_DB;
USE SCHEMA SILVER;

-- ==============================================================================
-- 1. DIMENSIONS
-- ==============================================================================
CREATE OR REPLACE TABLE dim_account AS
SELECT 
    account_id, customer_id, account_name, region, account_owner, segment,
    TRY_CAST(active_flag AS BOOLEAN) AS is_active
FROM ASSESSMENT_DB.RAW.raw_salesforce_accounts;

CREATE OR REPLACE TABLE dim_product AS
SELECT 
    product_id, product_name, product_family, lifecycle_status,
    TRY_CAST(standard_cost AS DECIMAL(10,2)) AS standard_cost
FROM ASSESSMENT_DB.RAW.raw_product_master;

-- Auto-generating a Standard Time Dimension (dim_date) as mentioned in architecture
CREATE OR REPLACE TABLE dim_date AS
SELECT
    DATEADD(day, SEQ4(), '2024-01-01'::DATE) AS calendar_date,
    YEAR(DATEADD(day, SEQ4(), '2024-01-01'::DATE)) AS cal_year,
    MONTH(DATEADD(day, SEQ4(), '2024-01-01'::DATE)) AS cal_month,
    DATE_TRUNC('month', DATEADD(day, SEQ4(), '2024-01-01'::DATE)) AS reporting_month
FROM TABLE(GENERATOR(ROWCOUNT => 3650)); -- Generates 10 years of dates

-- ==============================================================================
-- 2. DATA QUALITY FRAMEWORK & QUARANTINE
-- Simulating dbt singular tests / Great Expectations behavior
-- ==============================================================================
CREATE OR REPLACE TABLE quarantine_orders AS
SELECT *, 'Negative/Zero Quantity or Null Price' AS dq_failure_reason
FROM ASSESSMENT_DB.RAW.raw_oracle_orders
WHERE TRY_CAST(quantity AS INT) <= 0 OR TRY_CAST(unit_price AS DECIMAL) IS NULL
UNION ALL
SELECT *, 'Logical Error: Delivery before Order' AS dq_failure_reason
FROM ASSESSMENT_DB.RAW.raw_oracle_orders
WHERE TRY_CAST(actual_delivery_date AS DATE) < TRY_CAST(order_date AS DATE);

-- ==============================================================================
-- 3. FACTS (CLEANSED)
-- ==============================================================================
CREATE OR REPLACE TABLE fact_forecast AS
SELECT
    forecast_id, product_id, region,
    TRY_CAST(forecast_month AS DATE) AS forecast_month,
    TRY_CAST(forecast_revenue AS DECIMAL(15,2)) AS forecast_revenue,
    TRY_CAST(forecast_quantity AS INT) AS forecast_quantity
FROM ASSESSMENT_DB.RAW.raw_adaptive_forecast;

CREATE OR REPLACE TABLE fact_orders AS
WITH raw_orders AS (
    -- Exclude quarantined records from the main pipeline
    SELECT r.* 
    FROM ASSESSMENT_DB.RAW.raw_oracle_orders r
    LEFT JOIN quarantine_orders q ON r.order_id = q.order_id
    WHERE q.order_id IS NULL
),
casted_orders AS (
    SELECT
        order_id, customer_id, product_id,
        TRY_CAST(order_date AS DATE) AS order_date,
        TRY_CAST(promised_delivery_date AS DATE) AS promised_delivery_date,
        TRY_CAST(actual_delivery_date AS DATE) AS actual_delivery_date,
        TRY_CAST(quantity AS INT) AS quantity,
        TRY_CAST(unit_price AS DECIMAL(10,2)) AS unit_price,
        plant_location, order_status,
        CASE 
            WHEN TRY_CAST(actual_delivery_date AS DATE) IS NOT NULL 
                 AND TRY_CAST(actual_delivery_date AS DATE) <= TRY_CAST(promised_delivery_date AS DATE) THEN 1 
            ELSE 0 
        END AS is_on_time_delivery
    FROM raw_orders
)
SELECT *
FROM casted_orders
-- Handle Duplicates (e.g., ORD00005)
QUALIFY ROW_NUMBER() OVER(PARTITION BY order_id ORDER BY order_date DESC) = 1;