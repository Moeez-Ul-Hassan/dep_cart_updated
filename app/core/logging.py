import logging
import sys
import os
import structlog
from logging.handlers import RotatingFileHandler

def setup_logging():
    """Configures structured JSON logging for AWS CloudWatch and Local Disk."""
    
    # 1. Create a 'logs' directory in the root folder if it doesn't exist
    os.makedirs("logs", exist_ok=True)

    # 2. Console Handler (Crucial for AWS CloudWatch / Docker daemon)
    console_handler = logging.StreamHandler(sys.stdout)

    # 3. File Handler (Crucial for local debugging)
    # RotatingFileHandler prevents the file from growing to 100GB and crashing your laptop
    file_handler = RotatingFileHandler(
        filename="logs/enterprise_cart.log",
        maxBytes=5 * 1024 * 1024,  # Automatically creates a new file after 5 MB
        backupCount=3              # Keeps the last 3 files, deletes older ones
    )

    # Attach BOTH handlers to the base Python logger
    logging.basicConfig(
        format="%(message)s",
        level=logging.INFO,
        handlers=[console_handler, file_handler]
    )

    structlog.configure(
        processors=[
            structlog.stdlib.add_log_level,
            structlog.stdlib.add_logger_name,
            structlog.processors.TimeStamper(fmt="iso"),
            # This is the magic line that outputs strict JSON for AWS tools
            structlog.processors.JSONRenderer() 
        ],
        context_class=dict,
        logger_factory=structlog.stdlib.LoggerFactory(),
        wrapper_class=structlog.stdlib.BoundLogger,
        cache_logger_on_first_use=True,
    )