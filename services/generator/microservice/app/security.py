"""Authentification par clé partagée et limitation de débit."""
import hmac
import time
from collections import defaultdict, deque
from threading import Lock
from typing import Optional

from fastapi import Header, HTTPException

from .config import settings


def require_api_key(x_api_key: str = Header(default="")) -> None:
    """Seul le site WordPress, qui connaît la clé, peut appeler le service."""
    expected = settings.api_key.encode()
    if not expected or not hmac.compare_digest(x_api_key.encode(), expected):
        raise HTTPException(status_code=401, detail="Clé API invalide.")


class RateLimiter:
    """Fenêtre glissante en mémoire : N générations par utilisateur sur une période."""

    def __init__(self, count: int, window_seconds: int):
        self.count = count
        self.window = window_seconds
        self._hits: dict = defaultdict(deque)
        self._lock = Lock()

    def hit(self, key: str) -> Optional[int]:
        """Enregistre une tentative. Renvoie le délai d'attente en secondes si la limite est atteinte."""
        now = time.monotonic()
        with self._lock:
            hits = self._hits[key]
            while hits and now - hits[0] >= self.window:
                hits.popleft()
            if len(hits) >= self.count:
                return int(self.window - (now - hits[0])) + 1
            hits.append(now)
            return None
