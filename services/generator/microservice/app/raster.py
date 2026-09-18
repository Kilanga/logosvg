"""Sortie matricielle : le fichier d'impression des machines qui n'attendent pas de vecteur.

En DTF, DTG ou sublimation, l'atelier imprime une image en quadrichromie : vectoriser
reviendrait à détruire les dégradés pour rien, et à livrer un fichier que la machine
convertirait de toute façon en pixels. La préparation est donc différente :

1. léger lissage — on retire le bruit de génération sans écraser le détail ;
2. détourage du fond, en réutilisant le même remplissage par les bords que la
   vectorisation : c'est la transparence qui fait le fichier d'impression ;
3. le blanc reste imprimé si la machine a une encre blanche (DTF, DTG), et redevient la
   couleur du textile si elle n'en a pas (sublimation) ;
4. mise à l'échelle de la taille d'impression demandée, à la résolution de la technique.

Aucune réduction de couleurs : le nombre d'encres n'a pas de sens ici, la palette
renvoyée n'est qu'indicative (elle alimente l'affichage, pas la compatibilité).
"""
import io

from PIL import Image, ImageFilter

from .techniques import Technique
from .vectorizer import (
    extract_palette,
    flatten_near_white,
    opaque_share,
    remove_background,
    whites_to_paper,
)

CM_PER_INCH = 2.54
# Résolution réellement produite par le modèle, une fois le dessin porté à sa taille
# d'impression. Le fichier livré est bien en 300 dpi, mais au-delà de cet agrandissement
# les pixels supplémentaires sont inventés par l'interpolation : c'est cette valeur-là,
# et non le dpi du fichier, qui dit si le rendu sera net. 150 dpi est le seuil au-delà
# duquel un atelier accepte couramment un fichier DTF.
MIN_SOURCE_DPI = 150
# Part de blanc à partir de laquelle l'absence d'encre blanche se verra sur le vêtement.
WHITE_SHARE_WARNING = 0.08


def target_pixels(print_width_cm: float, dpi: int) -> int:
    return max(int(round(print_width_cm / CM_PER_INCH * dpi)), 1)


def _white_share(img: Image.Image) -> float:
    """Part de l'image qui est du blanc pur et opaque."""
    total = img.width * img.height
    white = sum(
        n for n, p in (img.getcolors(total) or [])
        if p[3] > 0 and p[0] > 246 and p[1] > 246 and p[2] > 246
    )
    return white / float(total)


def prepare_raster(png_bytes: bytes, profile: Technique, remove_bg: bool) -> tuple:
    """Renvoie l'image détourée et la part de blanc que la machine ne saura pas imprimer."""
    img = Image.open(io.BytesIO(png_bytes)).convert("RGB")
    # Médiane 3 et non 5 : ici on garde le détail, on ne prépare pas une vectorisation.
    img = img.filter(ImageFilter.MedianFilter(3))
    if remove_bg:
        flatten_near_white(img)

    rgba = img.convert("RGBA")
    dropped_white = 0.0
    if remove_bg:
        before = rgba.copy()
        remove_background(rgba)
        if not profile.white_is_ink:
            # Pas d'encre blanche : ces zones prendront la couleur du textile. On les
            # mesure avant de les rendre transparentes, pour pouvoir en avertir le client.
            dropped_white = _white_share(rgba)
            whites_to_paper(rgba)
        # Filet de sécurité : si tout a été effacé, on rend l'image d'origine.
        if opaque_share(rgba) < 0.03:
            rgba, dropped_white = before, 0.0
    return rgba, dropped_white


def rasterize(png_bytes: bytes, profile: Technique, remove_bg: bool,
              print_width_cm: float) -> dict:
    """Produit le PNG d'impression, à la taille et à la résolution de la technique."""
    prepared, dropped_white = prepare_raster(png_bytes, profile, remove_bg)

    wanted = target_pixels(print_width_cm, profile.dpi)
    factor = wanted / float(prepared.width)
    height = max(int(round(prepared.height * factor)), 1)
    scaled = prepared.resize((wanted, height), Image.LANCZOS)

    buf = io.BytesIO()
    scaled.save(buf, format="PNG", dpi=(profile.dpi, profile.dpi))

    share = round(opaque_share(scaled), 3)
    # Ce que le modèle a réellement dessiné, ramené à la taille d'impression.
    source_dpi = int(round(prepared.width / (print_width_cm / CM_PER_INCH)))
    net_width = round(prepared.width / MIN_SOURCE_DPI * CM_PER_INCH)

    warnings = []
    if source_dpi < MIN_SOURCE_DPI:
        warnings.append(
            f"À {print_width_cm:.0f} cm de large, le dessin d'origine ne fournit que "
            f"{source_dpi} dpi : le fichier est bien en 300 dpi, mais les détails fins "
            f"seront adoucis. Jusqu'à {net_width} cm, le rendu reste net."
        )
    if remove_bg and share > 0.92:
        warnings.append(
            "Le fond n'a pas pu être retiré : le dessin couvre toute l'image. "
            "Relancez la création ou décrivez un sujet isolé."
        )
    if share < 0.02:
        warnings.append("Presque rien n'est resté visible après le détourage. Relancez la création.")
    if dropped_white > WHITE_SHARE_WARNING:
        warnings.append(
            "Cette technique n'imprime pas de blanc : les zones blanches du dessin "
            "prendront la couleur du textile."
        )

    palette = extract_palette(scaled, min_share=0.01)
    return {
        "png": buf.getvalue(),
        "palette": palette,
        # Indicatif : en quadrichromie le nombre de couleurs ne coûte rien et ne sert pas
        # à la compatibilité avec l'atelier.
        "inks": len(palette),
        "stats": {
            "paths": 0,
            "width_px": scaled.width,
            "height_px": scaled.height,
            "print_width_cm": round(print_width_cm, 1),
            "print_height_cm": round(print_width_cm * scaled.height / scaled.width, 1),
            "dpi": profile.dpi,
            "upscale": round(factor, 2),
            # Résolution réelle du dessin à cette taille : c'est elle qui dit si le rendu
            # sera net, pas le dpi du fichier, qui vaut toujours 300.
            "source_dpi": source_dpi,
            "net_width_cm": net_width,
            # Part du dessin que la machine ne sait pas imprimer, faute d'encre blanche.
            "white_share": round(dropped_white, 3),
            "png_bytes": len(buf.getvalue()),
            "opaque_share": share,
        },
        "warnings": warnings,
    }
