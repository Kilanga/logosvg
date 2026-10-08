"""Le visuel déjà fait d'un client, mis au format de l'atelier sans être redessiné."""
import base64
import io
import time

import pytest
from fastapi.testclient import TestClient
from PIL import Image, ImageDraw

import app.jobs as jobs
import app.main as main
from app.main import app

HEADERS = {"X-API-Key": "test-key"}


@pytest.fixture(scope="module")
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


def visuel(size=(600, 300), fmt="PNG", mode="RGB"):
    img = Image.new(mode, size, (255, 255, 255, 0) if mode == "RGBA" else "white")
    ImageDraw.Draw(img).ellipse([50, 50, 250, 250], fill=(200, 30, 40, 255) if mode == "RGBA" else (200, 30, 40))
    ImageDraw.Draw(img).rectangle([320, 80, 560, 220], fill=(20, 60, 160, 255) if mode == "RGBA" else (20, 60, 160))
    buf = io.BytesIO()
    img.save(buf, format=fmt)
    return base64.b64encode(buf.getvalue()).decode()


def convert(client, user_id, **extra):
    body = {"user_id": user_id, "image": visuel(), "technique": "dtf", "print_width_cm": 25}
    body.update(extra)
    return client.post("/convert", headers=HEADERS, json=body)


def test_un_visuel_raster_devient_un_png_d_impression_sans_passer_par_le_modele(client, monkeypatch):
    def interdit(*args, **kwargs):
        raise AssertionError("le modèle ne doit pas être appelé")

    monkeypatch.setattr(jobs, "review", interdit)
    monkeypatch.setattr(jobs, "to_english", interdit)
    r = convert(client, "cv1")
    assert r.status_code == 202, r.text
    assert r.json()["refinements_left"] == 0
    data = wait_for(client, r.json()["job_id"], "cv1")
    assert data["status"] == "done", data
    result = data["result"]
    assert result["mode"] == "convert"
    assert result["output"] == "raster"
    assert result["prompt_used"] is None and result["subject"] is None

    png = client.get(f"/jobs/{r.json()['job_id']}/print.png",
                     params={"user_id": "cv1"}, headers=HEADERS)
    assert png.status_code == 200
    # Les proportions du fichier sont gardées : rien n'est recadré au carré.
    img = Image.open(io.BytesIO(png.content))
    assert abs(img.width / img.height - 2) < 0.05


def test_un_visuel_pour_la_serigraphie_est_vectorise_en_aplats(client):
    r = convert(client, "cv2", technique="screen_printing", colors=2)
    data = wait_for(client, r.json()["job_id"], "cv2")
    assert data["status"] == "done", data
    assert data["result"]["output"] == "vector"
    svg = client.get(f"/jobs/{r.json()['job_id']}/design.svg",
                     params={"user_id": "cv2"}, headers=HEADERS)
    assert svg.status_code == 200 and b"<svg" in svg.content


def test_un_logo_detoure_ne_devient_pas_un_carre_noir():
    from app.init_image import decode_for_print
    png = decode_for_print(visuel(fmt="PNG", mode="RGBA"), 4096)
    img = Image.open(io.BytesIO(png))
    assert img.mode == "RGB"
    assert img.getpixel((5, 5)) == (255, 255, 255)


def test_la_definition_est_gardee_jusqu_a_la_limite():
    from app.init_image import decode_for_print
    assert Image.open(io.BytesIO(decode_for_print(visuel(size=(3000, 1500)), 4096))).size == (3000, 1500)
    assert Image.open(io.BytesIO(decode_for_print(visuel(size=(3000, 1500)), 1000))).size == (1000, 500)


def test_un_visuel_depose_ne_se_retouche_ni_ne_se_decline(client):
    job_id = convert(client, "cv3").json()["job_id"]
    assert wait_for(client, job_id, "cv3")["status"] == "done"
    r = client.post(f"/jobs/{job_id}/refine", headers=HEADERS,
                    json={"instruction": "ajoute un chapeau", "user_id": "cv3"})
    assert r.status_code == 422
    r = client.post(f"/jobs/{job_id}/variants", headers=HEADERS, json={"user_id": "cv3"})
    assert r.status_code == 422


def test_un_fichier_illisible_est_refuse_en_francais(client):
    for payload in ("pas du base64 !", base64.b64encode(b"GIF89a....").decode(), visuel(fmt="BMP")):
        r = convert(client, "cv4", image=payload)
        assert r.status_code == 422, payload[:20]
        assert "visuel" in r.json()["detail"]


def test_sans_cle_pas_de_conversion(client):
    r = client.post("/convert", json={"user_id": "x", "image": visuel()})
    assert r.status_code == 401
