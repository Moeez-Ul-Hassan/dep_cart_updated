-- SILVER LAYER: Creating structured Parquet storage locations
CREATE EXTERNAL TABLE IF NOT EXISTS users_silver (
  id INT, email STRING, name STRING, created_at STRING, updated_at STRING
) STORED AS PARQUET LOCATION 's3://YOUR_BUCKET_NAME/silver_layer/users/';

-- ... (Include the CREATE EXTERNAL TABLE statements for products, carts, cart_items) ...

-- SILVER LAYER: ETL Transformation and Deduplication
INSERT INTO users_silver
SELECT id, email, name, created_at, updated_at
FROM (SELECT *, ROW_NUMBER() OVER(PARTITION BY id ORDER BY updated_at DESC) as rank FROM users_bronze) WHERE rank = 1;

-- (Include the INSERT INTO statements for products, carts, cart_items here as well)