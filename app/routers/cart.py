from fastapi import APIRouter, Depends, Header, Path, Query
from sqlalchemy.orm import Session
from redis import Redis
import structlog

from app.database.session import get_db
from app.database.redis_client import get_redis
from app.services.cart_service import CartService

from app.schemas.domain import CartResponse, CartItemCreate, CartItemUpdate, BillResponse
from app.models.domain import Cart, CartItem, Product
from app.exceptions.business_logic import (
    ProductNotFoundException, 
    CartNotFoundException, 
    InsufficientStockException, 
    CartNotActiveException,
    ItemNotFoundInCartException
)

logger = structlog.get_logger()
router = APIRouter()

@router.post("/", response_model=CartResponse)
def create_cart(
    user_id: int = Query(..., gt=0, description="User ID must be positive"), 
    db: Session = Depends(get_db)
):
    existing_cart = db.query(Cart).filter(Cart.user_id == user_id, Cart.status == "active", Cart.is_deleted == False).first()
    if existing_cart:
        return existing_cart
        
    new_cart = Cart(user_id=user_id, status="active", total_amount=0.0)
    db.add(new_cart)
    db.commit()
    db.refresh(new_cart)
    
    logger.info("cart_created", cart_id=new_cart.id, user_id=user_id)
    return new_cart

@router.post("/{cart_id}/items", response_model=CartResponse)
def add_item_to_cart(
    item: CartItemCreate,
    cart_id: int = Path(..., gt=0, description="Cart ID must be positive"), 
    db: Session = Depends(get_db)
):
    # 1. Check Cart
    cart = db.query(Cart).filter(Cart.id == cart_id).first()
    if not cart:
        raise CartNotFoundException(cart_id=cart_id)
    if cart.status != "active":
        raise CartNotActiveException(cart_id=cart_id, current_status=cart.status)
        
    # 2. Check Product
    product = db.query(Product).filter(Product.id == item.product_id).first()
    if not product:
        raise ProductNotFoundException(product_id=item.product_id)
        
    # 3. Check Inventory Math
    available_stock = product.stock - product.reserved_stock
    if available_stock < item.quantity:
        raise InsufficientStockException(
            product_id=product.id, 
            requested_qty=item.quantity, 
            available_qty=available_stock
        )
        
    # 4. Process Item
    cart_item = CartItem(
        cart_id=cart.id, 
        product_id=product.id, 
        quantity=item.quantity,
        price_at_addition=product.price
    )
    
    cart.total_amount += (product.price * item.quantity)
    product.reserved_stock += item.quantity
    
    db.add(cart_item)
    db.commit()
    db.refresh(cart)
    
    logger.info("item_added", cart_id=cart.id, product_id=product.id, quantity=item.quantity)
    return cart

@router.post("/{cart_id}/checkout")
def checkout_cart(
    cart_id: int = Path(..., gt=0), 
    x_idempotency_key: str = Header(...), 
    db: Session = Depends(get_db),
    cache: Redis = Depends(get_redis)
):
    """Checkout utilizing an idempotency key and Redis to prevent double charging."""
    service = CartService(db=db, cache=cache)
    return service.checkout_cart(cart_id=cart_id, idempotency_key=x_idempotency_key)

@router.get("/{cart_id}", response_model=CartResponse)
def get_cart(cart_id: int = Path(..., gt=0), db: Session = Depends(get_db)):
    """View the current cart."""
    cart = db.query(Cart).filter(Cart.id == cart_id).first()
    if not cart:
        raise CartNotFoundException(cart_id=cart_id)
    return cart

@router.delete("/{cart_id}/items/{product_id}", response_model=CartResponse)
def remove_item_from_cart(
    cart_id: int = Path(..., gt=0), 
    product_id: int = Path(..., gt=0), 
    db: Session = Depends(get_db)
):
    """Remove a product completely and release the reserved stock."""
    cart = db.query(Cart).filter(Cart.id == cart_id).first()
    if not cart:
        raise CartNotFoundException(cart_id=cart_id)
    if cart.status != "active":
        raise CartNotActiveException(cart_id=cart_id, current_status=cart.status)

    cart_item = db.query(CartItem).filter(CartItem.cart_id == cart_id, CartItem.product_id == product_id).first()
    if not cart_item:
        raise ItemNotFoundInCartException(cart_id=cart_id, product_id=product_id)

    product = db.query(Product).filter(Product.id == product_id).first()

    # Math: Subtract from cart total and release reserved stock
    cart.total_amount -= (cart_item.price_at_addition * cart_item.quantity)
    product.reserved_stock -= cart_item.quantity

    db.delete(cart_item)
    db.commit()
    db.refresh(cart)

    logger.info("item_removed", cart_id=cart.id, product_id=product.id)
    return cart

@router.get("/{cart_id}/bill", response_model=BillResponse)
def generate_bill(cart_id: int = Path(..., gt=0), db: Session = Depends(get_db)):
    """Generate an itemized bill with taxes."""
    cart = db.query(Cart).filter(Cart.id == cart_id).first()
    if not cart:
        raise CartNotFoundException(cart_id=cart_id)
    
    # Enterprise billing logic (Mock 16% Tax Rate for Punjab/Pakistan standard)
    tax_rate = 0.16 
    tax_amount = round(cart.total_amount * tax_rate, 2)
    grand_total = round(cart.total_amount + tax_amount, 2)

    logger.info("bill_generated", cart_id=cart.id, grand_total=grand_total)
    
    return BillResponse(
        cart_id=cart.id,
        subtotal=round(cart.total_amount, 2),
        tax_amount=tax_amount,
        grand_total=grand_total
    )

@router.delete("/{cart_id}")
def abandon_cart(cart_id: int = Path(..., gt=0), db: Session = Depends(get_db)):
    """Soft delete the cart and return all items to stock."""
    cart = db.query(Cart).filter(Cart.id == cart_id).first()
    if not cart:
        raise CartNotFoundException(cart_id=cart_id)
    if cart.status != "active":
        raise CartNotActiveException(cart_id=cart_id, current_status=cart.status)

    # Release all reserved stock back to the warehouse
    for item in cart.items:
        product = db.query(Product).filter(Product.id == item.product_id).first()
        if product:
            product.reserved_stock -= item.quantity

    # Soft delete the cart
    cart.status = "abandoned"
    cart.is_deleted = True
    db.commit()

    logger.info("cart_abandoned", cart_id=cart.id)
    return {"status": "success", "message": "Cart abandoned and inventory released"}