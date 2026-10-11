USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COMPUTE_WH;
USE DATABASE ASSESSMENT_DB;
USE SCHEMA GOLD;

-- ==============================================================================
-- GOLD LAYER: BUSINESS MART
-- ==============================================================================
CREATE OR REPLACE TABLE mart_revenue_performance AS
WITH actuals AS (
    SELECT 
        DATE_TRUNC('month', o.order_date) AS reporting_month,
        COALESCE(a.region, 'Unknown') AS region,  -- Handling orphan customer records
        COALESCE(o.product_id, 'Unknown') AS product_id,
        SUM(o.quantity * o.unit_price) AS actual_revenue,
        SUM((o.unit_price - p.standard_cost) * o.quantity) AS estimated_gross_margin,
        SUM(o.is_on_time_delivery) AS on_time_deliveries,
        COUNT(CASE WHEN o.order_status = 'Shipped' THEN o.order_id END) AS total_shipped_orders
    FROM ASSESSMENT_DB.SILVER.fact_orders o
    LEFT JOIN ASSESSMENT_DB.SILVER.dim_account a ON o.customer_id = a.customer_id
    LEFT JOIN ASSESSMENT_DB.SILVER.dim_product p ON o.product_id = p.product_id
    WHERE o.order_status = 'Shipped' -- Revenue recognized only on shipped orders
    GROUP BY 1, 2, 3
),
forecasts AS (
    SELECT 
        DATE_TRUNC('month', forecast_month) AS reporting_month,
        region, 
        product_id,
        SUM(forecast_revenue) AS forecast_revenue
    FROM ASSESSMENT_DB.SILVER.fact_forecast
    GROUP BY 1, 2, 3
)
SELECT 
    COALESCE(act.reporting_month, fcst.reporting_month) AS reporting_month,
    COALESCE(act.region, fcst.region) AS region,
    COALESCE(act.product_id, fcst.product_id) AS product_id,
    COALESCE(act.actual_revenue, 0) AS actual_revenue,
    COALESCE(fcst.forecast_revenue, 0) AS forecast_revenue,
    (COALESCE(act.actual_revenue, 0) - COALESCE(fcst.forecast_revenue, 0)) AS revenue_variance,
    COALESCE(act.estimated_gross_margin, 0) AS estimated_gross_margin,
    DIV0(act.on_time_deliveries, act.total_shipped_orders) AS delivery_performance_pct
FROM actuals act
FULL OUTER JOIN forecasts fcst 
    ON act.reporting_month = fcst.reporting_month 
    AND act.region = fcst.region 
    AND act.product_id = fcst.product_id;

-- Final Validation
SELECT * FROM mart_revenue_performance ORDER BY reporting_month DESC LIMIT 20;