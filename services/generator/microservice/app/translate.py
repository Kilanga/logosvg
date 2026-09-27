"""Traduction optionnelle FR -> EN via Ollama (SDXL comprend mieux l'anglais)."""
import logging

import httpx

from .config import settings

log = logging.getLogger(__name__)

# La consigne retire au modèle la permission d'interpréter. Mesurée sur neuf
# phrases d'épreuve contre l'ancienne : 9/9 contre 8/9 avec qwen2.5:7b. Ce que
# l'ancienne ratait n'était pas anodin — « un blaireau qui joue de la trompette »
# revenait en « a toothbrush playing a trumpet ». Une espèce fausse, et le
# dessin ne correspond plus du tout à ce que le client a demandé.
SYSTEM = (
    "You are a translator. Translate the user's French t-shirt design idea into English. "
    "Rules: translate literally. Keep the exact species or object, the exact number of "
    "subjects, and the exact action. Keep the same register: a cuddle is not a kiss. "
    "Do not add, remove, interpret or embellish anything. Do not add style, colour, "
    "background, composition or art-direction words. "
    "Output only the translation, no quotes, no comments."
)


async def to_english(text: str) -> str:
    if not settings.ollama_url:
        return text
    payload = {
        "model": settings.ollama_model,
        "stream": False,
        # Décharge le modèle aussitôt pour laisser la VRAM à ComfyUI : sur une
        # carte de 12 Go, un modèle de 7 milliards resté en mémoire prendrait la
        # place de SDXL. Le prix de cette discipline est un chargement à froid à
        # chaque appel — d'où le délai large ci-dessous.
        "keep_alive": 0,
        "options": {"temperature": 0},
        "messages": [
            {"role": "system", "content": SYSTEM},
            {"role": "user", "content": text},
        ],
    }
    # Trois minutes, et non une. Le modèle est rechargé à froid à chaque appel,
    # et ce chargement peut tomber pendant que ComfyUI charge SDXL. À 60 s, il
    # dépassait le délai, l'exception était avalée, et le prompt français
    # partait tel quel vers un modèle qui ne comprend que l'anglais : le dessin
    # revenait à côté sans qu'aucune erreur ne soit levée nulle part.
    try:
        async with httpx.AsyncClient(timeout=180) as client:
            resp = await client.post(f"{settings.ollama_url.rstrip('/')}/api/chat", json=payload)
            resp.raise_for_status()
            translated = resp.json()["message"]["content"].strip().strip('"')
            return translated[:300] or text
    except Exception as exc:  # la traduction ne doit jamais bloquer la génération
        log.warning("Traduction indisponible, prompt d'origine conservé : %s", exc)
        return text
