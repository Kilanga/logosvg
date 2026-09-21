# Prêt-à-tirer — service de génération

Le client décrit son design, l'IA le génère en aplats, le service le vectorise,
et l'atelier reçoit un **SVG prêt pour l'impression**.

Ce dossier ne contient que le **moteur de génération**. L'application, les
comptes, l'annuaire des imprimeurs et les demandes d'impression sont dans
l'application Rails, à la racine du dépôt.

```
Navigateur ──> Application Rails (jobs de fond)
                  │  appel serveur à serveur, clé API
                  ▼
              Tunnel Cloudflare
                  ▼
              Microservice FastAPI (127.0.0.1:5000)   ← machine de génération
                  ├── ComfyUI + SDXL (127.0.0.1:8188)  génération
                  ├── Ollama (optionnel)               traduction FR → EN
                  └── vtracer                          vectorisation
```

La clé d'API ne quitte jamais le serveur : c'est Rails qui relaie les appels,
depuis des tâches de fond uniquement. Le navigateur ne la voit jamais.

## Contenu

| Dossier | Rôle |
|---|---|
| `microservice/` | API de génération + vectorisation, file d'attente, anti-abus, tests |
| `infra/cloudflared/` | Configuration du tunnel |

## État d'avancement

| Élément | État |
|---|---|
| Pipeline API → file d'attente → vectorisation → fichiers | Fonctionne et testé (mode simulation) |
| Sécurité du service : clé API, limite de débit, filtre de prompts, isolation entre clients | Testé |
| Génération réelle via ComfyUI | Écrite, **pas encore testée** (nécessite la machine avec GPU) |
| Application Rails | En construction, voir `docs/SPEC.md` |

## 1. Tester le microservice (n'importe quel PC)

Le mode `mock` remplace la génération d'image par un dessin simple. Tout le
reste — file d'attente, vectorisation, filtre de prompts, limite de débit —
tourne pour de vrai.

Prérequis : Python 3.10 ou plus récent. **Éviter Python 3.14** : `vtracer`
0.6.15 y publie une roue qui s'importe sans erreur puis provoque une faute de
segmentation au premier appel. Python 3.13 fonctionne.

```bash
cd microservice
python3.13 -m venv .venv
.venv/bin/pip install -r requirements-dev.txt
.venv/bin/python -m pytest -q      # lance les tests
cp .env.example .env               # puis renseigner API_KEY
.venv/bin/python -m uvicorn app.main:app --host 127.0.0.1 --port 5000
```

Sous Windows, les scripts PowerShell équivalents sont dans `microservice/scripts/`.

Depuis la racine du dépôt, `bin/dev` lance le service en mode mock en même temps
que l'application Rails, et lui transmet la clé du `.env` racine.

Essai manuel :

```bash
KEY="votre-cle"
JOB=$(curl -s -X POST http://127.0.0.1:5000/generate \
  -H "X-API-Key: $KEY" -H 'Content-Type: application/json' \
  -d '{"prompt":"un renard qui fait du skate","style":"mascotte","colors":3,"user_id":"test"}' \
  | sed -n 's/.*"job_id":"\([a-f0-9]*\)".*/\1/p')
sleep 5
curl -s "http://127.0.0.1:5000/jobs/$JOB?user_id=test" -H "X-API-Key: $KEY"
curl -s "http://127.0.0.1:5000/jobs/$JOB/design.svg?user_id=test" -H "X-API-Key: $KEY" -o design.svg
```

### API

| Méthode | Route | Rôle |
|---|---|---|
| `GET` | `/health` | Vérifie que le service répond (sans clé) |
| `POST` | `/generate` | Lance une création, renvoie `job_id` (202) |
| `GET` | `/jobs/{id}?user_id=` | État : `queued`, `running`, `done`, `error` + palette, nombre d'encres, alertes |
| `GET` | `/jobs/{id}/design.svg?user_id=` | Le design vectorisé |
| `GET` | `/jobs/{id}/source.png?user_id=` | L'image brute générée, pour la comparaison |

Le contrat complet, côté Rails, est décrit dans `docs/SPEC.md`, section
« Intégration du microservice ».

## 2. Sur la machine de génération (RTX 4070 Ti)

1. **ComfyUI** : version portable Windows depuis le dépôt GitHub officiel.
2. **Modèle** : `sd_xl_base_1.0.safetensors` dans `ComfyUI/models/checkpoints/`.
   SDXL tient confortablement dans 12 Go de VRAM.
3. Dans ComfyUI, charger `microservice/workflows/sdxl_flat.json` pour vérifier
   qu'il s'exécute (menu *Workflow > Open*, format API).
4. Dans `.env` : `GENERATOR_MODE=comfyui`.
5. **Optionnel, traduction** : `OLLAMA_URL=http://127.0.0.1:11434` et
   `ollama pull qwen2.5:3b`. Le modèle est déchargé après chaque traduction pour
   libérer la VRAM. Un modèle 7B ou 14B chargé en même temps que SDXL
   dépasserait les 12 Go.
6. **Tunnel** :
   - Sans domaine : `infra/cloudflared/quick-tunnel.ps1`. L'adresse change à
     chaque lancement, il faut la recopier dans `GENERATOR_URL` côté Rails.
   - Avec un domaine sur Cloudflare : `infra/cloudflared/config.example.yml`,
     adresse fixe.

Ordre de démarrage : ComfyUI → (Ollama) → le service → le tunnel.

## Réglages du service (`.env`)

| Variable | Défaut | Rôle |
|---|---|---|
| `RATE_LIMIT_COUNT` / `RATE_LIMIT_WINDOW_SECONDS` | 5 / 3600 | Créations max par client sur la période |
| `MAX_QUEUE` | 10 | Demandes en attente avant de refuser |
| `JOB_TTL_SECONDS` | 3600 | Durée de conservation des fichiers sur la machine |
| `MAX_PATHS_WARNING` | 400 | Au-delà, le client est prévenu que le design sera difficile à imprimer |
| `BLOCKLIST_FILE` | `blocklist.txt` | Marques et termes refusés |

## Sécurité en place

- Le service n'écoute que sur `127.0.0.1` : il n'est joignable que par le tunnel.
- Le navigateur ne voit jamais la clé API : Rails relaie les appels, depuis des
  tâches de fond.
- Double limite de débit : quota journalier dans Rails, limite horaire dans le
  service.
- Identifiant client pseudonymisé (HMAC) envoyé au service, jamais l'identifiant
  réel de l'utilisateur.
- Un client ne peut consulter que ses propres créations.
- Le SVG est contrôlé (pas de script, pas de lien externe) avant d'être publié.
- Filtre de marques et de contenus, appliqué avant et après traduction.

## Points à traiter ensuite

- **File d'attente en mémoire** : un redémarrage du service perd les créations en
  cours, et remet à zéro les compteurs de reprises. Suffisant pour une
  démonstration ; à déplacer côté Rails si cela devient un enjeu commercial.
- **Filtre de prompts** : une liste de mots est contournable. Pour la production,
  ajouter une modération par modèle.
- **Qualité d'impression** : valider sur de vrais designs SDXL et ajuster
  `filter_speckle` et le flou médian dans `app/vectorizer.py`.
