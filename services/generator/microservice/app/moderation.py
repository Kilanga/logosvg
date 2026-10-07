"""Relecture d'une demande par le modèle de langue, avant toute génération.

La liste de mots (`prompt_filter`) arrête ce qu'elle connaît, et rien d'autre :
« le petit sorcier à lunettes et sa cicatrice » passe, « une souris aux grandes
oreilles rondes, culotte rouge » aussi. Le modèle, lui, reconnaît ce qu'une
demande désigne sans le nommer. Il ne remplace pas la liste — elle reste le
premier filtre, instantané et prévisible —, il la complète.

Ce qu'il renvoie n'est jamais montré tel quel : il choisit une catégorie, et
c'est le service qui écrit la phrase lue par le client. Un modèle qui
rédigerait lui-même le refus pourrait dire n'importe quoi, dans n'importe
quelle langue.

Il ne bloque jamais par panne : Ollama éteint, réponse illisible, délai
dépassé, la demande passe — la liste de mots a déjà fait son travail, et une
plateforme qui refuse tout dès que son modérateur tousse ne sert à personne.
"""
import json
import logging
from typing import Optional

import httpx

from .config import settings

log = logging.getLogger(__name__)

# Les raisons de refus, et la phrase que le client lit pour chacune.
REFUSALS = {
    "brand": "Cette demande reprend une marque, un logo ou un club existant. "
             "Un atelier ne peut pas l'imprimer sans l'accord de son propriétaire : "
             "décrivez votre propre idée.",
    "character": "Cette demande reprend un personnage ou une œuvre protégés "
                 "(film, dessin animé, manga, jeu vidéo…). Inventez votre propre personnage.",
    "person": "Cette demande représente une personne réelle identifiable. "
              "Son image lui appartient : choisissez un personnage imaginaire.",
    "sexual": "Cette demande a un caractère sexuel ou dénudé, que la plateforme n'imprime pas.",
    "hate": "Cette demande contient un symbole ou un message haineux, discriminatoire "
            "ou extrémiste, que la plateforme n'imprime pas.",
    "violence": "Cette demande montre une violence crue ou appelle à la violence, "
                "ce que la plateforme n'imprime pas.",
    "drugs": "Cette demande fait la promotion de drogues illégales, ce que la plateforme n'imprime pas.",
}

SYSTEM = (
    "You review design requests for a French t-shirt printing service before an image is drawn. "
    "The request may be in French. Decide whether a print shop could legally and decently print it.\n"
    "First ask yourself what existing thing the request depicts. Customers often describe a famous "
    "character, logo or person without naming it, by its well-known features (a boy wizard with "
    "round glasses and a lightning scar, a mouse with big round ears, red shorts and white gloves, "
    "the swoosh of a sports brand). Treat such a description exactly as if the name were written.\n"
    "Refuse, with one category, when the request:\n"
    "- brand: names or describes an existing brand, logo, company, sports club or team;\n"
    "- character: names or unmistakably describes a copyrighted character or work "
    "(Disney, Pixar, Marvel, DC, manga, anime, video games, films, TV series, comics, books);\n"
    "- person: depicts a real, identifiable person (celebrity, politician, athlete, influencer);\n"
    "- sexual: is sexual, nude or erotic;\n"
    "- hate: contains hateful, racist, discriminatory or extremist symbols or messages;\n"
    "- violence: shows graphic gore or calls for violence against people;\n"
    "- drugs: promotes illegal drugs.\n"
    "Allow everything else, including: animals, original characters, skulls, monsters, horror "
    "or fantasy themes, weapons drawn in a stylised way, humour, sport in general, music, "
    "alcohol, generic objects. Text to print (often in quotes or capitals) is allowed, first "
    "names included, unless it is a brand or slogan of a brand, hateful, or targets a real person: "
    "a first name written as text is not a character.\n"
    'Answer with JSON only, in this order: {"depicts": "<the existing brand, character, work or '
    'person it depicts, or none>", "allowed": true or false, "category": "none" or one of brand, '
    'character, person, sexual, hate, violence, drugs}.'
)


async def review(text: str, context: str = "") -> Optional[str]:
    """La phrase de refus à montrer au client, ou None si la demande passe."""
    if not (settings.moderation and settings.ollama_url):
        return None

    request = f"Current design: {context}\nRequested change: {text}" if context else text
    verdict = await _ask(request)
    if verdict is None or verdict.get("allowed", True) is not False:
        return None

    category = str(verdict.get("category", "")).strip().lower()
    if category not in REFUSALS:
        # Un refus sans raison connue ne vaut pas un refus : le modèle hésite,
        # la liste de mots a déjà fait son travail.
        log.warning("Modération : refus sans catégorie reconnue (%r), demande acceptée", category)
        return None
    log.info("Modération : demande refusée (%s)", category)
    return REFUSALS[category]


async def _ask(request: str) -> Optional[dict]:
    payload = {
        "model": settings.ollama_model,
        "stream": False,
        "format": "json",
        # Gardé chargé quelques secondes : la traduction suit immédiatement et
        # reprend le même modèle, au lieu de le recharger à froid. Elle, le
        # décharge (keep_alive 0) pour rendre la VRAM à ComfyUI.
        "keep_alive": "20s",
        "options": {"temperature": 0},
        "messages": [
            {"role": "system", "content": SYSTEM},
            {"role": "user", "content": request},
        ],
    }
    try:
        async with httpx.AsyncClient(timeout=180) as client:
            resp = await client.post(f"{settings.ollama_url.rstrip('/')}/api/chat", json=payload)
            resp.raise_for_status()
            return json.loads(resp.json()["message"]["content"])
    except Exception as exc:  # la modération ne doit jamais bloquer par panne
        log.warning("Modération indisponible, demande acceptée : %s", exc)
        return None
