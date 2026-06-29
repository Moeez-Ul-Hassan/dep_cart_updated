import json
import boto3
import pymysql
import os
from datetime import datetime

s3 = boto3.client('s3')

def lambda_handler(event, context):
    db_host = os.environ['DB_HOST']
    db_user = os.environ['DB_USER']
    db_pass = os.environ['DB_PASS']
    db_name = os.environ['DB_NAME']
    s3_bucket = os.environ['S3_BUCKET']
    
    BATCH_SIZE = 10000 
    tables_to_extract = ["carts", "cart_items", "products", "users"]
    
    current_run_time = datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S')
    file_timestamp = datetime.utcnow().strftime('%Y-%m-%d_%H-%M-%S')
    total_rows = 0

    print(f"Connecting to database: {db_host}...")
    try:
        connection = pymysql.connect(
            host=db_host, user=db_user, password=db_pass, database=db_name
        )
    except Exception as e:
        raise e

    def default_converter(o):
        if isinstance(o, datetime):
            return o.__str__()

    with connection:
        with connection.cursor() as schema_cursor:
            with connection.cursor(pymysql.cursors.SSDictCursor) as data_cursor:
                
                for table in tables_to_extract:
                    
                    # 1. DYNAMIC SCHEMA INTROSPECTION (With SQLAlchemy NULL Fix)
                    schema_cursor.execute(f"SHOW COLUMNS FROM {table}")
                    columns = [row[0].lower() for row in schema_cursor.fetchall()]
                    
                    if "updated_at" in columns and "created_at" in columns:
                        track_col, col_type = "COALESCE(updated_at, created_at)", "timestamp"
                    elif "updated_at" in columns:
                        track_col, col_type = "updated_at", "timestamp"
                    elif "created_at" in columns:
                        track_col, col_type = "created_at", "timestamp"
                    elif "id" in columns:
                        track_col, col_type = "id", "id"
                    else:
                        track_col = None

                    default_watermark = '0' if col_type == 'id' else '1970-01-01 00:00:00'

                    # 2. READ THE WATERMARK
                    watermark_key = f"watermarks/{table}_watermark.txt"
                    try:
                        obj = s3.get_object(Bucket=s3_bucket, Key=watermark_key)
                        last_run = obj['Body'].read().decode('utf-8')
                    except s3.exceptions.NoSuchKey:
                        last_run = default_watermark

                    # 3. BUILD THE QUERY
                    if track_col:
                        query = f"SELECT * FROM {table} WHERE {track_col} > '{last_run}'"
                        print(f"[{table}] Incremental Load: {track_col} > {last_run}")
                    else:
                        query = f"SELECT * FROM {table}"
                        print(f"[{table}] No tracking column. Doing Full Load.")

                    data_cursor.execute(query)
                    
                    batch_number = 1
                    rows_extracted_for_table = 0
                    max_id_extracted = int(last_run) if col_type == "id" else 0
                    
                    # 4. STREAM AND UPLOAD (Memory Safe)
                    while True:
                        rows = data_cursor.fetchmany(BATCH_SIZE)
                        if not rows:
                            break 
                        
                        if col_type == "id":
                            batch_max_id = max(row['id'] for row in rows)
                            if batch_max_id > max_id_extracted:
                                max_id_extracted = batch_max_id

                        json_lines = "\n".join([json.dumps(row, default=default_converter) for row in rows])
                        file_key = f"raw_database/{table}/extract_{file_timestamp}_part{batch_number}.json"
                        
                        s3.put_object(Bucket=s3_bucket, Key=file_key, Body=json_lines)
                        
                        rows_extracted_for_table += len(rows)
                        total_rows += len(rows)
                        batch_number += 1
                        
                    # 5. ADVANCE THE WATERMARK
                    if track_col and rows_extracted_for_table > 0:
                        new_watermark = current_run_time if col_type == "timestamp" else str(max_id_extracted)
                        s3.put_object(Bucket=s3_bucket, Key=watermark_key, Body=new_watermark)
                        print(f"[{table}] Watermark advanced to {new_watermark}")
                    elif track_col:
                        print(f"[{table}] No new rows. Watermark remains {last_run}")
                        
    return {
        'statusCode': 200,
        'body': json.dumps(f'Pipeline Success! Processed {total_rows} rows.')
    }