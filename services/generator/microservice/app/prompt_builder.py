"""Transforme l'idée du client en prompt contraint pour un rendu facile à vectoriser."""

STYLES = {
    "logo": "minimalist vector logo emblem, simple geometric shapes",
    "illustration": "flat vector illustration, bold simple shapes",
    "mascotte": "cartoon mascot character, flat vector style, thick outlines",
    "badge": "vintage badge emblem, flat vector style, bold outlines",
}

POSITIVE_TEMPLATE = (
    "{style}, {subject}, bold clean outlines, solid flat colors, "
    "limited palette of {colors} colors, no gradients, no shading, no texture, "
    "centered composition, isolated on plain white background, screen print t-shirt design"
)

NEGATIVE_PROMPT = (
    "photo, photorealistic, gradient, soft shadow, shading, texture, noise, grain, "
    "blur, 3d render, watercolor, sketch lines, text, letters, watermark, signature, "
    "frame, background scenery"
)


def build_prompts(subject: str, style: str, colors: int) -> tuple:
    style_text = STYLES.get(style, STYLES["illustration"])
    positive = POSITIVE_TEMPLATE.format(style=style_text, subject=subject, colors=colors)
    return positive, NEGATIVE_PROMPT
