"""Catalogue des techniques d'impression, et ce que chacune impose au design.

Le service ne produit pas « un SVG » : il produit **le fichier que l'atelier sait imprimer**.
Une sérigraphie veut des aplats vectorisés en quelques encres ; un DTF veut une image
matricielle en 300 dpi à fond transparent, dégradés compris. La technique choisie par le
client pilote donc trois choses, et c'est tout l'intérêt de ce module :

1. le **prompt** (`prompt_builder`) — un visuel pensé dès la génération pour deux couleurs
   vaut infiniment mieux qu'un visuel riche réduit après coup ;
2. la **sortie** (`vectorizer` ou `raster`) — vectorisation, ou détourage et mise à l'échelle ;
3. les **alertes** renvoyées au client et jointes à la fiche technique de l'atelier.

`family` décide de la voie de sortie. `white_is_ink` dit si le blanc est imprimable :
faux en sérigraphie et en sublimation (le textile fait le blanc), vrai en DTF, DTG et
broderie. `min_detail` est la taille du plus petit détail que la technique sait rendre ;
il pilote le filtrage des mouchetures à la vectorisation.
"""
from dataclasses import asdict, dataclass
from typing import Optional

DEFAULT_TECHNIQUE = "screen_printing"
DEFAULT_PRINT_WIDTH_CM = 25.0


@dataclass(frozen=True)
class Technique:
    key: str
    label: str  # libellé client, en français
    family: str  # vector | raster
    max_colors: Optional[int]  # None : autant de couleurs que voulu
    default_colors: int
    gradients: bool
    white_is_ink: bool
    min_detail: int  # mouchetures ignorées à la vectorisation
    dpi: int
    # Une phrase en anglais, lue par FLUX.2 : ce que la technique exige du dessin.
    # FLUX lit les négations (son encodeur est un modèle de langage, pas CLIP) :
    # les interdits y sont dits en clair, il n'y a plus de prompt négatif.
    prompt_hint: str

    @property
    def file_name(self) -> str:
        return "design.svg" if self.family == "vector" else "print.png"

    @property
    def limited_colors(self) -> bool:
        return self.max_colors is not None

    def clamp_colors(self, colors: Optional[int]) -> int:
        asked = colors if colors else self.default_colors
        if self.max_colors is None:
            return max(asked, self.default_colors)
        return max(1, min(asked, self.max_colors))


CATALOG = {
    t.key: t
    for t in (
        Technique(
            key="screen_printing",
            label="Sérigraphie",
            family="vector",
            max_colors=6,
            default_colors=3,
            gradients=False,
            white_is_ink=False,
            min_detail=20,
            dpi=300,
            prompt_hint=(
                "Screen printing artwork: solid spot colors with crisp clean edges, "
                "no gradients, no shading, no texture, no halftone."
            ),
        ),
        Technique(
            key="flex",
            label="Flex ou flocage (découpe)",
            family="vector",
            max_colors=2,
            default_colors=1,
            gradients=False,
            white_is_ink=False,
            # Le vinyle est découpé au couteau : un détail plus petit que le couteau
            # s'arrache au pelage. On filtre donc beaucoup plus large qu'en sérigraphie.
            min_detail=64,
            dpi=300,
            prompt_hint=(
                "Cut vinyl design: one bold solid silhouette with very thick shapes and large "
                "connected areas; no thin lines, no small details, no tiny ornaments."
            ),
        ),
        Technique(
            key="embroidery",
            label="Broderie",
            family="vector",
            max_colors=6,
            default_colors=4,
            gradients=False,
            white_is_ink=True,
            # Un point de broderie mesure environ un millimètre : tout ce qui est plus
            # fin devient un paquet de fil.
            min_detail=56,
            dpi=300,
            prompt_hint=(
                "Embroidery design: bold simple shapes, thick outlines and large flat areas; "
                "no thin lines, no small details, no tiny text."
            ),
        ),
        Technique(
            key="dtf",
            label="DTF (transfert numérique)",
            family="raster",
            max_colors=None,
            default_colors=8,
            gradients=True,
            white_is_ink=True,
            min_detail=0,
            dpi=300,
            prompt_hint="Full-color illustration with rich colors, smooth shading and crisp clean edges.",
        ),
        Technique(
            key="dtg",
            label="DTG (impression directe)",
            family="raster",
            max_colors=None,
            default_colors=8,
            gradients=True,
            white_is_ink=True,
            min_detail=0,
            dpi=300,
            prompt_hint="Full-color illustration with rich colors, smooth shading and crisp clean edges.",
        ),
        Technique(
            key="sublimation",
            label="Sublimation",
            family="raster",
            max_colors=None,
            default_colors=8,
            gradients=True,
            # La sublimation n'a pas d'encre blanche : le blanc reste la couleur du textile.
            white_is_ink=False,
            min_detail=0,
            dpi=300,
            prompt_hint=(
                "Full-color illustration with rich colors and smooth shading, bright tones; "
                "no white outline, as the fabric itself provides the white."
            ),
        ),
    )
}

KEYS = tuple(CATALOG)


def resolve(key: Optional[str]) -> Technique:
    """Renvoie le profil demandé, ou celui par défaut si la clé est inconnue."""
    return CATALOG.get(key or DEFAULT_TECHNIQUE, CATALOG[DEFAULT_TECHNIQUE])


def catalog_payload() -> list:
    """Le catalogue tel que Rails le lit pour alimenter la fiche atelier et l'écran de création."""
    payload = []
    for technique in CATALOG.values():
        entry = asdict(technique)
        entry.pop("prompt_hint", None)
        entry["file_name"] = technique.file_name
        payload.append(entry)
    return payload
