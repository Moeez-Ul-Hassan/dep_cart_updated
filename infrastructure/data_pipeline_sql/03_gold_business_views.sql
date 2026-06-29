-- GOLD LAYER: Executive Dashboards and Analytics
CREATE OR REPLACE VIEW gold_executive_funnel AS
SELECT 
    COUNT(cart_id) AS total_carts_created,
    ROUND(SUM(CASE WHEN status = 'completed' THEN total_amount ELSE 0 END), 2) AS gross_revenue,
    ROUND(SUM(CASE WHEN status = 'abandoned' THEN total_amount ELSE 0 END), 2) AS lost_revenue,
    ROUND((CAST(SUM(CASE WHEN status = 'completed' THEN 1 ELSE 0 END) AS DOUBLE) / COUNT(cart_id)) * 100, 2) AS conversion_rate_pct
FROM carts_silver;

-- (Add the other views: gold_customer_360, gold_product_performance, gold_cart_composition)