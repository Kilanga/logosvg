"""Filtres des demandes interdites : la liste de mots, puis la relecture par le modèle."""
import asyncio
import dataclasses
import time
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

import app.jobs as jobs
import app.main as main
import app.moderation as moderation
from app.main import app
from app.prompt_filter import PromptFilter, normalize

HEADERS = {"X-API-Key": "test-key"}
BLOCKLIST = Path(__file__).resolve().parent.parent / "blocklist.txt"


# --- La liste de mots ----------------------------------------------------------

def test_les_deguisements_courants_sont_ramenes_au_mot():
    assert normalize("Un logo N1KE") == "un logo nike"
    assert normalize("d.i.s.n.e.y") == "disney"
    assert normalize("n i k e") == "nike"
    assert normalize("Pokémon") == "pokemon"
    assert normalize("adida$") == "adidas"


def test_un_nombre_reste_un_nombre():
    assert normalize("FÊTE 2026, le 14 juillet") == "fete 2026 le 14 juillet"


def test_la_liste_arrete_les_marques_deguisees_et_laisse_passer_les_idees():
    filtre = PromptFilter(BLOCKLIST)
    assert filtre.blocked_term("un logo n1ke") == "nike"
    assert filtre.blocked_term("pikachu en armure") == "pikachu"
    assert filtre.blocked_term("un renard qui fait du skate") is None


def test_les_mots_courants_ne_sont_pas_dans_la_liste():
    """Un puma est un animal, Mario un prénom : c'est au modèle d'en juger."""
    filtre = PromptFilter(BLOCKLIST)
    assert filtre.blocked_term("un puma qui rugit") is None
    assert filtre.blocked_term("le prénom MARIO en grand") is None


# --- La relecture par le modèle ------------------------------------------------

@pytest.fixture
def ollama(monkeypatch):
    """Ollama configuré, et sa réponse décidée par le test."""
    monkeypatch.setattr(moderation, "settings", dataclasses.replace(
        moderation.settings, ollama_url="http://ollama.test", moderation=True))
    answers = {"verdict": {"allowed": True, "category": "none"}, "calls": []}

    async def fake_ask(request):
        answers["calls"].append(request)
        return answers["verdict"]

    monkeypatch.setattr(moderation, "_ask", fake_ask)
    return answers


def test_un_refus_donne_la_phrase_du_service_pas_celle_du_modele(ollama):
    ollama["verdict"] = {"allowed": False, "category": "brand", "reason": "it's Nike lol"}
    refus = asyncio.run(moderation.review("la virgule d'une marque de sport"))
    assert refus == moderation.REFUSALS["brand"]


def test_une_demande_acceptee_passe(ollama):
    assert asyncio.run(moderation.review("un renard qui fait du skate")) is None


def test_un_refus_sans_categorie_connue_ne_vaut_pas_refus(ollama):
    ollama["verdict"] = {"allowed": False, "category": "weird"}
    assert asyncio.run(moderation.review("un renard")) is None


def test_une_panne_du_modele_laisse_passer(ollama):
    ollama["verdict"] = None
    assert asyncio.run(moderation.review("un renard")) is None


def test_une_retouche_est_relue_avec_le_design_qu_elle_modifie(ollama):
    asyncio.run(moderation.review("mets-lui une casquette", context="a fox on a skateboard"))
    assert "a fox on a skateboard" in ollama["calls"][0]
    assert "mets-lui une casquette" in ollama["calls"][0]


def test_sans_ollama_ou_desactivee_rien_n_est_relu(monkeypatch):
    calls = []

    async def fake_ask(request):
        calls.append(request)
        return {"allowed": False, "category": "brand"}

    monkeypatch.setattr(moderation, "_ask", fake_ask)
    monkeypatch.setattr(moderation, "settings", dataclasses.replace(moderation.settings, ollama_url=""))
    assert asyncio.run(moderation.review("nike")) is None
    monkeypatch.setattr(moderation, "settings", dataclasses.replace(
        moderation.settings, ollama_url="http://ollama.test", moderation=False))
    assert asyncio.run(moderation.review("nike")) is None
    assert calls == []


# --- De bout en bout -----------------------------------------------------------

@pytest.fixture
def client():
    with TestClient(app) as c:
        main.rate_limiter.count = 100
        yield c


def wait_for(client, job_id, user_id, timeout=30):
    deadline = time.time() + timeout
    while time.time() < deadline:
        data = client.get(f"/jobs/{job_id}", params={"user_id": user_id}, headers=HEADERS).json()
        if data["status"] in ("done", "error"):
            return data
        time.sleep(0.2)
    raise AssertionError("Le travail n'a pas terminé à temps")


def test_un_clic_refuse_echoue_en_entier_sans_dessiner_ni_relire_trois_fois(client, monkeypatch):
    calls = []

    async def fake_review(text, context=""):
        calls.append(text)
        return moderation.REFUSALS["character"]

    monkeypatch.setattr(jobs, "review", fake_review)
    r = client.post("/generate", headers=HEADERS, json={
        "prompt": "le petit sorcier à lunettes et sa cicatrice", "style": "mascotte",
        "colors": 3, "user_id": "mod1", "count": 3,
    })
    assert r.status_code == 202, r.text

    results = [wait_for(client, job_id, "mod1") for job_id in r.json()["job_ids"]]
    assert [res["status"] for res in results] == ["error"] * 3
    assert {res["error"] for res in results} == {moderation.REFUSALS["character"]}
    assert len(calls) == 1, "relue une fois pour tout le lot"
