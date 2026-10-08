"""L'image de départ envoyée par le client, ramenée à ce que le modèle sait lire.

Croquis photographié, ancien logo, photo : n'importe quel PNG, JPEG ou WebP. Le
modèle, lui, part d'un carré de la taille de travail. L'image est donc mise à
plat sur du blanc (un logo détouré garde son fond blanc, comme ce que le moteur
génère), réduite pour tenir dans le carré sans être déformée, et centrée sur un
fond blanc. Les métadonnées — dont la position GPS d'une photo de téléphone —
ne survivent pas au réencodage.
"""
import base64
import binascii
import io

from PIL import Image, ImageOps, UnidentifiedImageError

FORMATS = {"PNG", "JPEG", "WEBP"}
# Au-delà, ce n'est pas un croquis : c'est une tentative de saturer le service.
MAX_PIXELS = 40_000_000


class InitImageError(ValueError):
    pass


def decode(data_b64: str, size: int) -> bytes:
    """Renvoie un PNG carré de `size` px, ou lève InitImageError (message en français)."""
    try:
        raw = base64.b64decode(data_b64, validate=True)
    except (binascii.Error, ValueError):
        raise InitImageError("L'image de départ est illisible.")

    Image.MAX_IMAGE_PIXELS = MAX_PIXELS
    try:
        with Image.open(io.BytesIO(raw)) as img:
            if img.format not in FORMATS:
                raise InitImageError("L'image de départ doit être un PNG, un JPEG ou un WebP.")
            img = ImageOps.exif_transpose(img)
            rgba = img.convert("RGBA")
    except (UnidentifiedImageError, Image.DecompressionBombError, OSError):
        raise InitImageError("L'image de départ est illisible.")

    flat = Image.new("RGB", rgba.size, "white")
    flat.paste(rgba, mask=rgba.getchannel("A"))
    flat.thumbnail((size, size), Image.LANCZOS)

    square = Image.new("RGB", (size, size), "white")
    square.paste(flat, ((size - flat.width) // 2, (size - flat.height) // 2))
    out = io.BytesIO()
    square.save(out, format="PNG")
    return out.getvalue()


def decode_for_print(data_b64: str, max_side: int) -> bytes:
    """Le visuel du client, préparé tel quel pour l'impression (pas pour le modèle).

    Contrairement à `decode`, rien n'est recadré au carré : les proportions sont
    celles du fichier, et la définition est gardée jusqu'à `max_side` — un PNG
    d'impression se juge à ses pixels. La transparence est posée sur du blanc,
    comme pour un dessin du modèle : le détourage du service la retrouve, et un
    logo détouré ne devient pas un carré noir au passage.
    """
    try:
        raw = base64.b64decode(data_b64, validate=True)
    except (binascii.Error, ValueError):
        raise InitImageError("Le visuel est illisible.")

    Image.MAX_IMAGE_PIXELS = MAX_PIXELS
    try:
        with Image.open(io.BytesIO(raw)) as img:
            if img.format not in FORMATS:
                raise InitImageError("Le visuel doit être un PNG, un JPEG ou un WebP.")
            img = ImageOps.exif_transpose(img)
            rgba = img.convert("RGBA")
    except (UnidentifiedImageError, Image.DecompressionBombError, OSError):
        raise InitImageError("Le visuel est illisible.")

    flat = Image.new("RGB", rgba.size, "white")
    flat.paste(rgba, mask=rgba.getchannel("A"))
    flat.thumbnail((max_side, max_side), Image.LANCZOS)
    out = io.BytesIO()
    flat.save(out, format="PNG")
    return out.getvalue()
