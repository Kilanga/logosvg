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
    # Un seul prompt : FLUX.2 lit les négations, et la sérigraphie interdit les
    # dégradés en toutes lettres. Le dessin seul, jamais le vêtement.
    assert "negative_used" not in data["result"]
    assert "no gradients" in data["result"]["prompt_used"]
    assert "do not draw the t-shirt" in data["result"]["prompt_used"]

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
    # Les dégradés sont l'intérêt de la machine : rien ne les interdit ici.
    assert "no gradients" not in result["prompt_used"]
    assert "smooth shading" in result["prompt_used"]
    # Le décor, lui, reste interdit quelle que soit la technique.
    assert "no scenery" in result["prompt_used"]

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


# ------------------------------------------------------------------ agrandissement
# Le DTF visé à 300 dpi : un modèle d'agrandissement dessine les pixels qui
# manquent. Le détourage, lui, reste fait à la taille du dessin.

def test_l_image_agrandie_porte_la_transparence_du_dessin():
    from io import BytesIO

    from PIL import Image

    from app.raster import rasterize
    from app.techniques import resolve

    png = _png_avec_blanc_interieur()
    agrandie = BytesIO()
    Image.open(BytesIO(png)).convert("RGB").resize((2048, 2048)).save(agrandie, format="PNG")

    sans = rasterize(png, resolve("dtf"), True, 20)
    avec = rasterize(png, resolve("dtf"), True, 20, agrandie.getvalue())

    assert sans["stats"]["model_upscale"] == 1.0
    assert avec["stats"]["model_upscale"] == 4.0
    # 2 048 px dessinés sur 20 cm : au-delà de 150 dpi, plus d'alerte de définition.
    assert avec["stats"]["source_dpi"] > sans["stats"]["source_dpi"]
    assert not any("adoucis" in w for w in avec["warnings"])
    # Le fond reste transparent, le disque opaque.
    fichier = Image.open(BytesIO(avec["png"]))
    assert fichier.getpixel((2, 2))[3] == 0
    assert fichier.getpixel((fichier.width // 2, fichier.height // 5))[3] == 255
    assert abs(avec["stats"]["opaque_share"] - sans["stats"]["opaque_share"]) < 0.02


def test_l_agrandissement_n_a_lieu_que_si_un_modele_est_configure(monkeypatch):
    import asyncio
    import dataclasses

    import app.jobs as jobs
    from app.techniques import resolve

    png = _png_avec_blanc_interieur()
    manager = jobs.JobManager(prompt_filter=None)

    sans = asyncio.run(manager._upscale(png, resolve("dtf"), 25))
    assert sans == (None, None)

    monkeypatch.setattr(jobs, "settings", dataclasses.replace(jobs.settings, upscale_model="x.pth"))
    agrandie, alerte = asyncio.run(manager._upscale(png, resolve("dtf"), 25))
    assert alerte is None
    from io import BytesIO

    from PIL import Image
    assert Image.open(BytesIO(agrandie)).width == 2953  # 25 cm à 300 dpi


# ------------------------------------------------------------------ FLUX.2 klein
# Le graphe n'est pas exécuté ici (pas de GPU) : on vérifie qu'il est cohérent —
# chaque lien pointe vers un nœud qui existe, et les réglages arrivent au bon endroit.

def _liens_valides(wf):
    for nid, node in wf.items():
        for value in node["inputs"].values():
            if isinstance(value, list) and len(value) == 2 and isinstance(value[1], int):
                assert value[0] in wf, f"le nœud {nid} pointe vers {value[0]}, absent"


def test_le_workflow_flux2_recoit_prompt_tirage_et_taille(monkeypatch):
    import dataclasses

    import app.generator as generator

    monkeypatch.setattr(generator, "settings", dataclasses.replace(
        generator.settings, image_size=1000, flux_steps=4, flux_cfg=1.0))
    gen = generator.ComfyUIGenerator()

    wf = gen._workflow("a fox", 42)
    _liens_valides(wf)
    assert wf["4"]["inputs"]["text"] == "a fox"
    # Distillé : pas de prompt négatif, le conditionnement négatif est mis à zéro.
    assert wf["5"]["class_type"] == "ConditioningZeroOut"
    assert wf["1"]["inputs"]["unet_name"] == "flux-2-klein-4b-fp8.safetensors"
    assert wf["8"]["inputs"]["noise_seed"] == 42
    assert wf["7"]["inputs"]["steps"] == 4 and wf["10"]["inputs"]["cfg"] == 1.0
    # 1 000 n'est pas un multiple de 16 : le latent serait refusé.
    assert wf["6"]["inputs"]["width"] == 1008 and wf["7"]["inputs"]["width"] == 1008


def test_la_retouche_flux2_part_de_l_image_avec_un_bruit_partiel():
    import app.generator as generator

    wf = generator.ComfyUIGenerator()._workflow_refine("a fox", 7, "tsia_x.png", 0.35, size=1536)
    _liens_valides(wf)
    assert wf["14"]["inputs"]["image"] == "tsia_x.png"
    assert wf["17"]["inputs"]["denoise"] == 0.35
    assert wf["11"]["inputs"]["sigmas"] == ["17", 1]  # la fin du planning seulement
    assert wf["11"]["inputs"]["latent_image"] == ["16", 0]  # l'image encodée
    assert wf["15"]["inputs"]["width"] == 1536


def test_seul_flux2_reste_et_le_mock_sert_aux_tests(monkeypatch):
    import dataclasses
    from pathlib import Path

    import app.generator as generator

    monkeypatch.setattr(generator, "settings", dataclasses.replace(generator.settings, generator_mode="comfyui"))
    assert type(generator.get_generator()) is generator.ComfyUIGenerator
    workflows = {p.name for p in (Path(generator.__file__).parent.parent / "workflows").glob("*.json")}
    assert workflows == {"flux2_klein.json", "flux2_klein_img2img.json", "upscale_model.json"}


# ------------------------------------------------------------------ prompts
# Les deux défauts vus à la comparaison du 06/10 : le t-shirt dessiné, et le
# texte traduit (« FÊTE 2026 » devenu « FESTIVAL 2026 »).

def test_le_prompt_demande_le_dessin_seul_et_le_texte_a_la_lettre():
    from app.prompt_builder import build_prompt

    prompt = build_prompt('a village party with the text "FÊTE 2026"', "illustration", 3, "screen_printing")
    assert '"FÊTE 2026"' in prompt
    assert "letter for letter" in prompt
    assert "do not draw the t-shirt" in prompt
    assert "exactly 3 flat colors" in prompt


def test_les_trois_propositions_ont_des_registres_differents():
    from app.prompt_builder import build_prompt, flavour_count

    prompts = {build_prompt("a fox", "mascotte", 3, "screen_printing", i) for i in range(flavour_count())}
    assert len(prompts) == 3


def test_le_texte_entre_guillemets_ne_passe_pas_par_le_traducteur():
    from app.translate import protect, restore

    protected, saved = protect("Fête du village avec « FÊTE 2026 » et \"Les Lions\"")
    assert "FÊTE" not in protected and "Lions" not in protected
    assert saved == ["FÊTE 2026", "Les Lions"]
    # Le traducteur garde les repères : le texte revient à la lettre.
    assert restore("Village party with [[T1]] and [[T2]]", saved) == 'Village party with "FÊTE 2026" and "Les Lions"'
    # Il en perd un : le texte n'est pas perdu pour autant.
    assert '"Les Lions"' in restore("Village party with [[T1]]", saved)
