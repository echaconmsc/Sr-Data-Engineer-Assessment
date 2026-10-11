-- ==============================================================================
-- 1. SETUP ENVIRONMENT
-- ==============================================================================

USE ROLE ACCOUNTADMIN;
CREATE OR REPLACE DATABASE ASSESSMENT_DB;
CREATE OR REPLACE SCHEMA ASSESSMENT_DB.RAW;
CREATE OR REPLACE SCHEMA ASSESSMENT_DB.SILVER;
CREATE OR REPLACE SCHEMA ASSESSMENT_DB.GOLD;

USE DATABASE ASSESSMENT_DB;
USE SCHEMA RAW;

-- ==============================================================================
-- 2. INGESTION LAYER (BRONZE/RAW)
-- ==============================================================================

CREATE OR REPLACE TABLE raw_oracle_orders (
    order_id VARCHAR, customer_id VARCHAR, product_id VARCHAR, order_date VARCHAR,
    promised_delivery_date VARCHAR, actual_delivery_date VARCHAR, quantity VARCHAR,
    unit_price VARCHAR, plant_location VARCHAR, order_status VARCHAR
);

CREATE OR REPLACE TABLE raw_salesforce_accounts (
    account_id VARCHAR, customer_id VARCHAR, account_name VARCHAR, region VARCHAR,
    account_owner VARCHAR, segment VARCHAR, active_flag VARCHAR
);

CREATE OR REPLACE TABLE raw_adaptive_forecast (
    forecast_id VARCHAR, product_id VARCHAR, region VARCHAR, forecast_month VARCHAR,
    forecast_revenue VARCHAR, forecast_quantity VARCHAR
);

CREATE OR REPLACE TABLE raw_product_master (
    product_id VARCHAR, product_name VARCHAR, product_family VARCHAR,
    lifecycle_status VARCHAR, standard_cost VARCHAR
);

/* 
================================================================================
PRODUCTION NOTE:
In a live automated environment:
CREATE STAGE my_s3_stage URL='s3://my-enterprise-bucket/raw_data/' ...;
COPY INTO raw_oracle_orders FROM @my_s3_stage/oracle_orders.csv 
FILE_FORMAT = (TYPE = 'CSV' SKIP_HEADER = 1);
================================================================================
*/