"""Relit le texte d'un dessin, pour relancer quand le modèle l'a mal écrit.

FLUX.2 [klein] écrit le texte demandé juste deux fois sur trois environ :
« PIZZA CLUB » revenait en « PIZZLA CLUB », « CLLLUB »… (recettes du 14 et
du 16/10/2026). Le prompt n'y peut plus grand-chose ; la seule garantie est
de relire l'image et de redessiner, avec un autre tirage, quand le texte n'y
est pas. Décidé le 17/10/2026 : jusqu'à deux nouveaux essais, et le meilleur
des dessins est gardé si aucun n'est exact.

La lecture passe par RapidOCR (modèles ONNX livrés avec le paquet, rien à
télécharger, quelques dixièmes de seconde sur le processeur). Le paquet est
facultatif : absent, aucune relecture n'est faite et le dessin part tel quel,
comme avant.
"""
from __future__ import annotations

import io
import logging
import re
from dataclasses import dataclass
from difflib import SequenceMatcher
from typing import Optional

from PIL import Image

log = logging.getLogger(__name__)

QUOTED = re.compile(r'"([^"]+)"')

_engine = None
_unavailable = False


@dataclass(frozen=True)
class Reading:
    """Ce que la relecture a trouvé : exact, ou à quel point c'est proche (0 à 1)."""

    exact: bool
    score: float
    seen: str


def expected_texts(subject: str) -> list:
    """Les textes à imprimer, tels que le client les a mis entre guillemets."""
    return [t.strip() for t in QUOTED.findall(subject or "") if t.strip()]


def normalize(text: str) -> str:
    """Majuscules, lettres et chiffres seulement : la casse, les espaces et la
    ponctuation ne sont pas ce que le modèle rate."""
    return re.sub(r"[^0-9A-Z]", "", text.upper().translate(_ACCENTS))


_ACCENTS = str.maketrans("ÀÂÄÁÃÇÉÈÊËÍÌÎÏÑÓÒÔÖÕÚÙÛÜÝŸ", "AAAAACEEEEIIIINOOOOOUUUUYY")


def _get_engine():
    global _engine, _unavailable
    if _engine is not None or _unavailable:
        return _engine
    try:
        from rapidocr_onnxruntime import RapidOCR  # paquet facultatif
    except ImportError:
        _unavailable = True
        log.info("RapidOCR absent : le texte des dessins n'est pas relu.")
        return None
    _engine = RapidOCR()
    return _engine


def available() -> bool:
    return _get_engine() is not None


def read(png: bytes) -> Optional[list]:
    """Les lignes de texte lues dans l'image, ou None si la relecture est indisponible."""
    engine = _get_engine()
    if engine is None:
        return None
    import numpy as np  # livré avec RapidOCR

    with Image.open(io.BytesIO(png)) as img:
        pixels = np.array(img.convert("RGB"))
    try:
        result, _ = engine(pixels)
    except Exception as exc:  # une relecture ratée ne doit jamais bloquer un dessin
        log.warning("Relecture du texte impossible : %s", exc)
        return None
    return [line[1] for line in (result or [])]


def judge(lines: list, texts: list) -> Reading:
    """Compare ce qui est lu à ce qui est attendu. Exact si chaque texte attendu
    se retrouve, une fois normalisé, dans ce qui est lu ; sinon un score de
    ressemblance, pour garder le meilleur des essais."""
    seen = " ".join(lines)
    everything = normalize(seen)
    scores = []
    for text in texts:
        wanted = normalize(text)
        if not wanted:
            continue
        if wanted in everything:
            scores.append(1.0)
            continue
        # Le meilleur passage de même longueur que le texte attendu.
        best = 0.0
        width = len(wanted)
        for start in range(max(len(everything) - width, 0) + 1):
            best = max(best, SequenceMatcher(None, wanted, everything[start:start + width + 1]).ratio())
        scores.append(best)
    if not scores:
        return Reading(exact=True, score=1.0, seen=seen)
    return Reading(exact=all(s == 1.0 for s in scores), score=sum(scores) / len(scores), seen=seen)


def check(png: bytes, texts: list) -> Optional[Reading]:
    """La relecture d'un dessin, ou None quand il n'y a rien à relire ou pas de quoi relire."""
    if not texts:
        return None
    lines = read(png)
    if lines is None:
        return None
    return judge(lines, texts)
