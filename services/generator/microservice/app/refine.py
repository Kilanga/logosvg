"""Chat de retouche : transforme une demande du client en nouvelle description d'image.

Le client écrit « enlève le skateboard, mets-le plus souriant » ; le modèle local fusionne
cette demande dans la description anglaise déjà utilisée, et SDXL repart de l'image existante.
Sans Ollama, on se rabat sur une simple concaténation : moins fin, mais jamais bloquant.
"""
import logging

import httpx

from .config import settings
from .translate import to_english

log = logging.getLogger(__name__)

SYSTEM = (
    "You maintain a short English description of a t-shirt design for an image generator. "
    "Apply the user's change request to the current description. Keep everything the user "
    "did not ask to change. Answer with the new description only: one line, English, "
    "under 200 characters, no quotes, no comments."
)

MAX_SUBJECT = 300


def _fallback(subject: str, instruction: str) -> str:
    return f"{subject}, {instruction}"[:MAX_SUBJECT]


async def apply_instruction(subject: str, instruction: str) -> str:
    """Renvoie la nouvelle description anglaise du design."""
    instruction_en = await to_english(instruction)
    if not settings.ollama_url:
        return _fallback(subject, instruction_en)

    payload = {
        "model": settings.ollama_model,
        "stream": False,
        # Décharge le modèle aussitôt pour laisser la VRAM à ComfyUI.
        "keep_alive": 0,
        "options": {"temperature": 0.2},
        "messages": [
            {"role": "system", "content": SYSTEM},
            {"role": "user", "content": f"Current description: {subject}\nChange request: {instruction_en}"},
        ],
    }
    try:
        async with httpx.AsyncClient(timeout=60) as client:
            resp = await client.post(f"{settings.ollama_url.rstrip('/')}/api/chat", json=payload)
            resp.raise_for_status()
            merged = resp.json()["message"]["content"].strip().strip('"')
            return merged[:MAX_SUBJECT] or _fallback(subject, instruction_en)
    except Exception as exc:  # une retouche ne doit jamais échouer sur la réécriture
        log.warning("Réécriture indisponible, repli sur la concaténation : %s", exc)
        return _fallback(subject, instruction_en)
