"""Ce que le traducteur renvoie, nettoyé avant d'aller dans le prompt."""
import asyncio
import dataclasses

import app.translate as translate
from app.translate import clean_output, protect, restore


def test_un_repere_invente_est_retire():
    # Recette du 14/10/2026 : « style aquarelle » revenait en « watercolor style "T1 ».
    assert clean_output('two otters cuddling under a rainbow, watercolor style "T1', 0) == \
        "two otters cuddling under a rainbow, watercolor style"
    assert clean_output("a fox [[T2]] on a skateboard", 1) == "a fox on a skateboard"


def test_les_vrais_reperes_restent():
    protected, saved = protect('un renard avec le texte "PIZZA CLUB"')
    assert clean_output("a fox with the text [[T1]]", len(saved)) == "a fox with the text [[T1]]"
    assert restore("a fox with the text [[T1]]", saved) == 'a fox with the text "PIZZA CLUB"'


def test_un_guillemet_reste_ouvert_est_retire():
    assert clean_output('a fox "PIZZA CLUB" and a "cat', 0) == 'a fox "PIZZA CLUB" and a cat'


def test_la_consigne_ne_parle_des_reperes_que_s_il_y_en_a(monkeypatch):
    seen = []

    async def fake(text, markers=False):
        seen.append(markers)
        return text.replace("un renard", "a fox")

    monkeypatch.setattr(translate, "_translate", fake)
    monkeypatch.setattr(translate, "settings", dataclasses.replace(translate.settings, ollama_url="http://ollama.test"))

    assert asyncio.run(translate.to_english("un renard")) == "a fox"
    assert asyncio.run(translate.to_english('un renard "GO"')) == 'a fox "GO"'
    assert seen == [False, True]
