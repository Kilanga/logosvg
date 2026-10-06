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


# --------------------------------------------------------------------------- restauration
# La machine à GPU s'éteint désormais à la main : chaque redémarrage vide la
# mémoire du service, et les fichiers n'y vivent qu'une heure. Rails garde l'image
# de départ et la description, et les renvoie pour reprendre un design oublié.

def _source_png(client, user_id):
    parent = create_design(client, user_id)
    png = client.get(f"/jobs/{parent}/source.png", params={"user_id": user_id}, headers=HEADERS).content
    subject = client.get(f"/jobs/{parent}", params={"user_id": user_id},
                         headers=HEADERS).json()["result"]["subject"]
    return png, subject


def _restore(client, user_id, png, subject, used=0, **extra):
    import base64
    body = {"user_id": user_id, "prompt": "un renard qui fait du skate", "subject": subject,
            "style": "mascotte", "technique": "screen_printing", "colors": 3,
            "used_refinements": used, "seed": 11,
            "source_png": base64.b64encode(png).decode()}
    body.update(extra)
    return client.post("/jobs/restore", headers=HEADERS, json=body)


def test_un_design_restaure_se_reprend_comme_un_autre(client):
    png, subject = _source_png(client, "rs1")
    r = _restore(client, "rs1", png, subject, used=1)
    assert r.status_code == 201, r.text
    restored = r.json()["job_id"]
    assert r.json()["refinements_left"] == 2

    status = client.get(f"/jobs/{restored}", params={"user_id": "rs1"}, headers=HEADERS).json()
    assert status["status"] == "done"
    assert status["result"]["subject"] == subject

    child = client.post(f"/jobs/{restored}/refine", headers=HEADERS,
                        json={"instruction": "ajoute un soleil", "user_id": "rs1"})
    assert child.status_code == 202, child.text
    assert child.json()["refinements_left"] == 1
    data = wait_for(client, child.json()["job_id"], "rs1")
    assert data["status"] == "done", data
    assert data["root_id"] == restored


def test_le_compte_apporte_par_rails_borne_la_lignee(client):
    png, subject = _source_png(client, "rs2")
    restored = _restore(client, "rs2", png, subject, used=3).json()["job_id"]

    r = client.post(f"/jobs/{restored}/variants", headers=HEADERS, json={"user_id": "rs2"})
    assert r.status_code == 429
    assert r.json()["reason"] == "refine_budget"


def test_une_image_qui_n_est_pas_un_png_est_refusee(client):
    r = _restore(client, "rs3", b"GIF89a pas un png", "a fox")
    assert r.status_code == 422


def test_la_restauration_exige_la_cle(client):
    r = client.post("/jobs/restore", json={"user_id": "x"})
    assert r.status_code == 401


# ------------------------------------------------------------- image de départ
# Le client peut partir d'une image à lui (croquis, ancien logo, photo) : le
# dessin en dérive, transformé selon sa description. Facultatif.

def _image_client(fmt="PNG", size=(300, 200)):
    import base64
    import io

    from PIL import Image, ImageDraw
    img = Image.new("RGB", size, "white")
    ImageDraw.Draw(img).rectangle([40, 40, 160, 160], fill=(30, 90, 120))
    buf = io.BytesIO()
    img.save(buf, format=fmt)
    return base64.b64encode(buf.getvalue()).decode()


def test_une_creation_peut_partir_d_une_image_du_client(client):
    r = client.post("/generate", headers=HEADERS, json={
        "prompt": "transforme ce croquis en logo", "style": "logo", "colors": 2,
        "user_id": "img1", "seed": 7, "init_image": _image_client("JPEG"),
    })
    assert r.status_code == 202, r.text
    data = wait_for(client, r.json()["job_id"], "img1")
    assert data["status"] == "done", data
    assert data["result"]["from_image"] is True

    # Une variante redessine la même image de départ.
    v = client.post(f"/jobs/{r.json()['job_id']}/variants", headers=HEADERS, json={"user_id": "img1", "count": 1})
    assert v.status_code == 202, v.text
    assert wait_for(client, v.json()["job_id"], "img1")["result"]["from_image"] is True


def test_sans_image_rien_ne_change(client):
    job = create_design(client, "img2")
    data = client.get(f"/jobs/{job}", params={"user_id": "img2"}, headers=HEADERS).json()
    assert data["result"]["from_image"] is False


def test_une_image_illisible_ou_d_un_autre_format_est_refusee_en_francais(client):
    import base64
    for payload in ("pas du base64 !", base64.b64encode(b"GIF89a....").decode(), _image_client("BMP")):
        r = client.post("/generate", headers=HEADERS, json={
            "prompt": "un logo", "user_id": "img3", "init_image": payload,
        })
        assert r.status_code == 422, payload[:20]
        assert "image de départ" in r.json()["detail"]


def test_l_image_est_ramenee_au_carre_de_travail_sans_ses_metadonnees():
    import base64
    import io

    from PIL import Image

    from app.init_image import decode

    png = decode(_image_client("PNG", size=(800, 400)), 512)
    img = Image.open(io.BytesIO(png))
    assert img.size == (512, 512)
    assert img.getpixel((5, 5)) == (255, 255, 255)  # bandes blanches, pas de déformation
    assert not img.info.get("exif")


# ------------------------------------------------------------ trois propositions
# Décidé le 06/10/2026 : chaque demande dessine trois propositions, dans des
# registres voisins ; le client en choisit une. Un clic, une seule reprise.

def test_une_creation_donne_trois_propositions_d_un_meme_lot(client):
    r = client.post("/generate", headers=HEADERS, json={
        "prompt": "un renard qui fait du skate", "style": "mascotte", "colors": 3,
        "user_id": "p1", "count": 3,
    })
    assert r.status_code == 202, r.text
    ids = r.json()["job_ids"]
    assert len(ids) == 3 and r.json()["job_id"] == ids[0]

    results = [wait_for(client, job_id, "p1")["result"] for job_id in ids]
    assert sorted(res["flavour"] for res in results) == [0, 1, 2]
    assert len({res["prompt_used"] for res in results}) == 3
    assert len({res["seed"] for res in results}) == 3


def test_une_retouche_donne_trois_propositions_pour_une_seule_reprise(client):
    parent = create_design(client, "p2")
    r = client.post(f"/jobs/{parent}/refine", headers=HEADERS,
                    json={"instruction": "ajoute un casque", "user_id": "p2", "count": 3})
    assert r.status_code == 202, r.text
    assert len(r.json()["job_ids"]) == 3
    assert r.json()["refinements_left"] == 2
    datas = [wait_for(client, job_id, "p2") for job_id in r.json()["job_ids"]]
    assert all(d["status"] == "done" for d in datas)
    # Une seule description pour le lot : le traducteur n'est appelé qu'une fois.
    assert len({d["result"]["subject"] for d in datas}) == 1
