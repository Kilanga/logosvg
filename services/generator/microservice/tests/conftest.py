import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

os.environ.setdefault("API_KEY", "test-key")
os.environ["GENERATOR_MODE"] = "mock"
os.environ["OLLAMA_URL"] = ""
os.environ["RATE_LIMIT_COUNT"] = "3"
os.environ["BLOCKLIST_FILE"] = str(ROOT / "blocklist.txt")
os.environ["DATA_DIR"] = str(ROOT / "tests" / "_data")
