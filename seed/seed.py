import sys
import os
import time
import random
from faker import Faker
import structlog

# --- FIX: Tell Python where the root directory is ---
# This allows the script to find the 'app' folder no matter how you run it.
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from sqlalchemy import insert
from app.database.session import SessionLocal
from app.models.domain import User, Product, Cart, CartItem

logger = structlog.get_logger()
fake = Faker()

# Adjust these numbers to hit 1 Million. 
# WARNING: Start with 100,000 to test your laptop's CPU/Memory before going to 1,000,000.
TOTAL_USERS = 100000
TOTAL_PRODUCTS = 100000
BATCH_SIZE = 10000

def seed_in_batches(db, model, data_generator, total_records):
    """Inserts data in chunks to prevent memory crashes."""
    logger.info(f"Starting bulk insert for {model.__tablename__}", target=total_records)
    start_time = time.time()
    
    for i in range(0, total_records, BATCH_SIZE):
        batch = [next(data_generator) for _ in range(BATCH_SIZE)]
        db.execute(insert(model).values(batch))
        db.commit()
        
        logger.info("batch_inserted", table=model.__tablename__, current=i+BATCH_SIZE, total=total_records)

    end_time = time.time()
    logger.info(f"Finished {model.__tablename__}", duration_seconds=round(end_time - start_time, 2))

# --- Data Generators ---

def generate_user():
    return {
        "email": fake.unique.email(),
        "name": fake.name()
    }

def generate_product():
    return {
        "name": fake.catch_phrase(),
        "price": round(random.uniform(10.0, 500.0), 2),
        "stock": random.randint(100, 10000),
        "reserved_stock": 0
    }

def run_seeder():
    db = SessionLocal()
    try:
        # 1. Seed Users
        user_gen = (generate_user() for _ in iter(int, 1))
        seed_in_batches(db, User, user_gen, TOTAL_USERS)
        
        # 2. Seed Products
        product_gen = (generate_product() for _ in iter(int, 1))
        seed_in_batches(db, Product, product_gen, TOTAL_PRODUCTS)
        
    except Exception as e:
        logger.error("seeding_failed", error=str(e))
        db.rollback()
    finally:
        db.close()

if __name__ == "__main__":
    run_seeder()