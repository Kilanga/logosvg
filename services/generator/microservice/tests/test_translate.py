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

    async def fake(text, markers=False, keep_warm=False):
        seen.append(markers)
        return text.replace("un renard", "a fox")

    monkeypatch.setattr(translate, "_translate", fake)
    monkeypatch.setattr(translate, "settings", dataclasses.replace(translate.settings, ollama_url="http://ollama.test"))

    assert asyncio.run(translate.to_english("un renard")) == "a fox"
    assert asyncio.run(translate.to_english('un renard "GO"')) == 'a fox "GO"'
    assert seen == [False, True]


# Recette du 16/10/2026 : une demande de retouche passée par la consigne des
# idées revenait en majuscules entre guillemets, c'est-à-dire en texte à imprimer.
def test_une_demande_de_retouche_a_sa_propre_consigne_et_perd_ses_guillemets(monkeypatch):
    seen = {}

    async def fake_chat(system, user, **kwargs):
        seen["system"], seen["user"] = system, user
        return '"PUT" "the" [[T1]] big under the board'

    monkeypatch.setattr(translate.ollama, "chat", fake_chat)
    monkeypatch.setattr(translate, "settings", dataclasses.replace(translate.settings, ollama_url="http://ollama.test"))

    result = asyncio.run(translate.instruction_to_english('mets "PIZZA CLUB" en grand sous la planche'))

    assert seen["system"] is translate.INSTRUCTION_SYSTEM
    assert seen["user"] == "mets [[T1]] en grand sous la planche"
    assert result == 'PUT the "PIZZA CLUB" big under the board'


def test_les_deux_consignes_connaissent_les_mots_a_double_sens():
    assert "blaireau (badger" in translate.SYSTEM
    assert "blaireau (badger" in translate.INSTRUCTION_SYSTEM


def test_sans_traducteur_la_demande_reste_telle_quelle(monkeypatch):
    async def broken(*args, **kwargs):
        raise RuntimeError("Ollama éteint")

    monkeypatch.setattr(translate.ollama, "chat", broken)
    monkeypatch.setattr(translate, "settings", dataclasses.replace(translate.settings, ollama_url="http://ollama.test"))

    assert asyncio.run(translate.instruction_to_english("enlève le fond")) == "enlève le fond"
