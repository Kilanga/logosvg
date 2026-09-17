"""Filtre de mots-clés appliqué avant toute génération (marques, contenus interdits)."""
import re
import unicodedata
from pathlib import Path
from typing import Optional

_CONTROL_CHARS = re.compile(r"[\x00-\x1f\x7f]")


def normalize(text: str) -> str:
    decomposed = unicodedata.normalize("NFKD", text)
    no_accents = "".join(c for c in decomposed if not unicodedata.combining(c))
    return re.sub(r"[^a-z0-9]+", " ", no_accents.lower()).strip()


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
