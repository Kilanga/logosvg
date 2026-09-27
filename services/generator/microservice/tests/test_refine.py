"""Parcours de reprise d'un design : variantes, chat de retouche, budget, lignée."""
import time

import pytest
from fastapi.testclient import TestClient

import app.main as main
from app.main import app

HEADERS = {"X-API-Key": "test-key"}


@pytest.fixture(scope="module")
def client():
    with TestClient(app) as c:
        # La limitation de débit a ses propres tests : ici elle ne doit pas masquer
        # le budget de reprises, qui est la règle mesurée.
        main.rate_limiter.count = 100
        yield c


def wait_for(client, job_id, user_id, timeout=30):
    deadline = time.time() + timeout
    while time.time() < deadline:
        data = client.get(f"/jobs/{job_id}", params={"user_id": user_id}, headers=HEADERS).json()
        if data["status"] in ("done", "error"):
            return data
        time.sleep(0.3)
    raise AssertionError("Le travail n'a pas terminé à temps")


def create_design(client, user_id, colors=3):
    r = client.post("/generate", headers=HEADERS, json={
        "prompt": "un renard qui fait du skate", "style": "mascotte",
        "colors": colors, "user_id": user_id, "seed": 7,
    })
    assert r.status_code == 202, r.text
    assert r.json()["refinements_left"] == 3
    job_id = r.json()["job_id"]
    assert wait_for(client, job_id, user_id)["status"] == "done"
    return job_id


def test_retouche_cree_une_nouvelle_version(client):
    parent = create_design(client, "r1")
    r = client.post(f"/jobs/{parent}/refine", headers=HEADERS,
                    json={"instruction": "enleve le skateboard et souris", "user_id": "r1"})
    assert r.status_code == 202, r.text
    body = r.json()
    assert body["refinements_left"] == 2
    child = body["job_id"]

    data = wait_for(client, child, "r1")
    assert data["status"] == "done", data
    assert data["mode"] == "refine"
    assert data["parent_id"] == parent
    assert data["root_id"] == parent
    result = data["result"]
    assert result["instruction"] == "enleve le skateboard et souris"
    # Sans Ollama, la description du parent est complétée par l'instruction traduite.
    assert "skateboard" in result["subject"]
    assert result["seed"] != 7  # nouveau tirage
    assert result["inks"] >= 1

    # L'image retouchée n'est pas une copie de son parent.
    png_parent = client.get(f"/jobs/{parent}/source.png", params={"user_id": "r1"}, headers=HEADERS).content
    png_child = client.get(f"/jobs/{child}/source.png", params={"user_id": "r1"}, headers=HEADERS).content
    assert png_parent[:4] == b"\x89PNG" and png_child[:4] == b"\x89PNG"
    assert png_parent != png_child

    svg = client.get(f"/jobs/{child}/design.svg", params={"user_id": "r1"}, headers=HEADERS)
    assert svg.status_code == 200 and "<svg" in svg.text


def test_variantes_gardent_la_description(client):
    parent = create_design(client, "r2")
    parent_subject = client.get(f"/jobs/{parent}", params={"user_id": "r2"},
                                headers=HEADERS).json()["result"]["subject"]

    r = client.post(f"/jobs/{parent}/variants", headers=HEADERS, json={"user_id": "r2", "count": 2})
    assert r.status_code == 202, r.text
    ids = r.json()["job_ids"]
    assert len(ids) == 2
    # Un clic, une reprise : deux tirages nés du même geste n'en coûtent qu'une.
    assert r.json()["refinements_left"] == 2

    seeds = set()
    for job_id in ids:
        data = wait_for(client, job_id, "r2")
        assert data["status"] == "done", data
        assert data["mode"] == "variant"
        assert data["root_id"] == parent
        assert data["result"]["subject"] == parent_subject
        seeds.add(data["result"]["seed"])
    assert len(seeds) == 2  # deux tirages differents


def test_budget_de_reprises_puis_graphiste(client):
    parent = create_design(client, "r3")
    for i in range(3):
        r = client.post(f"/jobs/{parent}/refine", headers=HEADERS,
                        json={"instruction": f"change la couleur numero {i}", "user_id": "r3"})
        assert r.status_code == 202, r.text
        assert r.json()["refinements_left"] == 2 - i
        assert wait_for(client, r.json()["job_id"], "r3")["status"] == "done"

    r = client.post(f"/jobs/{parent}/refine", headers=HEADERS,
                    json={"instruction": "encore une modification", "user_id": "r3"})
    assert r.status_code == 429
    body = r.json()
    assert body["refinements_left"] == 0
    assert body["reason"] == "refine_budget"
    assert "graphiste" in body["detail"]


def test_un_clic_de_variantes_ne_coute_quune_reprise(client):
    """Le defaut qui a motive cette regle : trois tirages d'un meme clic
    consommaient les trois reprises, et le chat de retouche devenait
    inaccessible a qui avait demande des variantes en premier."""
    parent = create_design(client, "r4")
    r = client.post(f"/jobs/{parent}/variants", headers=HEADERS, json={"user_id": "r4", "count": 3})
    assert r.status_code == 202, r.text
    assert len(r.json()["job_ids"]) == 3
    assert r.json()["refinements_left"] == 2
    for job_id in r.json()["job_ids"]:
        assert wait_for(client, job_id, "r4")["status"] == "done"

    # Et la retouche reste possible, ce qui etait tout l'objet de la correction.
    r = client.post(f"/jobs/{parent}/refine", headers=HEADERS,
                    json={"instruction": "mets un fond uni", "user_id": "r4"})
    assert r.status_code == 202, r.text
    assert r.json()["refinements_left"] == 1
    assert wait_for(client, r.json()["job_id"], "r4")["status"] == "done"


def test_budget_epuise_par_trois_actions_melangees(client):
    parent = create_design(client, "r8")
    for _ in range(2):
        r = client.post(f"/jobs/{parent}/variants", headers=HEADERS, json={"user_id": "r8", "count": 3})
        assert r.status_code == 202, r.text
        for job_id in r.json()["job_ids"]:
            wait_for(client, job_id, "r8")
    r = client.post(f"/jobs/{parent}/refine", headers=HEADERS,
                    json={"instruction": "un fond uni", "user_id": "r8"})
    assert r.status_code == 202, r.text
    assert r.json()["refinements_left"] == 0
    wait_for(client, r.json()["job_id"], "r8")

    # Deux clics de variantes et une retouche : le budget est epuise.
    r = client.post(f"/jobs/{parent}/variants", headers=HEADERS, json={"user_id": "r8", "count": 3})
    assert r.status_code == 429
    assert r.json()["reason"] == "refine_budget"


def test_instruction_filtree(client):
    parent = create_design(client, "r5")
    r = client.post(f"/jobs/{parent}/refine", headers=HEADERS,
                    json={"instruction": "ajoute le logo Nïke dessus", "user_id": "r5"})
    assert r.status_code == 422
    assert "autorisé" in r.json()["detail"]


def test_retouche_isolee_entre_utilisateurs(client):
    parent = create_design(client, "r6")
    r = client.post(f"/jobs/{parent}/refine", headers=HEADERS,
                    json={"instruction": "change tout", "user_id": "intrus"})
    assert r.status_code == 404


def test_retouche_refusee_si_parent_pas_pret(client):
    r = client.post("/generate", headers=HEADERS, json={
        "prompt": "un phare dans la tempete", "style": "logo", "colors": 2, "user_id": "r7",
    })
    parent = r.json()["job_id"]
    # Le design est encore en file : on ne peut pas retoucher ce qui n'existe pas.
    r = client.post(f"/jobs/{parent}/refine", headers=HEADERS,
                    json={"instruction": "ajoute un bateau", "user_id": "r7"})
    assert r.status_code == 409
    wait_for(client, parent, "r7")
