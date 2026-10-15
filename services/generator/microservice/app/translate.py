"""Traduction optionnelle FR -> EN via Ollama.

Le texte à imprimer ne passe jamais par le traducteur : ce qui est entre
guillemets est mis de côté avant et remis tel quel après. « FÊTE 2026 » était
devenu « FESTIVAL 2026 » — sur un t-shirt, c'est une faute imprimée cent fois.
"""
import logging
import re

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
    "Describe the design to print, not the garment: drop words such as 't-shirt for' or "
    "'sweatshirt with'. Words written in capitals are text to print: keep them exactly "
    "as written, untranslated, in double quotes. "
    "Output only the translation, no comments."
)

# Dit seulement quand il y a des repères. Écrit à chaque fois, la consigne
# donnait au modèle un exemple à recopier : « style aquarelle », sans aucun
# guillemet, revenait en « watercolor style "T1 » (recette du 14/10/2026), et ce
# guillemet ouvert déclenchait ensuite la règle du texte à imprimer.
MARKERS = " Keep every marker such as [[T1]] exactly where it is, unchanged."

# Ce qui ressemble à un repère sans en être un : un [[T3]] inventé, un « "T1 »
# tronqué, un « [T1] » à moitié recopié.
STRAY_MARKER = re.compile(r'\[{1,2}\s*T\d+\s*\]{0,2}|"\s*T\d+\b\.?|\bT\d+\]{1,2}')

# Ce qui est entre guillemets — français, droits ou typographiques — est du texte à
# imprimer, et ne se traduit pas.
QUOTED = re.compile(r"«\s*([^»]+?)\s*»|\"([^\"]+)\"|“([^”]+)”")


def protect(text: str) -> tuple:
    """Remplace chaque texte entre guillemets par un repère [[T1]], [[T2]]…"""
    saved = []

    def keep(match):
        saved.append(next(g for g in match.groups() if g))
        return f"[[T{len(saved)}]]"

    return QUOTED.sub(keep, text), saved


def restore(text: str, saved: list) -> str:
    """Remet les textes à la lettre, entre guillemets droits. Un repère que le
    traducteur aurait perdu n'emporte pas le texte : il est ajouté à la fin."""
    for number, original in enumerate(saved, start=1):
        marker = f"[[T{number}]]"
        if marker in text:
            text = text.replace(marker, f'"{original}"')
        else:
            text = f'{text}, with the text "{original}"'
    return text


async def to_english(text: str) -> str:
    if not settings.ollama_url:
        return text
    protected, saved = protect(text)
    translated = await _translate(protected, markers=bool(saved))
    if translated == protected:
        return text
    return restore(clean_output(translated, len(saved)), saved)


def clean_output(text: str, markers: int) -> str:
    """Retire ce que le traducteur a ajouté et qui n'est pas une traduction :
    des repères qu'on ne lui a pas donnés, et un guillemet resté ouvert — qui,
    dans le prompt, ferait passer la suite pour du texte à imprimer."""
    def keep_real(match):
        found = re.search(r"\d+", match.group(0))
        number = int(found.group(0)) if found else 0
        real = match.group(0).startswith("[[") and match.group(0).rstrip().endswith("]]")
        return match.group(0) if real and 1 <= number <= markers else ""

    text = STRAY_MARKER.sub(keep_real, text)
    if text.count('"') % 2 == 1:
        last = text.rfind('"')
        text = text[:last] + text[last + 1:]
    return re.sub(r"\s{2,}", " ", text).strip(" ,;")


async def _translate(text: str, markers: bool = False) -> str:
    payload = {
        "model": settings.ollama_model,
        "stream": False,
        # Décharge le modèle aussitôt pour laisser la VRAM à ComfyUI : sur une
        # carte de 12 Go, un modèle de 7 milliards resté en mémoire prendrait la
        # place du modèle d'image. Le prix de cette discipline est un chargement
        # à froid à chaque appel — d'où le délai large ci-dessous.
        "keep_alive": 0,
        "options": {"temperature": 0},
        "messages": [
            {"role": "system", "content": SYSTEM + (MARKERS if markers else "")},
            {"role": "user", "content": text},
        ],
    }
    # Trois minutes, et non une. Le modèle est rechargé à froid à chaque appel,
    # et ce chargement peut tomber pendant que ComfyUI charge son modèle. À 60 s, il
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
