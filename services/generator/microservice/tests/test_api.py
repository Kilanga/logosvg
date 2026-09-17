import time

import pytest
from fastapi.testclient import TestClient

from app.main import app

HEADERS = {"X-API-Key": "test-key"}


@pytest.fixture(scope="module")
def client():
    with TestClient(app) as c:
        yield c


def wait_for(client, job_id, user_id, timeout=30):
    deadline = time.time() + timeout
    while time.time() < deadline:
        data = client.get(f"/jobs/{job_id}", params={"user_id": user_id}, headers=HEADERS).json()
        if data["status"] in ("done", "error"):
            return data
        time.sleep(0.3)
    raise AssertionError("Le travail n'a pas terminé à temps")


def test_refuse_sans_cle(client):
    r = client.post("/generate", json={"prompt": "un renard", "user_id": "u1"})
    assert r.status_code == 401


def test_bloque_une_marque(client):
    r = client.post("/generate", headers=HEADERS, json={"prompt": "Logo façon Nïke", "user_id": "u1"})
    assert r.status_code == 422


def test_pipeline_complet(client):
    r = client.post("/generate", headers=HEADERS, json={
        "prompt": "un renard qui fait du skate", "style": "mascotte",
        "colors": 3, "user_id": "u2", "seed": 42,
    })
    assert r.status_code == 202
    job_id = r.json()["job_id"]

    data = wait_for(client, job_id, "u2")
    assert data["status"] == "done", data
    assert 1 <= data["result"]["inks"] <= 3
    assert data["result"]["stats"]["paths"] > 0

    svg = client.get(f"/jobs/{job_id}/design.svg", params={"user_id": "u2"}, headers=HEADERS)
    assert svg.status_code == 200
    assert "<svg" in svg.text and "<script" not in svg.text

    png = client.get(f"/jobs/{job_id}/source.png", params={"user_id": "u2"}, headers=HEADERS)
    assert png.content[:4] == b"\x89PNG"


def test_isolation_entre_utilisateurs(client):
    r = client.post("/generate", headers=HEADERS, json={"prompt": "une montagne", "user_id": "u3"})
    job_id = r.json()["job_id"]
    other = client.get(f"/jobs/{job_id}", params={"user_id": "intrus"}, headers=HEADERS)
    assert other.status_code == 404


def test_limite_de_debit(client):
    codes = [
        client.post("/generate", headers=HEADERS, json={"prompt": "un phare", "user_id": "u4"}).status_code
        for _ in range(4)
    ]
    assert codes[:3] == [202, 202, 202]
    assert codes[3] == 429


def test_nom_de_fichier_interdit(client):
    r = client.post("/generate", headers=HEADERS, json={"prompt": "un chat", "user_id": "u5"})
    job_id = r.json()["job_id"]
    wait_for(client, job_id, "u5")
    bad = client.get(f"/jobs/{job_id}/config.py", params={"user_id": "u5"}, headers=HEADERS)
    assert bad.status_code == 404
