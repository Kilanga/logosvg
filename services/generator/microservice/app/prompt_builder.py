"""Transforme l'idée du client en prompt contraint par la technique d'impression.

Deux familles de contraintes, et non plus une seule :

- **Sortie vectorielle** (sérigraphie, flex, broderie) : chaque couleur imprimée coûte une
  encre, donc pas de dégradé, pas d'ombre, pas de fond ; et chaque texture (hachures,
  trames, lignes de gravure) devient des centaines de formes dans le SVG, donc illisible à
  l'impression et lourde à manipuler.
- **Sortie matricielle** (DTF, DTG, sublimation) : la machine imprime en quadrichromie,
  les dégradés et les ombres passent sans surcoût. Brider le modèle à quelques aplats
  reviendrait à jeter la moitié de ce que l'atelier sait faire. Restent les contraintes
  communes : un sujet isolé, sur fond blanc uni, détourable proprement.

Dans les deux cas le fond doit rester retirable : « isolated on a pure white background »
n'est jamais négociable.
"""
from .techniques import Technique, resolve

# Aucune négation ici, et c'est délibéré. L'encodeur de texte de SDXL n'a pas de
# notion de négation : « no scenery » lui apporte surtout le mot « scenery ».
# Ces mentions, censées interdire le décor, le demandaient. Deux séries d'essais
# l'ont montré sur le même prompt — un phare livré deux fois sur deux en paysage
# complet, avec ciel, mer, horizon et reflets, alors que le prompt disait
# « no scenery, no landscape, no horizon ». La seconde fois le fond était bleu
# nuit plutôt que blanc, et le vectoriseur en a fidèlement tiré 8 722 formes :
# un fichier inimprimable, au bout de quatre minutes d'attente.
#
# Tout ce qu'on ne veut pas est désormais dans le prompt négatif, qui est le
# seul endroit où le modèle sait le lire.
STYLES = {
    "logo": "minimalist vector logo emblem, single centered symbol, simple bold geometric shapes",
    "illustration": "flat vector illustration, bold simple shapes, single subject",
    "mascotte": "cartoon mascot character, flat vector style, thick outlines, full body character",
    "badge": "vintage badge emblem, compact circular composition, flat vector style, bold outlines",
}

# Styles réécrits pour les techniques qui savent rendre le détail et les dégradés.
RICH_STYLES = {
    "logo": "polished logo emblem, single centered symbol, clean shapes",
    "illustration": "detailed illustration, single subject",
    "mascotte": "cartoon mascot character, expressive full body character, clean outlines",
    "badge": "vintage badge emblem, compact circular composition, clean outlines",
}

FLAT_TEMPLATE = (
    "{style}, {subject}, {technique}, bold clean outlines, solid flat colors, "
    "limited palette of exactly {colors} flat colors, "
    "centered composition, single subject only, "
    "isolated on a pure white background (#ffffff), plain empty white background, "
    "screen print t-shirt design"
)

RICH_TEMPLATE = (
    "{style}, {subject}, {technique}, clean outlines, rich colors, "
    "centered composition, single subject only, "
    "isolated on a pure white background (#ffffff), plain empty white background, "
    "t-shirt print design"
)

# Ce que personne ne veut, quelle que soit la machine : du texte, un cadre, un décor,
# plusieurs sujets, un fond qui ne se détourera pas.
COMMON_NEGATIVE = (
    "photo, photorealistic, 3d render, blur, text, letters, "
    "watermark, signature, frame, border, square frame, panel, poster layout, "
    # Ce que les négations du prompt positif prétendaient interdire, à leur
    # véritable place. « landscape scene » et « horizon » manquaient ici : le
    # phare les a livrés deux fois.
    "scenery, landscape, landscape scene, horizon, sky, clouds, sea, water, "
    "ground, floor, terrain, buildings behind subject, "
    "background scenery, background pattern, background shapes, "
    "geometric shapes behind subject, diamond shape behind subject, grey background, "
    "gray background, colored background, off-white background, beige background, "
    "dark background, halo, glow, vignette, reflection, collage, multiple subjects, "
    "busy composition"
)

# Ce qui coûte une encre ou des centaines de chemins : réservé aux sorties vectorielles.
FLAT_NEGATIVE = (
    "gradient, soft shadow, drop shadow, ground shadow, shading, "
    "texture, noise, grain, watercolor, sketch lines, "
    "halftone, hatching, cross-hatching, engraving lines, line texture, stippling, "
    "dotted texture, speckles"
)

# Conservé pour compatibilité avec l'ancien appel : c'est le négatif de la sérigraphie.
NEGATIVE_PROMPT = f"{FLAT_NEGATIVE}, {COMMON_NEGATIVE}"


def _join(*parts: str) -> str:
    return ", ".join(p for p in parts if p)


def build_prompts(subject: str, style: str, colors: int, technique: str = None) -> tuple:
    """Construit le couple (positif, négatif) pour un sujet et une technique donnés."""
    profile: Technique = resolve(technique)

    if profile.gradients:
        style_text = RICH_STYLES.get(style, RICH_STYLES["illustration"])
        positive = RICH_TEMPLATE.format(
            style=style_text, subject=subject, technique=profile.prompt_hint
        )
        negative = _join(profile.negative_hint, COMMON_NEGATIVE)
    else:
        style_text = STYLES.get(style, STYLES["illustration"])
        positive = FLAT_TEMPLATE.format(
            style=style_text,
            subject=subject,
            technique=profile.prompt_hint,
            colors=profile.clamp_colors(colors),
        )
        negative = _join(profile.negative_hint, FLAT_NEGATIVE, COMMON_NEGATIVE)

    return positive, negative
