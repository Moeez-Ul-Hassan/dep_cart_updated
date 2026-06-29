-- BRONZE LAYER: Mapping raw JSON data from S3
CREATE EXTERNAL TABLE IF NOT EXISTS users_bronze (
  id INT, email STRING, name STRING, created_at STRING, updated_at STRING
) ROW FORMAT SERDE 'org.openx.data.jsonserde.JsonSerDe' 
LOCATION 's3://YOUR_BUCKET_NAME/raw_database/users/';

CREATE EXTERNAL TABLE IF NOT EXISTS products_bronze (
  id INT, name STRING, price DOUBLE, stock INT, reserved_stock INT
) ROW FORMAT SERDE 'org.openx.data.jsonserde.JsonSerDe' 
LOCATION 's3://YOUR_BUCKET_NAME/raw_database/products/';

CREATE EXTERNAL TABLE IF NOT EXISTS carts_bronze (
  id INT, user_id INT, status STRING, total_amount DOUBLE
) ROW FORMAT SERDE 'org.openx.data.jsonserde.JsonSerDe' 
LOCATION 's3://YOUR_BUCKET_NAME/raw_database/carts/';

CREATE EXTERNAL TABLE IF NOT EXISTS cart_items_bronze (
  id INT, cart_id INT, product_id INT, quantity INT, price_at_addition DOUBLE
) ROW FORMAT SERDE 'org.openx.data.jsonserde.JsonSerDe' 
LOCATION 's3://YOUR_BUCKET_NAME/raw_database/cart_items/';