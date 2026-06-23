import redis
from app.core.config import settings
import structlog

logger = structlog.get_logger()

# Create a connection pool so we don't open/close connections on every single request
redis_pool = redis.ConnectionPool.from_url(settings.REDIS_URL, decode_responses=True)

def get_redis():
    """Dependency to inject Redis client into services."""
    client = redis.Redis(connection_pool=redis_pool)
    try:
        # Quick ping to ensure it's alive
        client.ping()
        yield client
    except redis.ConnectionError as e:
        logger.error("redis_connection_failed", error=str(e))
        raise