--- 1 Identify the top 10 stores based on Incremental Revenue (IR) generated during the promotional periods.
SELECT  
	store_id,

    SUM(base_price * quantity_sold_after_promo) - SUM(base_price * quantity_sold_before_promo) AS incremental_revenue

FROM fact_events 

GROUP BY store_id    

ORDER BY incremental_revenue DESC

LIMIT 10 ;

--- 2 Determine the bottom 10 stores in terms of Incremental Sold Units (ISU) during these campaigns.
SELECT  
	store_id,
    SUM(quantity_sold_after_promo) - SUM(quantity_sold_before_promo) AS incremental_sold_units
    
FROM fact_events

GROUP BY store_id   

ORDER BY incremental_sold_units ASC

LIMIT 10;

--- 3 Analyze store performance variations by city, exploring common characteristics among the top-performing stores that can be applied to others.
WITH store_performance AS (
    SELECT 
        ds.city,
        ds.store_id,

        SUM(fe.base_price * (fe.quantity_sold_after_promo - fe.quantity_sold_before_promo)) AS store_incremental_revenue,
        SUM(fe.quantity_sold_after_promo - fe.quantity_sold_before_promo) AS store_incremental_units
        
    FROM u131628650_supermart365.fact_events fe

    INNER JOIN u131628650_supermart365.dim_stores ds 
    ON fe.store_id = ds.store_id

    GROUP BY ds.city, ds.store_id)

SELECT 
    city,
    COUNT(store_id) AS stores_in_city,
    AVG(store_incremental_revenue) AS avg_store_revenue,
    SUM(store_incremental_revenue) AS total_city_revenue,
    SUM(store_incremental_units) AS total_city_units

FROM store_performance

GROUP BY city

ORDER BY avg_store_revenue DESC;

--- 4 Evaluate which two promotion types yield the highest Incremental Revenue.
SELECT 
       promo_type,
       SUM(base_price * quantity_sold_before_promo) AS revenue_before,
       SUM(base_price * quantity_sold_after_promo) AS revenue_after,
       SUM(base_price * quantity_sold_after_promo) - SUM(base_price * quantity_sold_before_promo) AS incremental_revenue
       
FROM fact_events 

GROUP BY promo_type
ORDER BY incremental_revenue DESC
LIMIT 2;

--- 5 Assess which two promotion types result in the lowest Incremental Sold Units.
SELECT 
       promo_type,
       SUM(quantity_sold_before_promo) AS revenue_before,
       SUM(quantity_sold_after_promo) AS revenue_after,
       SUM(quantity_sold_after_promo) - SUM(quantity_sold_before_promo) AS incremental_sold_units
	   
FROM fact_events 

GROUP BY promo_type

ORDER BY incremental_sold_units ASC

LIMIT 2;

--- 6 Compare the effectiveness of discount-based promotions with alternative types such as BOGOF and cashback.

WITH promotion_performance AS (
    SELECT 
        CASE
            WHEN promo_type IN ('50% OFF','33% OFF','25% OFF') THEN 'Discount' 
            WHEN promo_type = 'BOGOF' THEN 'BOGOF' 
            WHEN promo_type = '500 Cashback' THEN 'Cashback' 
        END AS promotion_category,
                
        SUM(base_price * (quantity_sold_after_promo - quantity_sold_before_promo)) AS incremental_revenue,
        SUM(quantity_sold_after_promo - quantity_sold_before_promo) AS incremental_sold_units
    FROM fact_events 
    GROUP BY promotion_category
)

SELECT 
    promotion_category,
    incremental_revenue,
    incremental_sold_units,
    RANK() OVER (ORDER BY incremental_revenue DESC) AS incremental_revenue_rank,
    RANK() OVER (ORDER BY incremental_sold_units DESC) AS incremental_sold_units_rank
FROM promotion_performance
ORDER BY incremental_revenue DESC;

--- 7 Determine the optimal balance between achieving Incremental Sold Units and maintaining healthy profit margins.
WITH event_calculations AS (
    SELECT 
        fe.promo_type,
        fe.base_price * cm.cost_margin / 100 AS cost_price,
        fe.base_price - (fe.base_price * cm.cost_margin / 100) AS profit_per_unit,
        fe.quantity_sold_after_promo - fe.quantity_sold_before_promo AS incremental_units
    FROM fact_events fe
    INNER JOIN cost_margin cm 
    ON fe.product_code = cm.product_code
),
promo_summary AS (
    SELECT 
        promo_type,
        SUM(incremental_units) AS total_incremental_units,
        SUM(profit_per_unit * incremental_units) AS total_incremental_profit,
        AVG(profit_per_unit) AS avg_profit_per_unit,
        CASE
            WHEN AVG(profit_per_unit) < 300 THEN 'Low Margin'
            WHEN AVG(profit_per_unit) BETWEEN 300 AND 900 THEN 'Healthy Margin'
            ELSE 'High Margin'
        END AS profit_margin_bucket
    FROM event_calculations
    GROUP BY promo_type
),
promo_ranks AS (
    SELECT 
        promo_type,
        total_incremental_units,
        total_incremental_profit,
        avg_profit_per_unit,
        profit_margin_bucket,
        RANK() OVER (ORDER BY total_incremental_units DESC) AS rank_by_units,
        RANK() OVER (ORDER BY avg_profit_per_unit DESC) AS rank_by_profit_per_unit
    FROM promo_summary
)
SELECT 
    promo_type,
    total_incremental_units,
    total_incremental_profit,
    avg_profit_per_unit,
    profit_margin_bucket,
    rank_by_units,
    rank_by_profit_per_unit,
    (rank_by_units + rank_by_profit_per_unit) AS optimal_balance_score  -- lower = better balance
FROM promo_ranks
ORDER BY optimal_balance_score ASC, total_incremental_units DESC;

--- 8 Identify the product categories that experience the most significant sales lift during discount campaigns.
WITH discount_sales AS (
    SELECT
        dp.category,
    
        SUM(fe.base_price * fe.quantity_sold_after_promo) - SUM(fe.base_price * fe.quantity_sold_before_promo) AS sales_lift_revenue,
        SUM(fe.quantity_sold_after_promo) - SUM(fe.quantity_sold_before_promo) AS sales_lift_sold_units,
        (SUM(fe.quantity_sold_after_promo) - SUM(fe.quantity_sold_before_promo)) * 100 / SUM(fe.quantity_sold_before_promo) AS sales_lift_sold_percentage

    FROM fact_events fe
    INNER JOIN dim_products dp
    ON fe.product_code = dp.product_code

    WHERE fe.promo_type IN ('50% OFF', '33% OFF', '25% OFF')  

    GROUP BY dp.category
)
SELECT
    category,
    sales_lift_revenue,
    sales_lift_sold_units,
    sales_lift_sold_percentage

FROM discount_sales

ORDER BY sales_lift_revenue DESC;

--- 9 Pinpoint specific products that demonstrate exceptional performance, either positively or negatively in response to promotions.
WITH product_performance AS (
    SELECT 
        dp.product_code,
        dp.product_name,
        dp.category, 

        SUM(fe.base_price * fe.quantity_sold_before_promo) AS revenue_before,
        SUM(fe.base_price * fe.quantity_sold_after_promo) AS revenue_after, 
        SUM(fe.base_price * (fe.quantity_sold_after_promo - fe.quantity_sold_before_promo)) AS incremental_revenue,
        SUM(fe.quantity_sold_after_promo - fe.quantity_sold_before_promo) AS incremental_sold_units

    FROM fact_events fe
    INNER JOIN dim_products dp
    ON fe.product_code = dp.product_code
    GROUP BY dp.product_code, dp.product_name, dp.category
)
SELECT 
    product_code,
    product_name,
    category,
    incremental_revenue,
    incremental_sold_units,
    CASE
        WHEN incremental_revenue > 0 AND incremental_sold_units > 0 THEN 'Exceptional Positive'
        WHEN incremental_revenue < 0 AND incremental_sold_units < 0 THEN 'Exceptional Negative'
        WHEN incremental_revenue > 0 AND incremental_sold_units < 0 THEN 'Mixed (Revenue ↑, Units ↓)' 
        WHEN incremental_revenue < 0 AND incremental_sold_units > 0 THEN 'Mixed (Revenue ↓, Units ↑)'
    END AS performance_flag
 
FROM product_performance
ORDER BY incremental_revenue DESC;

--- 10 Examine the correlation between product categories and the effectiveness of various promotion types.
WITH category_promo_performance AS (
    SELECT 
        dp.category,

        fe.promo_type,
        SUM(fe.base_price * (fe.quantity_sold_after_promo - fe.quantity_sold_before_promo)) AS incremental_revenue,
        SUM(fe.quantity_sold_after_promo - fe.quantity_sold_before_promo) AS incremental_units

    FROM fact_events fe

    INNER JOIN dim_products dp 
    ON fe.product_code = dp.product_code
    GROUP BY dp.category, fe.promo_type
)
SELECT 
    category,
    promo_type,
    incremental_revenue,
    incremental_units,
    RANK() OVER (PARTITION BY category ORDER BY incremental_revenue DESC) AS revenue_rank_in_category,
    RANK() OVER (PARTITION BY category ORDER BY incremental_units DESC) AS units_rank_in_category

FROM category_promo_performance

ORDER BY category,incremental_revenue DESC;


