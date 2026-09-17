"""Traduction optionnelle FR -> EN via Ollama (SDXL comprend mieux l'anglais)."""
import logging

import httpx

from .config import settings

log = logging.getLogger(__name__)

SYSTEM = (
    "Translate the user's t-shirt design idea into a short English description "
    "for an image generator. Output only the translation, without quotes or comments."
)


async def to_english(text: str) -> str:
    if not settings.ollama_url:
        return text
    payload = {
        "model": settings.ollama_model,
        "stream": False,
        # Décharge le modèle aussitôt pour laisser la VRAM à ComfyUI.
        "keep_alive": 0,
        "options": {"temperature": 0},
        "messages": [
            {"role": "system", "content": SYSTEM},
            {"role": "user", "content": text},
        ],
    }
    try:
        async with httpx.AsyncClient(timeout=60) as client:
            resp = await client.post(f"{settings.ollama_url.rstrip('/')}/api/chat", json=payload)
            resp.raise_for_status()
            translated = resp.json()["message"]["content"].strip().strip('"')
            return translated[:300] or text
    except Exception as exc:  # la traduction ne doit jamais bloquer la génération
        log.warning("Traduction indisponible, prompt d'origine conservé : %s", exc)
        return text
