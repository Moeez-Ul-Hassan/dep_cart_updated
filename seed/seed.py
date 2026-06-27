import sys
import os
import time
import random
import uuid
from faker import Faker
import structlog

# Tell Python where the root directory is
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from sqlalchemy import insert
from app.database.session import SessionLocal # Ensure this path is correct for your repo
from app.models.domain import User, Product, Cart, CartItem

logger = structlog.get_logger()
fake = Faker()

# --- CONFIGURATION ---
TOTAL_USERS = 100_000
TOTAL_PRODUCTS = 10_000
TOTAL_CARTS = 200_000
BATCH_SIZE = 10_000

def seed_in_batches(db, model, data_list):
    """Inserts data in chunks to prevent memory crashes."""
    logger.info(f"Starting bulk insert for {model.__tablename__}", target=len(data_list))
    start_time = time.time()
    
    for i in range(0, len(data_list), BATCH_SIZE):
        batch = data_list[i:i + BATCH_SIZE]
        db.execute(insert(model).values(batch))
        db.commit()
        
        logger.info("batch_inserted", table=model.__tablename__, current=min(i+BATCH_SIZE, len(data_list)), total=len(data_list))

    end_time = time.time()
    logger.info(f"Finished {model.__tablename__}", duration_seconds=round(end_time - start_time, 2))

def run_seeder():
    db = SessionLocal()
    try:
        # 1. Seed Users
        users_data = [
            {"email": f"user_{uuid.uuid4().hex[:8]}@example.com", "name": fake.name()} 
            for _ in range(TOTAL_USERS)
        ]
        seed_in_batches(db, User, users_data)
        
        # 2. Seed Products
        products_data = [
            {
                "name": fake.catch_phrase(),
                "price": round(random.uniform(10.0, 1500.0), 2),
                "stock": random.randint(50, 1000),
                "reserved_stock": 0
            }
            for _ in range(TOTAL_PRODUCTS)
        ]
        seed_in_batches(db, Product, products_data)

        # Fetch IDs to link relations
        logger.info("Fetching IDs for relational mapping...")
        user_ids = [u[0] for u in db.query(User.id).all()]
        product_ids = [p[0] for p in db.query(Product.id).all()]

        # 3. Seed Carts
        carts_data = [
            {
                "user_id": random.choice(user_ids),
                "status": random.choice(["active", "completed", "abandoned"]),
                "total_amount": 0.0
            }
            for _ in range(TOTAL_CARTS)
        ]
        seed_in_batches(db, Cart, carts_data)

        # 4. Seed Cart Items
        logger.info("Generating Cart Items...")
        cart_ids = [c[0] for c in db.query(Cart.id).all()]
        items_data = []
        
        for cart_id in cart_ids:
            # Each cart gets 1 to 4 items
            for _ in range(random.randint(1, 4)):
                items_data.append({
                    "cart_id": cart_id,
                    "product_id": random.choice(product_ids),
                    "quantity": random.randint(1, 5),
                    "price_at_addition": round(random.uniform(10.0, 500.0), 2)
                })
        seed_in_batches(db, CartItem, items_data)

        logger.info("✅ ALL SEEDING COMPLETE!")

    except Exception as e:
        logger.error("seeding_failed", error=str(e))
        db.rollback()
    finally:
        db.close()

if __name__ == "__main__":
    run_seeder()