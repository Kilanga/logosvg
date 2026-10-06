"""Transforme l'idée du client en un prompt pour FLUX.2 [klein], borné par la technique.

FLUX.2 lit le prompt avec un modèle de langage (Qwen3), pas avec CLIP : il comprend
les phrases, les négations et les guillemets. Le prompt est donc écrit comme une
consigne, en un seul texte — il n'y a plus de prompt négatif, que la version
distillée ignore de toute façon.

Trois choses y sont dites à chaque fois, parce que leur oubli a été constaté :

- **le dessin seul**, pas le vêtement : « t-shirt pour la fête du village » faisait
  dessiner un t-shirt, qui se serait retrouvé imprimé sur le t-shirt ;
- **un sujet isolé sur fond blanc uni**, condition du détourage et de la
  vectorisation ;
- **le texte entre guillemets, à la lettre** : « FÊTE 2026 » était devenu
  « FESTIVAL 2026 ».

Deux familles de contraintes, selon la technique : aplats comptés en encres pour la
sortie vectorielle (sérigraphie, flex, broderie), couleurs libres pour la sortie
matricielle (DTF, DTG, sublimation).
"""
from .techniques import Technique, resolve

STYLES = {
    "logo": "A minimalist logo emblem built around one centered symbol with simple bold geometric shapes",
    "illustration": "A flat illustration with bold simple shapes and a single subject",
    "mascotte": "A full-body cartoon mascot character with thick outlines",
    "badge": "A compact circular badge emblem with bold outlines",
}

RICH_STYLES = {
    "logo": "A polished logo emblem built around one centered symbol",
    "illustration": "A detailed illustration of a single subject",
    "mascotte": "An expressive full-body cartoon mascot character with clean outlines",
    "badge": "A compact circular badge emblem with clean outlines",
}

# Les trois propositions d'une même demande : la première telle que demandée, les
# deux autres dans un registre voisin, pour que le choix serve à quelque chose.
FLAVOURS = {
    "vector": ("", "Retro vintage screen print look.", "Bold modern graphic look with thick outlines."),
    "raster": ("", "Vintage illustration look.", "Vibrant modern illustration look."),
}

ARTWORK_ONLY = (
    "Only the artwork itself, as a print-ready graphic for a t-shirt: do not draw the "
    "t-shirt, a model, a mockup, a poster or a frame."
)
ISOLATED = (
    "One single subject, centered, isolated on a plain pure white background, "
    "with no scenery, no landscape and no background shapes."
)
TEXT_RULE = (
    "If the subject contains text in quotation marks, write that text exactly as given, "
    "letter for letter; otherwise add no text at all."
)


def flavour_count() -> int:
    return len(FLAVOURS["vector"])


def build_prompt(subject: str, style: str, colors: int, technique: str = None, flavour: int = 0) -> str:
    """Le prompt complet d'un dessin. `flavour` choisit le registre (0, 1 ou 2)."""
    profile: Technique = resolve(technique)
    flavours = FLAVOURS[profile.family]
    look = flavours[flavour % len(flavours)]

    if profile.gradients:
        opening = RICH_STYLES.get(style, RICH_STYLES["illustration"])
        palette = ""
    else:
        opening = STYLES.get(style, STYLES["illustration"])
        palette = f"Use exactly {profile.clamp_colors(colors)} flat colors, plus the white of the background."

    parts = [f"{opening}: {subject}.", look, profile.prompt_hint, palette, ISOLATED, ARTWORK_ONLY, TEXT_RULE]
    return " ".join(p for p in parts if p)
