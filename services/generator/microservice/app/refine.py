"""Chat de retouche : transforme une demande du client en nouvelle description d'image.

Le client écrit « enlève le skateboard, mets-le plus souriant » ; le modèle local fusionne
cette demande dans la description anglaise déjà utilisée, et le modèle repart de l'image existante.
Sans Ollama, on se rabat sur une simple concaténation : moins fin, mais jamais bloquant.

Recette du 14/10/2026 (B4) : « mets le texte en grand sous le skateboard » gardait
l'image telle quelle. Trois causes, toutes traitées ici :

- la consigne interdisait les guillemets, et le texte à imprimer (« "PIZZA CLUB" »)
  perdait ses guillemets dans la nouvelle description : il n'était plus du texte ;
- l'appel avait une minute, alors que le modèle repart à froid après la
  traduction (trois minutes ailleurs pour cette raison) : il tombait souvent dans
  le repli ;
- la retouche repartait de l'image avec un écart fixe (0,55), qui garde la mise
  en page : bien pour une couleur ou un contour, trop peu pour déplacer, agrandir,
  ajouter ou retirer un élément. La portée de la demande choisit maintenant l'écart.
"""
import json
import logging
import re
from dataclasses import dataclass

from . import ollama
from .config import settings
from .translate import protect, restore, to_english

log = logging.getLogger(__name__)

SYSTEM = (
    "You maintain a short English description of a t-shirt design for an image generator. "
    "Apply the user's change request to the current description. Keep everything the user "
    "did not ask to change. Markers such as [[T1]] stand for text printed on the design: keep "
    "each one unchanged and where the request puts it. "
    "Then say whether the change moves, resizes, adds or removes elements or text (\"layout\"), "
    "or only touches colours, lines, details or expression (\"detail\"). "
    'Answer in JSON only: {"description": "<one line, English, under 220 characters>", '
    '"scope": "layout" or "detail"}.'
)

MAX_SUBJECT = 300

# Sans modèle de langage, la portée se lit sur les mots de la demande.
LAYOUT_WORDS = re.compile(
    r"\b(ajout\w*|rajout\w*|enl[eè]v\w*|retir\w*|supprim\w*|d[ée]plac\w*|bouge\w*|mets?|place\w*|"
    r"sous|dessus|au-dessus|en dessous|à c[oô]t[ée]|gauche|droite|centr\w*|grand\w*|petit\w*|"
    r"agrandi\w*|r[ée]dui\w*|taille|texte|[ée]cri\w*|remplac\w*|"
    r"add|remove|move|put|place|under|below|above|beside|left|right|center|centre|bigger|larger|"
    r"smaller|resize|text|write|replace)\b",
    re.IGNORECASE,
)


@dataclass(frozen=True)
class Rewrite:
    subject: str
    scope: str  # "layout" ou "detail"


def guess_scope(instruction: str) -> str:
    return "layout" if LAYOUT_WORDS.search(instruction or "") else "detail"


def _fallback(subject: str, instruction: str, scope: str) -> Rewrite:
    return Rewrite(f"{subject}, {instruction}"[:MAX_SUBJECT], scope)


async def rewrite(subject: str, instruction: str) -> Rewrite:
    """La nouvelle description anglaise du design, et la portée de la demande."""
    scope = guess_scope(instruction)
    # Le modèle reste chargé entre la traduction et la réécriture qui suit.
    instruction_en = await to_english(instruction, keep_warm=True)
    if not settings.ollama_url:
        return _fallback(subject, instruction_en, scope)

    # Les textes à imprimer passent à côté du modèle, comme pour la traduction.
    protected_subject, saved = protect(subject)
    protected_instruction, saved_instruction = protect(instruction_en)
    for number in range(len(saved_instruction), 0, -1):
        protected_instruction = protected_instruction.replace(f"[[T{number}]]", f"[[T{len(saved) + number}]]")
    saved = saved + saved_instruction

    try:
        content = await ollama.chat(
            SYSTEM,
            f"Current description: {protected_subject}\nChange request: {protected_instruction}",
            temperature=0.2, json=True,
        )
        answer = json.loads(content)
        merged = str(answer.get("description", "")).strip().strip('"')
        # Un doute entre les deux penche vers la mise en page : une retouche
        # sans effet coûte une reprise au client.
        if answer.get("scope") == "layout":
            scope = "layout"
        if not merged:
            return _fallback(subject, instruction_en, scope)
        return Rewrite(restore(merged, saved)[:MAX_SUBJECT], scope)
    except Exception as exc:  # une retouche ne doit jamais échouer sur la réécriture
        log.warning("Réécriture indisponible, repli sur la concaténation : %s", exc)
        return _fallback(subject, instruction_en, scope)


async def apply_instruction(subject: str, instruction: str) -> str:
    """Seulement la nouvelle description (la portée est lue par `rewrite`)."""
    return (await rewrite(subject, instruction)).subject
