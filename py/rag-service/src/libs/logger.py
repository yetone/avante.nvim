import logging
from datetime import datetime

from libs.configs import LOG_DIR

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s",
    handlers=[
        logging.FileHandler(
            LOG_DIR / f"rag_service_{datetime.now().astimezone().strftime('%Y%m%d')}.log",
        ),
        logging.StreamHandler(),
    ],
)
logger = logging.getLogger(__name__)
