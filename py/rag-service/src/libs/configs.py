import os
from pathlib import Path

# Configuration
BASE_DATA_DIR = Path(os.environ.get("DATA_DIR", "data"))
CHROMA_PERSIST_DIR = BASE_DATA_DIR / "chroma_db"
LOG_DIR = BASE_DATA_DIR / "logs"
DB_FILE = BASE_DATA_DIR / "sqlite" / "indexing_history.db"

# Configure directories
BASE_DATA_DIR.mkdir(parents=True, exist_ok=True)
LOG_DIR.mkdir(parents=True, exist_ok=True)
DB_FILE.parent.mkdir(parents=True, exist_ok=True)  # Create sqlite directory
CHROMA_PERSIST_DIR.mkdir(parents=True, exist_ok=True)
