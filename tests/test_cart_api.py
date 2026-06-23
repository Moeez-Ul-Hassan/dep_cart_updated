import pytest
from app.models.domain import Product

# --- POSITIVE TESTS ---

def test_create_new_cart(client):
    response = client.post("/api/v1/carts/?user_id=777")
    assert response.status_code == 200
    assert response.json()["user_id"] == 777

def test_add_item_inventory_math(client, db_session):
    db_session.add(Product(id=1, name="Test Keyboard", price=150.0, stock=10, reserved_stock=0))
    db_session.commit()

    cart_id = client.post("/api/v1/carts/?user_id=777").json()["id"]
    response = client.post(f"/api/v1/carts/{cart_id}/items", json={"product_id": 1, "quantity": 2})
    
    assert response.status_code == 200
    assert response.json()["total_amount"] == 300.0

def test_idempotent_checkout_blocks_double_charge(client, db_session):
    db_session.add(Product(id=2, name="Mouse", price=50.0, stock=5, reserved_stock=0))
    db_session.commit()
    cart_id = client.post("/api/v1/carts/?user_id=999").json()["id"]
    client.post(f"/api/v1/carts/{cart_id}/items", json={"product_id": 2, "quantity": 1})

    # First Click: Should succeed
    resp1 = client.post(f"/api/v1/carts/{cart_id}/checkout", headers={"x-idempotency-key": "lock-123"})
    assert resp1.status_code == 200
    assert resp1.json()["message"] == "Order placed successfully"

    # Second Click: Should be intercepted by Redis mock
    resp2 = client.post(f"/api/v1/carts/{cart_id}/checkout", headers={"x-idempotency-key": "lock-123"})
    assert resp2.status_code == 200
    assert resp2.json()["message"] == "Order was already placed successfully. (Cached)"

# --- NEGATIVE & SECURITY TESTS (Parameterization) ---

@pytest.mark.parametrize("invalid_user_id", [
    0, -1, -999, "abc", "12.5"
])
def test_create_cart_invalid_user_blocks(client, invalid_user_id):
    """Bombards the endpoint with bad data. FastAPI should catch this before the DB."""
    response = client.post(f"/api/v1/carts/?user_id={invalid_user_id}")
    assert response.status_code == 422 # 422 is standard for Unprocessable Entity (Validation Error)

@pytest.mark.parametrize("invalid_cart_id", [
    0, -1, "cart_nine"
])
def test_add_item_invalid_cart_id(client, invalid_cart_id):
    response = client.post(
        f"/api/v1/carts/{invalid_cart_id}/items", 
        json={"product_id": 1, "quantity": 1}
    )
    assert response.status_code == 422

@pytest.mark.parametrize("payload", [
    {"product_id": -1, "quantity": 1},
    {"product_id": 1, "quantity": -5},
    {"product_id": 1, "quantity": 0},
    {"product_id": "laptop", "quantity": 1}
])
def test_add_item_invalid_payload_blocks(client, db_session, payload):
    cart_id = client.post("/api/v1/carts/?user_id=101").json()["id"]
    response = client.post(f"/api/v1/carts/{cart_id}/items", json=payload)
    assert response.status_code == 422

def test_insufficient_stock_error(client, db_session):
    db_session.add(Product(id=3, name="Rare GPU", price=500.0, stock=1, reserved_stock=0))
    db_session.commit()

    cart_id = client.post("/api/v1/carts/?user_id=888").json()["id"]
    response = client.post(f"/api/v1/carts/{cart_id}/items", json={"product_id": 3, "quantity": 5})
    
    assert response.status_code == 409
    assert response.json()["error_code"] == "INSUFFICIENT_STOCK"

def test_checkout_missing_idempotency_header(client, db_session):
    cart_id = client.post("/api/v1/carts/?user_id=888").json()["id"]
    # Missing the 'x-idempotency-key' header entirely
    response = client.post(f"/api/v1/carts/{cart_id}/checkout")
    
    assert response.status_code == 422
    assert response.json()["detail"][0]["loc"] == ["header", "x-idempotency-key"]