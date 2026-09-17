"""Préparation de l'image (réduction de couleurs, fond) puis conversion en SVG avec vtracer."""
import io
from collections import Counter

import vtracer
from PIL import Image, ImageDraw, ImageFilter

TRANSPARENT = (0, 0, 0, 0)


def _is_light(pixel) -> bool:
    r, g, b = pixel[:3]
    return (0.299 * r + 0.587 * g + 0.114 * b) > 200


def prepare_image(png_bytes: bytes, colors: int, remove_background: bool) -> Image.Image:
    img = Image.open(io.BytesIO(png_bytes)).convert("RGB")
    # Lisse le bruit de génération qui créerait des centaines de micro-formes.
    img = img.filter(ImageFilter.MedianFilter(5))
    # Une couleur de plus pour le fond blanc s'il doit être retiré.
    target = colors + (1 if remove_background else 0)
    quantized = img.quantize(colors=target, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    rgba = quantized.convert("RGBA")

    if remove_background:
        w, h = rgba.size
        seeds = [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1),
                 (w // 2, 0), (w // 2, h - 1), (0, h // 2), (w - 1, h // 2)]
        for xy in seeds:
            pixel = rgba.getpixel(xy)
            # Remplissage depuis les bords : le blanc à l'intérieur du dessin est conservé.
            if pixel[3] and _is_light(pixel):
                ImageDraw.floodfill(rgba, xy, TRANSPARENT, thresh=0)
    return rgba


def extract_palette(img: Image.Image, min_share: float = 0.005) -> list:
    counts = Counter()
    for n, pixel in img.getcolors(img.width * img.height) or []:
        if pixel[3] > 0:
            counts[pixel[:3]] += n
    total = sum(counts.values()) or 1
    palette = []
    for (r, g, b), n in counts.most_common():
        share = n / total
        if share >= min_share:
            palette.append({"hex": f"#{r:02x}{g:02x}{b:02x}", "share": round(share, 3)})
    return palette


def to_svg(img: Image.Image) -> str:
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return vtracer.convert_raw_image_to_svg(
        buf.getvalue(),
        img_format="png",
        colormode="color",
        # "cutout" : formes juxtaposées sans superposition, adapté à la sérigraphie.
        hierarchical="cutout",
        mode="spline",
        filter_speckle=8,
        color_precision=6,
        layer_difference=16,
        corner_threshold=60,
        length_threshold=4.0,
        max_iterations=10,
        splice_threshold=45,
        path_precision=3,
    )


def vectorize(png_bytes: bytes, colors: int, remove_background: bool, max_paths_warning: int) -> dict:
    prepared = prepare_image(png_bytes, colors, remove_background)
    svg = to_svg(prepared)
    palette = extract_palette(prepared)
    paths = svg.count("<path")

    warnings = []
    if paths > max_paths_warning:
        warnings.append(
            f"Le design contient {paths} formes : il risque d'être difficile à imprimer. "
            "Essayez un style plus simple ou moins de couleurs."
        )
    if paths == 0:
        warnings.append("Aucune forme détectée. Le design est peut-être trop clair : désactivez le retrait du fond.")

    return {
        "svg": svg,
        "palette": palette,
        "inks": len(palette),
        "stats": {"paths": paths, "svg_bytes": len(svg.encode("utf-8"))},
        "warnings": warnings,
    }
