from fastapi import FastAPI
from app.routers import cart
from app.database.session import engine
from app.models.domain import Base
from app.core.logging import setup_logging

# Import the new exceptions and handlers
from app.exceptions.business_logic import (
    ProductNotFoundException, CartNotFoundException, 
    InsufficientStockException, CartNotActiveException
)
from app.exceptions.handlers import (
    product_not_found_handler, cart_not_found_handler,
    insufficient_stock_handler, cart_not_active_handler
)

setup_logging()
Base.metadata.create_all(bind=engine)

app = FastAPI(
    title="Enterprise Cart Platform v2",
    version="1.0.0"
)

# --- Register Global Exception Handlers ---
app.add_exception_handler(ProductNotFoundException, product_not_found_handler)
app.add_exception_handler(CartNotFoundException, cart_not_found_handler)
app.add_exception_handler(InsufficientStockException, insufficient_stock_handler)
app.add_exception_handler(CartNotActiveException, cart_not_active_handler)

app.include_router(cart.router, prefix="/api/v1/carts", tags=["Carts"])

@app.get("/health")
def health_check():
    return {"status": "healthy", "service": "Cart API"}