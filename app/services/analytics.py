import boto3
import json
import uuid
import structlog
from datetime import datetime, timezone

logger = structlog.get_logger()

# --- CONFIGURATION ---
AWS_REGION = 'us-east-1'
STREAM_NAME = 'cart-events-firehose'

# Initialize the client outside the function so it only boots up once when the server starts
try:
    firehose_client = boto3.client('firehose', region_name=AWS_REGION)
    logger.info("✅ Analytics service successfully connected to AWS Kinesis Firehose.")
except Exception as e:
    logger.error("❌ kinesis_init_failed", error=str(e))
    firehose_client = None

def track_cart_event(user_id: int, event_type: str, product_id: int = None, quantity: int = 0, platform: str = "web"):
    """
    Silently sends an e-commerce event to AWS Kinesis Firehose.
    Designed to be run asynchronously as a FastAPI Background Task.
    """
    if not firehose_client:
        logger.warning("analytics_skipped", reason="Firehose client not initialized")
        return

    try:
        event = {
            "event_id": f"evt_{uuid.uuid4().hex[:8]}",
            "user_id": user_id,
            "event_type": event_type,
            "product_id": product_id,
            "quantity": quantity,
            "platform": platform,
            "timestamp": datetime.now(timezone.utc).isoformat()
        }

        firehose_client.put_record(
            DeliveryStreamName=STREAM_NAME,
            Record={
                'Data': (json.dumps(event) + '\n').encode('utf-8')
            }
        )
        logger.info("aws_event_streamed", event_type=event_type, user_id=user_id, product_id=product_id)
        
    except Exception as e:
        logger.error("aws_event_failed", error=str(e), event_type=event_type)