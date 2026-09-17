# T-shirt IA — démo

Plateforme où le client décrit son design, l'IA le génère, et le site livre directement un **SVG prêt pour l'impression**.

```
Navigateur ──> WordPress (plugin tshirt-ia-designer)
                  │  appel serveur à serveur, clé API
                  ▼
              Tunnel Cloudflare
                  ▼
              Microservice FastAPI (127.0.0.1:5000)   ← machine d'hébergement
                  ├── ComfyUI + SDXL (127.0.0.1:8188)  génération
                  ├── Ollama (optionnel)               traduction FR → EN
                  └── vtracer                          vectorisation
```

## Contenu

| Dossier | Rôle |
|---|---|
| `microservice/` | API de génération + vectorisation, file d'attente, anti-abus, tests |
| `wordpress-plugin/tshirt-ia-designer/` | Page de création (shortcode), réglages, relais sécurisé vers le service |
| `infra/cloudflared/` | Configuration du tunnel |

## État d'avancement

| Élément | État |
|---|---|
| Pipeline API → file d'attente → vectorisation → fichiers | Fonctionne et testé (mode simulation) |
| Sécurité du service : clé API, limite de débit, filtre de prompts, isolation entre clients | Testé (6 tests automatisés) |
| Plugin WordPress | Syntaxe PHP validée, interface vérifiée avec un WordPress simulé. **Pas encore testé dans un vrai WordPress.** |
| Génération réelle via ComfyUI | Écrite, **pas encore testée** (nécessite la machine avec GPU) |
| WooCommerce / Dokan (commande, imprimeurs partenaires) | À faire, une fois le cœur validé |

## 1. Tester le microservice dès maintenant (n'importe quel PC)

Le mode `mock` remplace la génération d'image par un dessin simple. Tout le reste tourne pour de vrai.

Prérequis : Python 3.10 ou plus récent.

```powershell
cd microservice
.\scripts\install.ps1     # crée .venv et .env, affiche la clé API
.\scripts\test.ps1        # lance les tests
.\scripts\run.ps1         # démarre le service sur http://127.0.0.1:5000
```

Essai manuel (remplacer `TA_CLE`) :

```powershell
$h = @{ "X-API-Key" = "TA_CLE" }
$body = '{"prompt":"un renard qui fait du skate","style":"mascotte","colors":3,"user_id":"test"}'
$job = Invoke-RestMethod -Method Post -Uri http://127.0.0.1:5000/generate -Headers $h -Body $body -ContentType "application/json"
Start-Sleep 3
Invoke-RestMethod -Uri "http://127.0.0.1:5000/jobs/$($job.job_id)?user_id=test" -Headers $h
Invoke-WebRequest -Uri "http://127.0.0.1:5000/jobs/$($job.job_id)/design.svg?user_id=test" -Headers $h -OutFile design.svg
```

### API

| Méthode | Route | Rôle |
|---|---|---|
| `GET` | `/health` | Vérifie que le service répond (sans clé) |
| `POST` | `/generate` | Lance une création, renvoie `job_id` (202) |
| `GET` | `/jobs/{id}?user_id=` | État : `queued`, `running`, `done`, `error` + palette, nombre d'encres, alertes |
| `GET` | `/jobs/{id}/design.svg?user_id=` | Le design vectorisé |
| `GET` | `/jobs/{id}/source.png?user_id=` | L'image brute générée, pour la comparaison |

## 2. Installer le plugin WordPress

1. Zipper le dossier `wordpress-plugin/tshirt-ia-designer`, puis *Extensions > Ajouter > Téléverser*.
2. *Réglages > T-shirt IA* : adresse du service, clé API, quota journalier.
3. Créer une page contenant `[tshirt_ia_designer]`.

Pour les premiers essais, **LocalWP** (gratuit) évite les surprises d'un hébergeur gratuit. Sur InfinityFree, vérifiez tôt que le site peut appeler une adresse externe : certains hébergeurs gratuits limitent les requêtes sortantes.

Les secrets peuvent rester hors de la base de données, dans `wp-config.php` :

```php
define( 'TSIA_API_KEY', '...' );
define( 'TSIA_TURNSTILE_SECRET', '...' );
```

### Anti-robot (gratuit)

Cloudflare > Turnstile > ajouter un widget pour votre domaine, puis copier la clé de site et la clé secrète dans les réglages. Sans clé, la vérification est simplement désactivée.

## 3. Sur la machine d'hébergement (RTX 4070 Ti)

1. **ComfyUI** : version portable Windows depuis le dépôt GitHub officiel.
2. **Modèle** : `sd_xl_base_1.0.safetensors` dans `ComfyUI/models/checkpoints/`. SDXL tient confortablement dans 12 Go de VRAM.
3. Dans ComfyUI, charger `microservice/workflows/sdxl_flat.json` pour vérifier qu'il s'exécute (menu *Workflow > Open*, format API).
4. Dans `.env` : `GENERATOR_MODE=comfyui`.
5. **Optionnel, traduction** : `OLLAMA_URL=http://127.0.0.1:11434` et `ollama pull qwen2.5:3b`. Le modèle est déchargé après chaque traduction pour libérer la VRAM. Un modèle 7B ou 14B chargé en même temps que SDXL dépasserait les 12 Go.
6. **Tunnel** :
   - Sans domaine : `infra/cloudflared/quick-tunnel.ps1`. L'adresse change à chaque lancement, il faut la recopier dans WordPress.
   - Avec un domaine sur Cloudflare : `infra/cloudflared/config.example.yml`, adresse fixe.

Ordre de démarrage : ComfyUI → (Ollama) → `run.ps1` → tunnel.

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
- Le navigateur ne voit jamais la clé API : WordPress relaie les appels.
- Seuls les clients connectés peuvent créer, avec nonce WordPress, Turnstile et quota journalier.
- Double limite de débit : dans WordPress et dans le service.
- Identifiant client pseudonymisé (hash) envoyé au service, pas l'ID WordPress.
- Un client ne peut consulter que ses propres créations.
- Le SVG est contrôlé (pas de script, pas de lien externe) avant d'être publié sur le site.
- Filtre de marques et de contenus, appliqué avant et après traduction.

## Points à traiter ensuite

- **File d'attente en mémoire** : un redémarrage du service perd les créations en cours. Suffisant pour une démo.
- **RGPD** : les fichiers copiés dans `wp-content/uploads/tsia/` ne sont pas purgés automatiquement. Définir une durée de conservation et une tâche de nettoyage avant l'ouverture au public.
- **Filtre de prompts** : une liste de mots est contournable. Pour la production, ajouter une modération par modèle.
- **Qualité d'impression** : valider sur de vrais designs SDXL et ajuster `filter_speckle` et le flou médian dans `app/vectorizer.py`.
- **Intégration commerce** : rattacher le SVG à un produit WooCommerce, puis l'envoyer à l'imprimeur choisi (Dokan).
