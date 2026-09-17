"""Transforme l'idée du client en prompt contraint pour un rendu facile à vectoriser.

Deux contraintes guident ces textes :
- chaque couleur imprimée coûte une encre, donc pas de dégradé, pas d'ombre, pas de fond ;
- chaque texture (hachures, trames, lignes de gravure) devient des centaines de formes
  dans le SVG, donc illisible à l'impression et lourd à manipuler.
"""

STYLES = {
    # Les mentions « no scenery / no landscape » évitent que SDXL livre un paysage complet
    # là où le client attend un symbole isolé.
    "logo": (
        "minimalist vector logo emblem, single centered symbol, simple bold geometric shapes, "
        "no scenery, no landscape, no horizon"
    ),
    "illustration": "flat vector illustration, bold simple shapes, single subject, no scenery",
    "mascotte": "cartoon mascot character, flat vector style, thick outlines, full body character",
    "badge": (
        "vintage badge emblem, compact circular composition, flat vector style, bold outlines, "
        "no landscape scene"
    ),
}

POSITIVE_TEMPLATE = (
    "{style}, {subject}, bold clean outlines, solid flat colors, "
    "limited palette of exactly {colors} flat colors, no gradients, no shading, no texture, "
    "centered composition, single subject only, nothing behind the subject, "
    "isolated on a pure white background (#ffffff), plain empty background, "
    "screen print t-shirt design"
)

NEGATIVE_PROMPT = (
    "photo, photorealistic, gradient, soft shadow, drop shadow, ground shadow, shading, "
    "texture, noise, grain, blur, 3d render, watercolor, sketch lines, text, letters, "
    "watermark, signature, frame, border, square frame, panel, poster layout, "
    "halftone, hatching, cross-hatching, engraving lines, line texture, stippling, "
    "dotted texture, speckles, background scenery, background pattern, background shapes, "
    "geometric shapes behind subject, diamond shape behind subject, grey background, "
    "gray background, colored background, off-white background, beige background, "
    "dark background, halo, glow, vignette, reflection, collage, multiple subjects, "
    "busy composition"
)


def build_prompts(subject: str, style: str, colors: int) -> tuple:
    style_text = STYLES.get(style, STYLES["illustration"])
    positive = POSITIVE_TEMPLATE.format(style=style_text, subject=subject, colors=colors)
    return positive, NEGATIVE_PROMPT
