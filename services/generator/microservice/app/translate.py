"""Traduction optionnelle FR -> EN via Ollama.

Le texte à imprimer ne passe jamais par le traducteur : ce qui est entre
guillemets est mis de côté avant et remis tel quel après. « FÊTE 2026 » était
devenu « FESTIVAL 2026 » — sur un t-shirt, c'est une faute imprimée cent fois.
"""
import logging
import re

from . import ollama
from .config import settings

log = logging.getLogger(__name__)

# Les mots qui désignent un animal et un objet (16/10/2026 : « un blaireau qui
# joue de la trompette » est revenu en « a toothbrush playing the trumpet »).
# La règle qui tranche : un sujet qui agit est l'animal.
DOUBLE_MEANINGS = (
    "Some French words name both an animal and an object: blaireau (badger or shaving brush), "
    "souris (mouse or computer mouse), grue (crane bird or construction crane), "
    "papillon (butterfly or bow tie), bourdon (bumblebee or great bell). When such a word is "
    "a subject that does something or has a face, it is the animal. "
)

# La consigne retire au modèle la permission d'interpréter. Mesurée sur neuf
# phrases d'épreuve contre l'ancienne : 9/9 contre 8/9 avec qwen2.5:7b. Ce que
# l'ancienne ratait n'était pas anodin — « un blaireau qui joue de la trompette »
# revenait en « a toothbrush playing a trumpet ». Une espèce fausse, et le
# dessin ne correspond plus du tout à ce que le client a demandé.
#
# Le 16/10/2026, la même phrase est revenue en « a toothbrush playing the
# trumpet » : la consigne ne suffisait plus. Les mots à double sens sont
# maintenant nommés, avec la règle qui tranche (un sujet qui agit est l'animal),
# et le formulaire invite le client à lever l'ambiguïté lui-même.
SYSTEM = (
    "You are a translator. Translate the user's French t-shirt design idea into English. "
    "Rules: translate literally. Keep the exact species or object, the exact number of "
    "subjects, and the exact action. Keep the same register: a cuddle is not a kiss. "
    "Do not add, remove, interpret or embellish anything. Do not add style, colour, "
    "background, composition or art-direction words. "
    "Describe the design to print, not the garment: drop words such as 't-shirt for' or "
    "'sweatshirt with'. Words written in capitals are text to print: keep them exactly "
    "as written, untranslated, in double quotes. "
    + DOUBLE_MEANINGS
    + "Output only the translation, no comments."
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


async def to_english(text: str, keep_warm: bool = False) -> str:
    """`keep_warm` quand un autre appel au modèle suit aussitôt (la réécriture
    d'une retouche) : il évite de le recharger à froid."""
    if not settings.ollama_url:
        return text
    protected, saved = protect(text)
    translated = await _translate(protected, markers=bool(saved), keep_warm=keep_warm)
    if translated == protected:
        return text
    return restore(clean_output(translated, len(saved)), saved)


# Une demande de retouche n'est pas une idée de dessin. Passée par la consigne
# ci-dessus, « mets tout le texte en grand sous le skateboard » revenait en
# majuscules entre guillemets — donc en texte à imprimer —, ou en
# « PUTSILHOMMES" "SUR" "LE"… (recette du 16/10/2026). Mesurée sur huit demandes
# avec qwen2.5:7b : huit traductions justes, tailles et places comprises.
# Les exemples à l'impératif : « passe la scène de nuit » revenait en « put the
# night scene » (recette du 17/10/2026).
INSTRUCTION_SYSTEM = (
    "You translate a French request to change an image into a clear English instruction. "
    "Write it in the imperative, in lowercase, the way a native English speaker would ask an "
    "illustrator, for example: 'make it night-time', 'add a black cat on the railing', "
    "'move the text under the skateboard', 'make the colours softer', 'redraw it in a retro "
    "style'. French verbs such as passer, mettre, rendre or faire often mean 'make' or 'turn' "
    "here: « passe la scène de nuit » is 'make the scene night-time', not 'put the night "
    "scene'. Keep the meaning exactly and keep every word about size, "
    "place, colour and number (big, small, under, above, left, right...); do not add anything. "
    "Only markers such as [[T1]] stand for text to print: keep them unchanged. Do not put "
    "anything in quotes or in capitals. "
    + DOUBLE_MEANINGS
    + "Output only the translation."
)


async def instruction_to_english(text: str, keep_warm: bool = False) -> str:
    """Une demande de retouche, en anglais. Le texte entre guillemets passe à
    côté du traducteur, comme pour une idée ; tout autre guillemet est retiré :
    il ferait passer la demande pour du texte à imprimer."""
    if not settings.ollama_url:
        return text
    protected, saved = protect(text)
    try:
        translated = await ollama.chat(
            INSTRUCTION_SYSTEM, protected,
            keep_alive=ollama.KEEP_WARM if keep_warm else ollama.UNLOAD,
        )
    except Exception as exc:  # une retouche ne doit jamais échouer sur la traduction
        log.warning("Traduction de la retouche indisponible, demande d'origine conservée : %s", exc)
        return text
    translated = clean_output(translated.replace('"', " ")[:300], len(saved))
    if not translated:
        return text
    return restore(translated, saved)


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


async def _translate(text: str, markers: bool = False, keep_warm: bool = False) -> str:
    # Déchargé aussitôt d'ordinaire, pour laisser la VRAM à ComfyUI : sur une
    # carte de 12 Go, un modèle de 7 milliards resté en mémoire prendrait la
    # place du modèle d'image.
    try:
        translated = await ollama.chat(
            SYSTEM + (MARKERS if markers else ""), text,
            keep_alive=ollama.KEEP_WARM if keep_warm else ollama.UNLOAD,
        )
        return translated.strip('"')[:300] or text
    except Exception as exc:  # la traduction ne doit jamais bloquer la génération
        # Le prompt français part alors tel quel : jobs.py le repère (sujet
        # identique à la demande) et le signale au client.
        log.warning("Traduction indisponible, prompt d'origine conservé : %s", exc)
        return text
