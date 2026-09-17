"""Configuration lue depuis les variables d'environnement (.env)."""
import os
from dataclasses import dataclass
from pathlib import Path

from dotenv import load_dotenv

load_dotenv()


def _int(name: str, default: int) -> int:
    return int(os.getenv(name, str(default)))


@dataclass(frozen=True)
class Settings:
    api_key: str = os.getenv("API_KEY", "")

    generator_mode: str = os.getenv("GENERATOR_MODE", "mock")
    comfyui_url: str = os.getenv("COMFYUI_URL", "http://127.0.0.1:8188")
    comfyui_checkpoint: str = os.getenv("COMFYUI_CHECKPOINT", "sd_xl_base_1.0.safetensors")
    comfyui_timeout: int = _int("COMFYUI_TIMEOUT", 180)
    image_size: int = _int("IMAGE_SIZE", 1024)

    ollama_url: str = os.getenv("OLLAMA_URL", "")
    ollama_model: str = os.getenv("OLLAMA_MODEL", "qwen2.5:3b")

    rate_limit_count: int = _int("RATE_LIMIT_COUNT", 5)
    rate_limit_window: int = _int("RATE_LIMIT_WINDOW_SECONDS", 3600)
    max_queue: int = _int("MAX_QUEUE", 10)
    blocklist_file: Path = Path(os.getenv("BLOCKLIST_FILE", "blocklist.txt"))

    data_dir: Path = Path(os.getenv("DATA_DIR", "data"))
    job_ttl: int = _int("JOB_TTL_SECONDS", 3600)
    max_paths_warning: int = _int("MAX_PATHS_WARNING", 400)


settings = Settings()
