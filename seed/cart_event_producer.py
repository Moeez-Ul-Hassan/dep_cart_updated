import boto3
import json
import time
import random
import uuid
import structlog
from datetime import datetime, timezone

logger = structlog.get_logger()

# Initialize AWS Kinesis Firehose Client
AWS_REGION = 'us-east-1'
STREAM_NAME = 'cart-events-firehose'

try:
    firehose = boto3.client('firehose', region_name=AWS_REGION)
    logger.info("✅ Successfully connected to AWS Kinesis Firehose!")
except Exception as e:
    logger.error("❌ Failed to connect to AWS.", error=str(e))
    exit(1)

EVENT_TYPES = ["cart_add", "cart_remove", "view_item", "checkout_start", "checkout_complete"]
PRODUCT_IDS = [101, 102, 103, 104, 105, 106, 107, 108, 109, 110]
PLATFORMS = ["ios", "android", "web"]

def generate_ecommerce_event():
    event_type = random.choice(EVENT_TYPES)
    return {
        "event_id": f"evt_{uuid.uuid4().hex[:8]}",
        "user_id": random.randint(1000, 9999),
        "event_type": event_type,
        "product_id": random.choice(PRODUCT_IDS),
        "quantity": random.randint(1, 5) if event_type in ["cart_add", "cart_remove"] else 0,
        "platform": random.choice(PLATFORMS),
        "timestamp": datetime.now(timezone.utc).isoformat()
    }

def start_aws_stream():
    logger.info(f"🚀 Streaming live traffic directly to AWS Kinesis: {STREAM_NAME}...")
    
    try:
        while True:
            event = generate_ecommerce_event()
            
            # Fire the event directly into the AWS Cloud
            firehose.put_record(
                DeliveryStreamName=STREAM_NAME,
                Record={
                    # Firehose requires data to be bytes, and we add a newline \n to separate JSON objects
                    'Data': (json.dumps(event) + '\n').encode('utf-8') 
                }
            )
            
            logger.info("aws_kinesis_put", event_type=event["event_type"], user_id=event["user_id"])
            time.sleep(0.1)
            
    except KeyboardInterrupt:
        logger.info("🛑 AWS stream stopped manually.")
    except Exception as e:
        logger.error("stream_failure", error=str(e))

if __name__ == "__main__":
    start_aws_stream()