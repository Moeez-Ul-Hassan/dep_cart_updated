import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.main import app
from app.database.session import get_db, Base
from app.database.redis_client import get_redis

# 1. Setup a lightning-fast, temporary SQLite database strictly for testing
SQLALCHEMY_DATABASE_URL = "sqlite:///:memory:"
engine = create_engine(
    SQLALCHEMY_DATABASE_URL,
    connect_args={"check_same_thread": False},
    poolclass=StaticPool,
)
TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

# 2. Setup a Fake Redis Cache in Python memory
class MockRedis:
    def __init__(self):
        self.cache = {}
    def get(self, key):
        return self.cache.get(key)
    def set(self, key, value, ex=None):
        self.cache[key] = value

# 3. Create the Database Fixture
@pytest.fixture(scope="function")
def db_session():
    """Creates a fresh database for every single test, then destroys it."""
    Base.metadata.create_all(bind=engine)
    db = TestingSessionLocal()
    try:
        yield db
    finally:
        db.close()
        Base.metadata.drop_all(bind=engine)

# 4. Inject the Overrides into FastAPI
@pytest.fixture(scope="function")
def client(db_session):
    """Provides a TestClient that uses our temporary DB and fake Redis."""
    
    # THE FIX: Shared state for the Redis mock so it remembers across multiple requests
    shared_mock_redis = MockRedis()
    
    def override_get_db():
        yield db_session
        
    def override_get_redis():
        yield shared_mock_redis

    # Tell FastAPI to swap out the real dependencies for our test ones
    app.dependency_overrides[get_db] = override_get_db
    app.dependency_overrides[get_redis] = override_get_redis

    with TestClient(app) as c:
        yield c