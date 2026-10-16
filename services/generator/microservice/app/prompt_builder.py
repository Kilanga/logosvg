"""Transforme l'idée du client en un prompt pour FLUX.2 [klein], borné par la technique.

FLUX.2 lit le prompt avec un modèle de langage (Qwen3), pas avec CLIP : il comprend
les phrases, les négations et les guillemets. Le prompt est donc écrit comme une
consigne, en un seul texte — il n'y a plus de prompt négatif, que la version
distillée ignore de toute façon.

Trois choses y sont dites à chaque fois, parce que leur oubli a été constaté :

- **le dessin seul**, pas le vêtement : « t-shirt pour la fête du village » faisait
  dessiner un t-shirt, qui se serait retrouvé imprimé sur le t-shirt ;
- **un fond blanc uni**, condition du détourage et de la vectorisation : sujet
  isolé en vectoriel ; en matriciel, une scène est permise dans une vignette
  nette (voir `Technique.composition`) ;
- **le texte entre guillemets, à la lettre** : « FÊTE 2026 » était devenu
  « FESTIVAL 2026 ».

Deux familles de contraintes, selon la technique : aplats comptés en encres pour la
sortie vectorielle (sérigraphie, flex, broderie), couleurs libres pour la sortie
matricielle (DTF, DTG, sublimation).
"""
import re

from .techniques import Technique, resolve

STYLES = {
    "logo": "A minimalist logo emblem built around one centered symbol with simple bold geometric shapes",
    "illustration": "A flat illustration with bold simple shapes and a single subject",
    "mascotte": "A full-body cartoon mascot character with thick outlines",
    "badge": "A compact circular badge emblem with bold outlines",
}

RICH_STYLES = {
    "logo": "A polished logo emblem built around one centered symbol",
    "illustration": "A detailed illustration of the subject or scene described",
    "mascotte": "An expressive full-body cartoon mascot character with clean outlines",
    "badge": "A compact circular badge emblem with clean outlines",
}

# Les trois propositions d'une même demande : la première telle que demandée, les
# deux autres dans un registre voisin, pour que le choix serve à quelque chose.
FLAVOURS = {
    "vector": ("", "Retro vintage screen print look.", "Bold modern graphic look with thick outlines."),
    "raster": ("", "Vintage illustration look.", "Vibrant modern illustration look."),
}

# Quand le client a lui-même nommé un style, les registres voisins ne doivent pas
# le remplacer : « style aquarelle » revenait en « Vintage illustration look »
# sur la deuxième proposition (recette du 14/10/2026). Les propositions varient
# alors la composition, plus le rendu.
CLIENT_STYLE = re.compile(
    r"\b(watercolou?r|vintage|retro|cartoon|manga|anime|kawaii|comic|pixel|8-bit|realistic|"
    r"photo(?:-?realistic)?|sketch|pencil|charcoal|ink drawing|line art|lineart|minimalist|"
    r"art deco|art nouveau|pop art|graffiti|neon|low poly|3d|psychedelic|grunge|tattoo|"
    r"stencil|woodcut|engraving|ukiyo-e|pastel|oil painting|painted|chalk|doodle|style)\b",
    re.IGNORECASE,
)
STYLE_KEPT_FLAVOURS = ("", "A different composition of the same idea, same style.",
                       "A bolder take of the same idea, same style, stronger contrast.")

# Le texte à imprimer, dit à part et tôt dans le prompt : le modèle soigne
# davantage ce qu'on lui nomme explicitement (« PIZZA CLUB » revenait en
# « PIZZLA CLUB », « PIZZA CUB »… à la recette du 14/10/2026).
QUOTED = re.compile(r'"([^"]+)"')

ARTWORK_ONLY = (
    "Only the artwork itself, as a print-ready graphic for a t-shirt: do not draw the "
    "t-shirt, a model, a mockup, a poster or a frame."
)
NO_TEXT = "Do not write any text, letters or numbers."


def text_rule(subject: str) -> str:
    """La consigne de texte : le texte exact s'il y en a, aucun sinon."""
    texts = [t.strip() for t in QUOTED.findall(subject) if t.strip()]
    if not texts:
        return NO_TEXT
    quoted = " and ".join(f'"{t}"' for t in texts)
    letters = sum(len(t.replace(" ", "")) for t in texts)
    return (
        f"The only text in the design is {quoted}, spelled exactly like that "
        f"({letters} characters, same order, no character added, dropped or changed), "
        "in large, bold, clean sans-serif capital letters that are easy to read, "
        "clearly separated from the drawing. No other text anywhere."
    )


def flavour_count() -> int:
    return len(FLAVOURS["vector"])


def build_prompt(subject: str, style: str, colors: int, technique: str = None, flavour: int = 0) -> str:
    """Le prompt complet d'un dessin. `flavour` choisit le registre (0, 1 ou 2)."""
    profile: Technique = resolve(technique)
    flavours = STYLE_KEPT_FLAVOURS if CLIENT_STYLE.search(QUOTED.sub("", subject)) else FLAVOURS[profile.family]
    look = flavours[flavour % len(flavours)]

    if profile.gradients:
        opening = RICH_STYLES.get(style, RICH_STYLES["illustration"])
        palette = ""
    else:
        opening = STYLES.get(style, STYLES["illustration"])
        palette = f"Use exactly {profile.clamp_colors(colors)} flat colors, plus the white of the background."

    parts = [f"{opening}: {subject}.", text_rule(subject), look, profile.prompt_hint, palette,
             profile.composition, ARTWORK_ONLY]
    return " ".join(p for p in parts if p)


def edit_prompt(instruction: str, prompt: str) -> str:
    """Le prompt d'une édition : la demande d'abord, puis le dessin attendu.

    Un modèle d'édition lit une consigne (« move the text below the board »)
    mieux qu'il ne devine l'écart entre deux descriptions ; la description
    complète suit, avec sa règle de texte, pour que le reste ne bouge pas.
    """
    instruction = (instruction or "").strip().rstrip(".")
    if not instruction:
        return prompt
    return (
        f"Edit the reference image: {instruction}. Keep the same character, colors and style; "
        f"change only what is asked. The result: {prompt}"
    )


def image_edit_prompt(instruction: str, prompt: str) -> str:
    """Le prompt d'une création qui part de l'image du client.

    Contrairement à une retouche, le style change presque toujours (une photo,
    une peinture, un croquis deviennent un dessin imprimable) : on garde le
    sujet et la composition, pas les couleurs ni le rendu.
    """
    instruction = (instruction or "").strip().rstrip(".")
    if not instruction:
        return prompt
    return (
        f"Use the reference image as the base and change it: {instruction}. "
        f"Keep its subject and composition except for what is asked, and redraw it "
        f"in the style described here. The result: {prompt}"
    )
