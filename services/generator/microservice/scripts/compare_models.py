"""Compare les modèles d'image sur les mêmes demandes, et produit une planche HTML.

À lancer sur la machine à GPU, ComfyUI démarré, depuis le dossier du microservice :

    .venv\\Scripts\\python.exe scripts\\compare_models.py --out C:\\tshirt-ia\\comparaison

Pour chaque demande, chaque modèle dessine avec le même tirage et le même prompt
(traduit par Ollama s'il répond, comme en production). Les demandes en
sérigraphie sont aussi vectorisées : le nombre de formes et d'encres du SVG dit
mieux qu'une image si le dessin est imprimable. La planche, `index.html`,
montre tout côte à côte avec les temps.

Le service n'est pas appelé : le script parle directement à ComfyUI. Il peut
donc tourner pendant que le service est arrêté — mais pas pendant qu'il génère,
la carte ne se partage pas bien.
"""
import argparse
import asyncio
import dataclasses
import html
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

import app.generator as generator  # noqa: E402
from app.config import settings  # noqa: E402
from app.prompt_builder import build_prompts  # noqa: E402
from app.techniques import resolve  # noqa: E402
from app.translate import to_english  # noqa: E402
from app.vectorizer import vectorize  # noqa: E402

# Les demandes des séries d'essais du 27/09, plus deux qui testent le texte : un
# club ou un événement veut souvent son nom sur le t-shirt, et c'est là que les
# modèles récents se distinguent le plus de SDXL.
DEMANDES = [
    ("renard-skate", "Un renard qui fait du skate, style rétro", "mascotte", "screen_printing", 3),
    ("phare", "Un phare breton sous les étoiles", "illustration", "screen_printing", 3),
    ("badge-trail", "Badge pour un trail en montagne", "badge", "screen_printing", 2),
    ("chat-pirate", "Un chat pirate avec un cache-œil", "mascotte", "screen_printing", 4),
    ("cafe-minimal", "Logo minimaliste pour un café", "logo", "screen_printing", 1),
    ("poulpe-guitare", "Un poulpe qui joue de la guitare", "illustration", "dtf", None),
    ("moto-vintage", "Une moto vintage dans un coucher de soleil", "illustration", "dtf", None),
    ("texte-club", "Logo du club de rugby « Les Lions de Vannes » avec le texte LES LIONS",
     "badge", "screen_printing", 2),
    ("texte-evenement", "T-shirt pour la fête du village avec le texte « FÊTE 2026 »",
     "illustration", "dtf", None),
]

MODELES = {
    "sdxl": {"label": "SDXL (actuel)", "image_model": "sdxl"},
    "klein-base": {"label": "FLUX.2 klein 4B base", "image_model": "flux2_klein",
                   "flux_unet": "flux-2-klein-base-4b-fp8.safetensors", "flux_steps": 20, "flux_cfg": 5.0},
    "klein-distille": {"label": "FLUX.2 klein 4B distillé", "image_model": "flux2_klein",
                       "flux_unet": "flux-2-klein-4b-fp8.safetensors", "flux_steps": 4, "flux_cfg": 1.0},
}

SEED = 20261006


def generateur_pour(cle: str, mock: bool = False):
    """Le générateur d'un modèle, avec ses réglages, sans toucher au .env."""
    reglages = {k: v for k, v in MODELES[cle].items() if k != "label"}
    mode = "mock" if mock else "comfyui"
    generator.settings = dataclasses.replace(settings, generator_mode=mode, **reglages)
    return generator.get_generator()


async def une_demande(gen, demande, dossier: Path) -> dict:
    slug, texte, style, technique, couleurs = demande
    profil = resolve(technique)
    couleurs = profil.clamp_colors(couleurs)
    sujet = await to_english(texte)
    positif, negatif = build_prompts(sujet, style, couleurs, profil.key)

    debut = time.monotonic()
    try:
        png = await gen.generate(positif, negatif, SEED, couleurs)
    except generator.GenerationError as exc:
        return {"erreur": str(exc), "sujet": sujet}
    duree = time.monotonic() - debut

    (dossier / f"{slug}.png").write_bytes(png)
    info = {"image": f"{dossier.name}/{slug}.png", "duree": duree, "sujet": sujet}
    if profil.family == "vector":
        out = vectorize(png, couleurs, True, settings.max_paths_warning, profil.key)
        (dossier / f"{slug}.svg").write_text(out["svg"], encoding="utf-8")
        info.update(formes=out["stats"]["paths"], encres=out["inks"], svg=f"{dossier.name}/{slug}.svg")
    return info


def cellule(info: dict) -> str:
    if "erreur" in info:
        return f'<td class="ko">{html.escape(info["erreur"])}</td>'
    lignes = [f'<img src="{info["image"]}" loading="lazy">', f'<b>{info["duree"]:.0f} s</b>']
    if "formes" in info:
        alerte = " ko" if info["formes"] > settings.max_paths_warning else ""
        lignes.append(f'<span class="{alerte}">{info["formes"]} formes, {info["encres"]} encres</span>')
        lignes.append(f'<a href="{info["svg"]}">SVG</a>')
    return "<td>" + "<br>".join(lignes) + "</td>"


def planche(resultats: dict, modeles: list) -> str:
    entete = "".join(f"<th>{html.escape(MODELES[m]['label'])}</th>" for m in modeles)
    corps = []
    for demande in DEMANDES:
        slug, texte, style, technique, couleurs = demande
        sujet = next((resultats[m][slug].get("sujet") for m in modeles if slug in resultats[m]), "")
        titre = (f"<th class='demande'>{html.escape(texte)}<small>{technique} · {style}"
                 f"{f' · {couleurs} encres' if couleurs else ''}<br><i>{html.escape(sujet or '')}</i></small></th>")
        corps.append("<tr>" + titre + "".join(cellule(resultats[m].get(slug, {"erreur": "—"}))
                                              for m in modeles) + "</tr>")
    moyennes = []
    for m in modeles:
        durees = [r["duree"] for r in resultats[m].values() if "duree" in r]
        moyennes.append(f"<td><b>{sum(durees) / len(durees):.0f} s</b> en moyenne</td>" if durees else "<td>—</td>")
    return f"""<!doctype html><html lang="fr"><meta charset="utf-8">
<title>Comparaison des modèles — Prêt-à-tirer</title>
<style>
body{{font:14px system-ui,sans-serif;margin:24px;color:#1D2433;background:#F2F4F3}}
table{{border-collapse:collapse;background:#fff}}td,th{{border:1px solid #C8D0D4;padding:8px;vertical-align:top;text-align:center}}
th.demande{{text-align:left;max-width:220px}}small{{display:block;color:#505A67;font-weight:normal;margin-top:4px}}
img{{width:260px;height:260px;object-fit:contain;background:#fff}}.ko{{color:#B3261E;font-weight:600}}
</style>
<h1>Comparaison des modèles d'image</h1>
<p>Même tirage ({SEED}), même prompt, même vectorisation. Au-delà de {settings.max_paths_warning} formes,
le SVG est signalé lourd à l'atelier.</p>
<table><tr><th>Demande</th>{entete}</tr>{''.join(corps)}<tr><th>Temps</th>{''.join(moyennes)}</tr></table>
</html>"""


async def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--out", default=str(ROOT.parent / "comparaison"))
    parser.add_argument("--modeles", default=",".join(MODELES), help="ex. : sdxl,klein-base")
    parser.add_argument("--mock", action="store_true", help="essai à blanc, sans ComfyUI")
    args = parser.parse_args()

    sortie = Path(args.out)
    sortie.mkdir(parents=True, exist_ok=True)
    modeles = [m.strip() for m in args.modeles.split(",") if m.strip() in MODELES]
    resultats = {}
    for m in modeles:
        print(f"\n=== {MODELES[m]['label']} ===", flush=True)
        dossier = sortie / m
        dossier.mkdir(exist_ok=True)
        gen = generateur_pour(m, args.mock)
        # Un dessin jeté d'abord : le premier paie le chargement du modèle en
        # mémoire, souvent plus long que tout le reste. Sans lui, la comparaison
        # des temps mesurerait le disque.
        debut = time.monotonic()
        try:
            await gen.generate("a simple circle, flat vector", "", 1, 1)
            print(f"  chargement     {time.monotonic() - debut:.0f} s", flush=True)
        except generator.GenerationError as exc:
            print(f"  ÉCHEC du chargement : {exc}", flush=True)
            print("  Le modèle est-il installé ? Lance INSTALLER-MODELES.bat.", flush=True)
            continue
        resultats[m] = {}
        for demande in DEMANDES:
            info = await une_demande(gen, demande, dossier)
            resultats[m][demande[0]] = info
            etat = info.get("erreur") or f"{info['duree']:.0f} s" + (
                f", {info['formes']} formes" if "formes" in info else "")
            print(f"  {demande[0]:<16} {etat}", flush=True)

    faits = [m for m in modeles if m in resultats]
    (sortie / "index.html").write_text(planche(resultats, faits), encoding="utf-8")
    print(f"\nPlanche : {sortie / 'index.html'}")


if __name__ == "__main__":
    asyncio.run(main())
