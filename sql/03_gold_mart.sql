-- ==============================================================================
-- 03_gold_mart.sql
-- ==============================================================================
USE ROLE ASSESSMENT_ENGINEER;
USE WAREHOUSE ASSESSMENT_WH;
USE DATABASE ASSESSMENT_DB;

-- ASSUMPTIONS (Gold Layer):
-- [A13] Grain: The final mart is aggregated at the Month x Region x Product level.
-- [A14] Revenue Recognition: Only 'Shipped' orders count towards actual_revenue.
-- [A15] Delivery Status: Added explicit metrics for on_time_orders vs total_shipped_orders to allow aggregations.

CREATE TRANSIENT SCHEMA IF NOT EXISTS ANALYTICS;

-- ==============================================================================
-- 1. AGGREGATE ACTUALS (Rolled up to Month, Region, Product)
-- ==============================================================================

CREATE OR REPLACE TRANSIENT TABLE ANALYTICS.mart_revenue_performance AS
WITH monthly_actuals AS (
    SELECT 
        DATE_TRUNC('month', o.order_date) AS reporting_month,
        COALESCE(a.region, 'Unknown') AS region,
        COALESCE(p.product_id, 'Unknown') AS product_id,
        
        -- Additive Measures
        SUM(IFF(o.order_status = 'Shipped', o.quantity * o.unit_price, 0)) AS actual_revenue,
        SUM(IFF(o.order_status = 'Shipped', (o.unit_price - COALESCE(p.standard_cost, 0)) * o.quantity, 0)) AS estimated_gross_margin,
        
        -- Delivery Performance (Additive logic)
        COUNT(IFF(o.order_status = 'Shipped', o.order_id, NULL)) AS total_shipped_orders,
        COUNT(IFF(o.order_status = 'Shipped' AND o.actual_delivery_date <= o.order_date, o.order_id, NULL)) AS on_time_deliveries
        
    FROM SILVER.fact_orders o
    LEFT JOIN SILVER.dim_account a ON o.customer_id = a.customer_id
    LEFT JOIN SILVER.dim_product p ON o.product_id = p.product_id
    GROUP BY 1, 2, 3
),

-- ==============================================================================
-- 2. AGGREGATE FORECAST
-- ==============================================================================

monthly_forecast AS (
    SELECT 
        forecast_month AS reporting_month,
        region,
        product_id,
        SUM(forecast_revenue) AS forecast_revenue
    FROM SILVER.fact_forecast
    GROUP BY 1, 2, 3
)

-- ==============================================================================
-- 3. FINAL MART (Full Outer Join for completeness)
-- ==============================================================================
SELECT 
    COALESCE(act.reporting_month, fcst.reporting_month) AS reporting_month,
    COALESCE(act.region, fcst.region) AS region,
    COALESCE(act.product_id, fcst.product_id) AS product_id,
    
    -- Financials
    COALESCE(act.actual_revenue, 0) AS actual_revenue,
    COALESCE(fcst.forecast_revenue, 0) AS forecast_revenue,
    (COALESCE(act.actual_revenue, 0) - COALESCE(fcst.forecast_revenue, 0)) AS revenue_variance,
    COALESCE(act.estimated_gross_margin, 0) AS estimated_gross_margin,
    
    -- Delivery Metrics
    COALESCE(act.total_shipped_orders, 0) AS total_shipped_orders,
    COALESCE(act.on_time_deliveries, 0) AS on_time_deliveries,
    DIV0(act.on_time_deliveries, act.total_shipped_orders) AS delivery_performance_pct

FROM monthly_actuals act
FULL OUTER JOIN monthly_forecast fcst 
    ON act.reporting_month = fcst.reporting_month 
   AND act.region = fcst.region 
   AND act.product_id = fcst.product_id;
