"""Filtre de mots-clés appliqué avant toute génération (marques, contenus interdits)."""
import re
import unicodedata
from pathlib import Path
from typing import Optional

_CONTROL_CHARS = re.compile(r"[\x00-\x1f\x7f]")

# Les chiffres et signes qui se lisent comme des lettres : « n1ke », « d1sn3y »,
# « adida$ ». Seulement collés à une lettre, pour que « 2026 » reste un nombre.
_LOOKALIKES = str.maketrans("013457@$", "oieastas")
_DISGUISED = re.compile(r"(?<=[a-z])[013457@$]+|[013457@$]+(?=[a-z])")
# Des lettres isolées séparées par des espaces ou des points : « n i k e »,
# « d.i.s.n.e.y ». Recollées avant la recherche.
_SPACED = re.compile(r"\b(?:[a-z] ){2,}[a-z]\b")


def normalize(text: str) -> str:
    decomposed = unicodedata.normalize("NFKD", text)
    no_accents = "".join(c for c in decomposed if not unicodedata.combining(c)).lower()
    undisguised = _DISGUISED.sub(lambda m: m.group().translate(_LOOKALIKES), no_accents)
    words = re.sub(r"[^a-z0-9]+", " ", undisguised).strip()
    return _SPACED.sub(lambda m: m.group().replace(" ", ""), words)


def clean_prompt(text: str) -> str:
    return re.sub(r"\s+", " ", _CONTROL_CHARS.sub(" ", text)).strip()


class PromptFilter:
    def __init__(self, path: Path):
        self.terms: list = []
        if path.exists():
            for line in path.read_text(encoding="utf-8").splitlines():
                line = line.strip()
                if line and not line.startswith("#"):
                    self.terms.append(normalize(line))

    def blocked_term(self, prompt: str) -> Optional[str]:
        haystack = f" {normalize(prompt)} "
        for term in self.terms:
            if f" {term} " in haystack:
                return term
        return None
