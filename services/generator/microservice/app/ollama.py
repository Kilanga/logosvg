"""Le seul endroit qui parle à Ollama (modération, traduction, retouche).

Trois appels recopiés jusqu'au 16/10/2026, chacun avec son délai et sa façon
de libérer la carte : ils passent tous par ici. Les erreurs remontent telles
quelles ; chaque appelant décide de son repli (accepter la demande, garder le
français, concaténer la retouche), parce qu'aucun ne doit bloquer une
génération.
"""
import httpx

from .config import settings

# Un modèle de 7 milliards déchargé repart à froid : jusqu'à plusieurs dizaines
# de secondes, davantage si ComfyUI charge le sien au même moment. À 60 s, la
# traduction tombait dans son repli sans bruit.
TIMEOUT_SECONDS = 180

# Rendre la carte tout de suite, ou garder le modèle quelques secondes quand un
# autre appel suit immédiatement (modération puis traduction, traduction puis
# réécriture d'une retouche).
UNLOAD = 0
KEEP_WARM = "20s"


async def chat(system: str, user: str, *, temperature: float = 0, json: bool = False,
               keep_alive=UNLOAD) -> str:
    """Le texte de la réponse, débarrassé des espaces autour."""
    payload = {
        "model": settings.ollama_model,
        "stream": False,
        "keep_alive": keep_alive,
        "options": {"temperature": temperature},
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": user},
        ],
    }
    if json:
        payload["format"] = "json"

    async with httpx.AsyncClient(timeout=TIMEOUT_SECONDS) as client:
        resp = await client.post(f"{settings.ollama_url.rstrip('/')}/api/chat", json=payload)
        resp.raise_for_status()
        return resp.json()["message"]["content"].strip()
