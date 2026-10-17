"""Relecture du texte demandé, et nouveaux tirages quand il est mal écrit (17/10/2026)."""
import app.jobs as jobs_module
import app.main as main
from app.text_check import Reading, expected_texts, judge, normalize
from tests.test_refine import HEADERS, client, wait_for  # noqa: F401 (fixture)


def test_les_textes_attendus_sont_ceux_entre_guillemets():
    assert expected_texts('a cat on a skateboard, with the text "PIZZA CLUB"') == ["PIZZA CLUB"]
    assert expected_texts("a cat on a skateboard") == []


def test_la_casse_les_espaces_et_les_accents_ne_comptent_pas():
    assert normalize("Fête 2026 !") == "FETE2026"
    assert judge(["pizza", "club"], ["PIZZA CLUB"]).exact


def test_une_lettre_en_trop_n_est_pas_exacte_mais_reste_proche():
    reading = judge(["PIZZA CLLLUB"], ["PIZZA CLUB"])
    assert not reading.exact
    assert reading.score > 0.8
    assert judge(["MOUNTAIN"], ["PIZZA CLUB"]).score < reading.score


def test_un_texte_mal_ecrit_est_redessine_jusqu_a_ce_qu_il_soit_juste(client, monkeypatch):
    readings = iter([Reading(False, 0.8, "PIZZA CLLLUB"), Reading(True, 1.0, "PIZZA CLUB")])
    monkeypatch.setattr(jobs_module, "check_text", lambda png, texts: next(readings))
    calls = []
    generator = main.manager.generator
    original = generator.generate

    async def generate(prompt, seed, colors):
        calls.append(seed)
        return await original(prompt, seed, colors)

    monkeypatch.setattr(generator, "generate", generate)
    r = client.post("/generate", headers=HEADERS, json={
        "prompt": 'un chat sur un skate avec le texte "PIZZA CLUB"', "user_id": "ocr1", "seed": 11,
    })
    data = wait_for(client, r.json()["job_id"], "ocr1")

    assert data["status"] == "done", data
    assert len(calls) == 2 and calls[0] == 11
    assert data["result"]["seed"] == calls[1], "le tirage gardé devient celui du design"
    assert not any("texte du dessin" in w for w in data["result"]["warnings"])


def test_apres_les_essais_le_plus_proche_est_garde_avec_un_avertissement(client, monkeypatch):
    readings = iter([Reading(False, 0.5, "PIZ"), Reading(False, 0.9, "PIZZA CLLUB"), Reading(False, 0.6, "PIZZ")])
    monkeypatch.setattr(jobs_module, "check_text", lambda png, texts: next(readings))
    seeds = []
    generator = main.manager.generator
    original = generator.generate

    async def generate(prompt, seed, colors):
        seeds.append(seed)
        return await original(prompt, seed, colors)

    monkeypatch.setattr(generator, "generate", generate)
    r = client.post("/generate", headers=HEADERS, json={
        "prompt": 'un chat avec le texte "PIZZA CLUB"', "user_id": "ocr2", "seed": 5,
    })
    data = wait_for(client, r.json()["job_id"], "ocr2")

    assert len(seeds) == 3
    assert data["result"]["seed"] == seeds[1], "le plus proche des trois"
    assert any("texte du dessin" in w for w in data["result"]["warnings"])


def test_sans_texte_rien_n_est_relu(client, monkeypatch):
    def interdit(png, texts):
        raise AssertionError("aucune relecture sans texte")

    monkeypatch.setattr(jobs_module, "check_text", interdit)
    r = client.post("/generate", headers=HEADERS, json={"prompt": "un renard", "user_id": "ocr3"})
    assert wait_for(client, r.json()["job_id"], "ocr3")["status"] == "done"
