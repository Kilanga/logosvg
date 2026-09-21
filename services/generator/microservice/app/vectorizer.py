"""Préparation de l'image (aplatissement, réduction de couleurs, fond) puis conversion en SVG.

Ordre des opérations, et pourquoi :

1. lissage médian — supprime le bruit de génération qui deviendrait des micro-formes ;
2. aplatissement des quasi-blancs — SDXL rend un fond « blanc » légèrement teinté et
   dégradé ; sans ça la quantification le coupe en deux teintes voisines et la moitié du
   fond survit au retrait ;
3. quantification à (couleurs + 1) par couverture de l'espace des couleurs, puis recalage
   de chaque teinte sur la couleur réelle la plus fréquente de son groupe — sans ce recalage
   un renard orange ressort olive (moyenne du groupe) ou une gravure noir et blanc se
   retrouve avec du vert et du mauve (couleurs inventées par la couverture) ;
4. fusion des teintes trop proches — deux gris à deux points d'écart sont la même encre à
   l'œil, mais deux calques pour le vectoriseur, donc des centaines de formes inutiles ;
5. retrait du fond depuis les bords — la couleur qui occupe le pourtour, blanche ou non ;
6. les zones blanches restantes deviennent du papier (non imprimé) : imprimer du blanc sur
   un textile clair ne sert à rien, et ça rend une encre au dessin. Le client qui veut du
   blanc imprimé décoche le retrait du fond ;
7. respect du nombre d'encres demandé — chaque couleur en trop rejoint la plus proche.
"""
import io
import re
from collections import Counter

import vtracer
from PIL import Image, ImageDraw, ImageFilter

from .techniques import resolve

TRANSPARENT = (0, 0, 0, 0)
WHITE = (255, 255, 255)
# Nombre de points de départ du remplissage par bord de l'image.
SEEDS_PER_EDGE = 9
# Part du pourtour que la couleur dominante doit occuper pour être considérée comme un fond.
BORDER_SHARE_MIN = 0.45
# Deux couleurs plus proches que cette distance RGB sont la même encre.
COLOR_TOLERANCE = 28
# Luminance au-delà de laquelle un pixel peu saturé est ramené au blanc pur.
NEAR_WHITE_LUMA = 232
NEAR_WHITE_SPREAD = 18
# Quota large, utilisé quand on ne veut fusionner que les teintes voisines.
NO_LIMIT = 64
# Part minimale du dessin pour qu'une teinte mérite sa propre encre.
MIN_INK_SHARE = 0.004


def _pixels(img: Image.Image):
    """Lit les pixels en supportant Pillow 10 a 14 (getdata est deprecie depuis Pillow 12)."""
    flattened = getattr(img, "get_flattened_data", None)
    return flattened() if flattened else img.getdata()


def _luma(r: int, g: int, b: int) -> float:
    return 0.299 * r + 0.587 * g + 0.114 * b


def _is_light(pixel) -> bool:
    return _luma(*pixel[:3]) > 200


def flatten_near_white(img: Image.Image) -> None:
    """Ramène au blanc pur les pixels presque blancs et peu colorés (fond « blanc » de SDXL)."""
    img.putdata([
        WHITE if (_luma(r, g, b) >= NEAR_WHITE_LUMA and max(r, g, b) - min(r, g, b) <= NEAR_WHITE_SPREAD)
        else (r, g, b)
        for r, g, b in _pixels(img)
    ])


def snap_palette_to_modes(rgb: Image.Image, quantized: Image.Image) -> Image.Image:
    """Chaque entrée de palette prend la couleur réelle la plus fréquente de son groupe.

    La quantification par couverture choisit des teintes qui balaient l'espace des couleurs,
    quitte à en inventer : sur une gravure en noir et blanc, elle réserve un emplacement au
    vert, et tous les gris moyens s'y retrouvent. Le recalage remplace chaque teinte par la
    couleur que portaient réellement la majorité de ses pixels.
    """
    small_index = quantized.resize((256, 256), Image.NEAREST)
    small_color = rgb.resize((256, 256), Image.NEAREST)
    groups: dict = {}
    for index, color in zip(_pixels(small_index), _pixels(small_color)):
        groups.setdefault(index, Counter())[color] += 1
    palette = list(quantized.getpalette() or [])
    for index, counter in groups.items():
        r, g, b = counter.most_common(1)[0][0]
        palette[index * 3:index * 3 + 3] = [r, g, b]
    snapped = quantized.copy()
    snapped.putpalette(palette)
    return snapped


def whites_to_paper(rgba: Image.Image) -> None:
    """Rend transparentes les zones blanches restantes : le textile fera le blanc."""
    rgba.putdata([TRANSPARENT if (p[3] and p[:3] == WHITE) else p for p in _pixels(rgba)])


def _opaque_counts(img: Image.Image) -> Counter:
    counts: Counter = Counter()
    for n, pixel in (img.getcolors(img.width * img.height) or []):
        if pixel[3] > 0:
            counts[pixel[:3]] += n
    return counts


def _opaque_share(img: Image.Image) -> float:
    opaque = sum(n for n, p in (img.getcolors(img.width * img.height) or []) if p[3] > 0)
    return opaque / float(img.width * img.height)


def opaque_share(img: Image.Image) -> float:
    """Part de l'image restée opaque. Utilisée aussi par la voie matricielle."""
    return _opaque_share(img)


def consolidate_colors(rgba: Image.Image, colors: int, tolerance: int = COLOR_TOLERANCE,
                       min_share: float = MIN_INK_SHARE) -> None:
    """Fusionne les teintes voisines et ramène le dessin à `colors` encres au maximum.

    Les couleurs sont parcourues de la plus présente à la plus rare : chacune rejoint une
    couleur déjà retenue si elle en est assez proche, sinon elle est retenue tant que le
    quota n'est pas atteint, sinon elle est fusionnée avec la plus proche des retenues.
    """
    counts = _opaque_counts(rgba)
    if not counts:
        return
    total = float(sum(counts.values()))
    keep: list = []
    mapping = {}
    limit = tolerance * tolerance
    for color, count in counts.most_common():
        nearest, distance = None, None
        for k in keep:
            d = (k[0] - color[0]) ** 2 + (k[1] - color[1]) ** 2 + (k[2] - color[2]) ** 2
            if distance is None or d < distance:
                nearest, distance = k, d
        # Une teinte anecdotique (quelques mouchetures) ne merite pas une encre :
        # elle rejoint la couleur conservee la plus proche.
        if nearest is not None and (distance < limit or count / total < min_share):
            mapping[color] = nearest
        elif len(keep) < colors:
            keep.append(color)
        else:
            mapping[color] = nearest
    if not mapping:
        return
    rgba.putdata([
        (mapping[p[:3]] + (p[3],)) if (p[3] and p[:3] in mapping) else p
        for p in _pixels(rgba)
    ])


def _border_color_counts(img: Image.Image) -> Counter:
    """Compte les couleurs présentes sur le pourtour de l'image (1 pixel de large)."""
    w, h = img.size
    px = img.load()
    counts: Counter = Counter()
    for x in range(w):
        counts[px[x, 0][:3]] += 1
        counts[px[x, h - 1][:3]] += 1
    for y in range(h):
        counts[px[0, y][:3]] += 1
        counts[px[w - 1, y][:3]] += 1
    return counts


def _edge_seeds(w: int, h: int) -> list:
    seeds = []
    for i in range(SEEDS_PER_EDGE):
        x = min(int((i + 0.5) * w / SEEDS_PER_EDGE), w - 1)
        seeds += [(x, 0), (x, h - 1)]
        y = min(int((i + 0.5) * h / SEEDS_PER_EDGE), h - 1)
        seeds += [(0, y), (w - 1, y)]
    return seeds


def remove_background(rgba: Image.Image) -> None:
    """Retire le fond, blanc ou non, en partant des bords.

    Le remplissage part uniquement du pourtour et sans tolérance : les zones claires
    situées à l'intérieur du dessin sont conservées.
    """
    w, h = rgba.size
    counts = _border_color_counts(rgba)
    if not counts:
        return
    total = sum(counts.values())
    dominant, n = counts.most_common(1)[0]
    seeds = _edge_seeds(w, h)

    # La couleur qui occupe l'essentiel du pourtour est le fond, quelle que soit sa teinte.
    if n / float(total) >= BORDER_SHARE_MIN:
        for xy in seeds:
            pixel = rgba.getpixel(xy)
            if pixel[3] and pixel[:3] == dominant:
                ImageDraw.floodfill(rgba, xy, TRANSPARENT, thresh=0)

    # Sujet qui touche les bords : on retire quand même les zones claires restantes.
    for xy in seeds:
        pixel = rgba.getpixel(xy)
        if pixel[3] and _is_light(pixel):
            ImageDraw.floodfill(rgba, xy, TRANSPARENT, thresh=0)


def prepare_image(png_bytes: bytes, colors: int, remove_bg: bool,
                  white_is_ink: bool = False) -> Image.Image:
    img = Image.open(io.BytesIO(png_bytes)).convert("RGB")
    img = img.filter(ImageFilter.MedianFilter(5))
    if remove_bg:
        flatten_near_white(img)

    target = colors + (1 if remove_bg else 0)
    # MAXCOVERAGE couvre l'espace des couleurs au lieu de découper selon le nombre de pixels :
    # MEDIANCUT gaspillait ses emplacements sur les nuances du fond et délavait le sujet.
    quantized = img.quantize(colors=target, method=Image.Quantize.MAXCOVERAGE, dither=Image.Dither.NONE)
    rgba = snap_palette_to_modes(img, quantized).convert("RGBA")

    # Avant le retrait : on soude les teintes voisines pour que le fond soit d'un seul bloc.
    consolidate_colors(rgba, NO_LIMIT, min_share=0.0)

    if remove_bg:
        before = rgba.copy()
        remove_background(rgba)
        # La broderie a du fil blanc, la sérigraphie et le flex n'ont pas d'encre blanche :
        # dans le second cas le blanc redevient du textile non imprimé.
        if not white_is_ink:
            whites_to_paper(rgba)
        # Filet de sécurité : si tout a été effacé (dessin blanc sur blanc, sujet confondu
        # avec le fond), on rend l'image d'origine plutôt qu'une image vide.
        if _opaque_share(rgba) < 0.03:
            rgba = before

    consolidate_colors(rgba, colors)
    return rgba


def extract_palette(img: Image.Image, min_share: float = 0.005) -> list:
    counts = _opaque_counts(img)
    total = sum(counts.values()) or 1
    palette = []
    for (r, g, b), n in counts.most_common():
        share = n / total
        if share >= min_share:
            palette.append({"hex": f"#{r:02x}{g:02x}{b:02x}", "share": round(share, 3)})
    return palette


FILL_PATTERN = re.compile(r'fill="#([0-9a-fA-F]{6})"')


def snap_fills_to_palette(svg: str, palette: list) -> tuple:
    """Ramène chaque `fill` du SVG sur une couleur de la palette, et dit lesquelles servent.

    Le vectoriseur rééchantillonne la couleur de chaque forme au lieu de reprendre celle
    du pixel : une image réduite à trois couleurs ressort avec dix-neuf `fill` voisins
    (#17121d, #1c1a26, #1d1d2c…). À l'œil c'est la même encre, mais l'application compte
    les `fill` distincts pour annoncer le nombre d'écrans à l'atelier — et un badge à
    quatre couleurs se retrouvait commandé à cent trente-cinq écrans.

    Chaque teinte est donc recalée sur la plus proche de la palette réellement préparée,
    et on renvoie les couleurs effectivement présentes : ce que l'atelier comptera.
    """
    if not palette:
        return svg, []

    references = []
    for entry in palette:
        hex_value = entry["hex"].lstrip("#")
        references.append((
            hex_value,
            (int(hex_value[0:2], 16), int(hex_value[2:4], 16), int(hex_value[4:6], 16)),
        ))

    used = set()
    cache = {}

    def nearest(match) -> str:
        raw = match.group(1).lower()
        if raw not in cache:
            r, g, b = int(raw[0:2], 16), int(raw[2:4], 16), int(raw[4:6], 16)
            cache[raw] = min(
                references,
                key=lambda ref: (ref[1][0] - r) ** 2 + (ref[1][1] - g) ** 2 + (ref[1][2] - b) ** 2,
            )[0]
        used.add(cache[raw])
        return 'fill="#%s"' % cache[raw]

    snapped = FILL_PATTERN.sub(nearest, svg)
    kept = [entry for entry in palette if entry["hex"].lstrip("#") in used]
    return snapped, kept


def to_svg(img: Image.Image, min_detail: int = 20) -> str:
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return vtracer.convert_raw_image_to_svg(
        buf.getvalue(),
        img_format="png",
        colormode="color",
        # "cutout" : formes juxtaposées sans superposition, adapté à la sérigraphie.
        hierarchical="cutout",
        mode="spline",
        # Taille du plus petit détail que la technique sait rendre : une moucheture que le
        # couteau de découpe arracherait n'a pas à figurer dans le fichier.
        filter_speckle=min_detail,
        color_precision=6,
        layer_difference=16,
        corner_threshold=60,
        length_threshold=4.0,
        max_iterations=10,
        splice_threshold=45,
        path_precision=3,
    )


def vectorize(png_bytes: bytes, colors: int, remove_background: bool, max_paths_warning: int,
              technique: str = None) -> dict:
    profile = resolve(technique)
    prepared = prepare_image(png_bytes, colors, remove_background, profile.white_is_ink)
    svg = to_svg(prepared, profile.min_detail)
    # La palette annoncée est celle du fichier livré, pas celle de l'image intermédiaire :
    # c'est la seule façon que le client et l'atelier comptent les mêmes encres.
    svg, palette = snap_fills_to_palette(svg, extract_palette(prepared))
    paths = svg.count("<path")
    # Part de l'image restée opaque : sert à repérer un fond qui n'a pas pu être retiré.
    opaque_share = round(_opaque_share(prepared), 3)

    warnings = []
    if paths > max_paths_warning:
        warnings.append(
            f"Le design contient {paths} formes : il risque d'être difficile à imprimer. "
            "Essayez un style plus simple ou moins de couleurs."
        )
    if paths == 0:
        warnings.append("Aucune forme détectée. Le design est peut-être trop clair : désactivez le retrait du fond.")
    if remove_background and opaque_share > 0.92:
        warnings.append(
            "Le fond n'a pas pu être retiré : le dessin couvre toute l'image. "
            "Relancez la création ou décrivez un sujet isolé."
        )
    # Découpe et broderie : au-delà de quelques dizaines de formes, le fichier est juste
    # et la machine, elle, ne suivra pas.
    if profile.min_detail >= 48 and paths > 60:
        warnings.append(
            f"{profile.label} : le dessin contient {paths} formes, c'est beaucoup pour cette "
            "technique. Un motif plus simple, en une ou deux couleurs, se pose bien mieux."
        )

    return {
        "svg": svg,
        "palette": palette,
        "inks": len(palette),
        "stats": {"paths": paths, "svg_bytes": len(svg.encode("utf-8")), "opaque_share": opaque_share},
        "warnings": warnings,
    }
