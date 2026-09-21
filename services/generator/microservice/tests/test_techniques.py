"""La technique d'impression décide du prompt, du fichier produit et des bornes."""
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


def create(client, user_id, **body):
    payload = {"prompt": "un renard qui fait du skate", "user_id": user_id, "seed": 7}
    payload.update(body)
    r = client.post("/generate", headers=HEADERS, json=payload)
    assert r.status_code == 202, r.text
    return wait_for(client, r.json()["job_id"], user_id), r.json()["job_id"]


def test_catalogue_publie_les_bornes(client):
    r = client.get("/techniques", headers=HEADERS)
    assert r.status_code == 200
    par_cle = {t["key"]: t for t in r.json()["techniques"]}
    assert set(par_cle) == {"screen_printing", "flex", "embroidery", "dtf", "dtg", "sublimation"}
    assert par_cle["flex"]["max_colors"] == 2
    assert par_cle["dtf"]["max_colors"] is None
    assert par_cle["screen_printing"]["file_name"] == "design.svg"
    assert par_cle["dtf"]["file_name"] == "print.png"
    # Le prompt reste une affaire du service : il ne sort pas dans le catalogue.
    assert "prompt_hint" not in par_cle["flex"]


def test_technique_inconnue_refusee(client):
    r = client.post("/generate", headers=HEADERS, json={
        "prompt": "un renard", "user_id": "t0", "technique": "lithographie",
    })
    assert r.status_code == 422


def test_serigraphie_produit_un_svg(client):
    data, job_id = create(client, "t1", technique="screen_printing", colors=3)
    assert data["status"] == "done", data
    assert data["result"]["output"] == "vector"
    assert data["result"]["print_file"] == "design.svg"
    assert "no gradients" in data["result"]["prompt_used"]

    svg = client.get(f"/jobs/{job_id}/design.svg", params={"user_id": "t1"}, headers=HEADERS)
    assert svg.status_code == 200 and "<svg" in svg.text
    absent = client.get(f"/jobs/{job_id}/print.png", params={"user_id": "t1"}, headers=HEADERS)
    assert absent.status_code == 404


def test_flex_borne_les_couleurs(client):
    data, _ = create(client, "t2", technique="flex", colors=6)
    assert data["status"] == "done", data
    # Deux couleurs maximum en découpe, quoi que demande le client.
    assert data["result"]["colors"] == 2
    assert "exactly 2 flat colors" in data["result"]["prompt_used"]
    assert data["result"]["inks"] <= 2


def test_dtf_produit_une_image_dimprimerie(client):
    data, job_id = create(client, "t3", technique="dtf", print_width_cm=24)
    assert data["status"] == "done", data
    result = data["result"]
    assert result["output"] == "raster"
    assert result["print_file"] == "print.png"
    # Les dégradés sont l'intérêt de la machine : le prompt ne les interdit plus.
    assert "no gradients" not in result["prompt_used"]
    assert "no shading" not in result["prompt_used"]

    stats = result["stats"]
    assert stats["dpi"] == 300
    # 24 cm à 300 dpi, à un pixel près.
    assert abs(stats["width_px"] - round(24 / 2.54 * 300)) <= 1
    assert stats["print_width_cm"] == 24.0

    png = client.get(f"/jobs/{job_id}/print.png", params={"user_id": "t3"}, headers=HEADERS)
    assert png.status_code == 200 and png.content[:4] == b"\x89PNG"
    absent = client.get(f"/jobs/{job_id}/design.svg", params={"user_id": "t3"}, headers=HEADERS)
    assert absent.status_code == 404


def _png_avec_blanc_interieur() -> bytes:
    """Un disque plein avec une zone blanche à l'intérieur, sur fond blanc."""
    from io import BytesIO

    from PIL import Image, ImageDraw

    img = Image.new("RGB", (512, 512), "white")
    draw = ImageDraw.Draw(img)
    draw.ellipse([56, 56, 456, 456], fill=(200, 40, 40))
    draw.rectangle([176, 176, 336, 336], fill="white")
    buf = BytesIO()
    img.save(buf, format="PNG")
    return buf.getvalue()


def test_le_blanc_interieur_depend_de_lencre_blanche():
    """Même dessin, deux machines : le DTF imprime le blanc, la sublimation non."""
    from app.raster import rasterize
    from app.techniques import resolve

    png = _png_avec_blanc_interieur()

    dtf = rasterize(png, resolve("dtf"), True, 20)
    assert dtf["stats"]["white_share"] == 0.0
    assert not any("blanc" in w for w in dtf["warnings"])

    subli = rasterize(png, resolve("sublimation"), True, 20)
    # Le carré blanc fait environ 10 % de l'image : il devient du textile, et le client
    # doit le savoir avant d'envoyer le fichier.
    assert subli["stats"]["white_share"] > 0.08
    assert any("n'imprime pas de blanc" in w for w in subli["warnings"])


def test_resolution_reelle_signalee():
    """Le fichier fait toujours 300 dpi ; ce qui compte est ce que le modèle a dessiné."""
    from app.raster import rasterize
    from app.techniques import resolve

    png = _png_avec_blanc_interieur()  # 512 px de côté

    large = rasterize(png, resolve("dtf"), True, 50)
    assert large["stats"]["dpi"] == 300
    # 512 px sur 50 cm : 26 dpi de dessin réel.
    assert large["stats"]["source_dpi"] < 150
    assert any("dpi" in w for w in large["warnings"])
    assert large["stats"]["net_width_cm"] == 9

    petit = rasterize(png, resolve("dtf"), True, 8)
    assert petit["stats"]["source_dpi"] >= 150
    assert not any("dpi" in w for w in petit["warnings"])


def test_la_reprise_garde_la_technique(client):
    data, job_id = create(client, "t5", technique="dtf", print_width_cm=20)
    assert data["status"] == "done", data

    r = client.post(f"/jobs/{job_id}/variants", headers=HEADERS,
                    json={"user_id": "t5", "count": 1})
    assert r.status_code == 202, r.text
    child = wait_for(client, r.json()["job_id"], "t5")
    assert child["status"] == "done", child
    assert child["result"]["technique"] == "dtf"
    assert child["result"]["print_file"] == "print.png"
    assert child["result"]["stats"]["print_width_cm"] == 20.0


def test_le_fichier_matriciel_est_net_a_la_taille_demandee(client):
    """Le §7 de docs/GENERATION.md : sans passe haute définition, chaque commande DTF
    repartait avec une alerte « définition faible » qui la rendait inexploitable."""
    data, _ = create(client, "hd1", technique="dtf", print_width_cm=25)
    assert data["status"] == "done", data

    stats = data["result"]["stats"]
    # Le fichier est livré à la résolution de la technique...
    assert stats["dpi"] == 300
    assert stats["width_px"] == 2953
    # ...et le dessin lui-même couvre vraiment cette taille : c'est cette valeur, et non
    # le dpi du fichier, que l'atelier regarde.
    assert stats["source_dpi"] >= 150, stats
    assert stats["net_width_cm"] >= 25, stats
    assert not any("dpi" in w for w in data["result"]["warnings"]), data["result"]["warnings"]


def test_les_encres_annoncees_sont_celles_que_l_atelier_comptera(client):
    """Le vectoriseur rééchantillonne la couleur de chaque forme : sans recalage, un
    design à trois encres sortait avec dix-neuf `fill` distincts, et l'application en
    comptait dix-neuf écrans."""
    import re

    data, job_id = create(client, "enc1", technique="screen_printing", colors=3)
    assert data["status"] == "done", data

    svg = client.get(f"/jobs/{job_id}/design.svg", params={"user_id": "enc1"},
                     headers=HEADERS).text
    fills = {m.lower() for m in re.findall(r'fill="(#[0-9a-fA-F]{6})"', svg)}
    palette = {entry["hex"].lower() for entry in data["result"]["palette"]}

    assert fills == palette, f"le SVG contient {len(fills)} encres, la palette en annonce {len(palette)}"
    assert data["result"]["inks"] == len(fills)
    assert len(fills) <= 3
