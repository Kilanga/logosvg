# Brancher le moteur de génération

Ce document dit ce que l'application Rails attend du service de génération, et
ce qui cassera si le service s'en écarte. Il est écrit pour la personne qui
développe ou branche le moteur — pas pour un lecteur du cahier des charges.

L'application ne sait rien du modèle, du GPU ni du workflow. Elle connaît
**une API HTTP** et quelques garanties. Tant que celles-ci tiennent, le moteur
peut changer entièrement.

---

## 1. Ce que l'application fait, et ne fait pas

| L'application fait | L'application ne fait pas |
| --- | --- |
| Appeler `POST /generate` depuis une tâche de fond | Appeler le service depuis une requête web |
| Sonder `GET /jobs/:id` toutes les 2 s, 5 min au plus | Attendre indéfiniment |
| Télécharger le fichier nommé par `result.print_file` | Deviner une extension |
| Contrôler tout SVG et tout PNG reçu | Faire confiance au service |
| Afficher les avertissements du service tels quels | Les réécrire |
| Compter le quota journalier du client | Compter le budget de reprises |

**Le budget de reprises est au service.** `refinements_left` fait foi à chaque
réponse ; Rails le recopie et ne le recalcule jamais. Si le service redémarre
et perd ses compteurs, les clients récupèrent des reprises — c'est une décision
ouverte assumée (voir `docs/SPEC.md`).

---

## 2. Le contrat HTTP

Base : `GENERATOR_URL`. Authentification : en-tête `X-API-Key`, sauf `/health`.
Délai réseau côté Rails : **20 s par appel**.

### `POST /generate` → `202`

```json
{
  "prompt": "un renard qui fait du skate",
  "style": "illustration|logo|mascotte|badge",
  "technique": "screen_printing",
  "colors": 3,
  "print_width_cm": 25,
  "remove_background": true,
  "user_id": "a1b2c3…",
  "seed": 123456
}
```

- `colors` est **absent** pour les techniques qui n'ont pas de plafond d'encres.
  Ne pas supposer qu'il est là.
- `print_width_cm` est toujours envoyé, même en vectoriel où il ne sert pas au
  fichier : il sert à la compatibilité atelier côté Rails.
- Réponse attendue : `job_id`, `status`, `position`, `refinements_left`.

### `GET /jobs/:id?user_id=…`

Réponse : `status`, `position`, `error`, `mode`, `parent_id`, `root_id`,
`refinements_left`, `result`.

`status` doit finir par valoir **`done`** ou **`error`**. Toute autre valeur est
traitée comme « encore en cours », et la demande expirera au bout de 5 minutes.

### `result`, quand `status == "done"`

```json
{
  "print_file": "design.svg",
  "palette": [{ "hex": "#1F5F7A" }],
  "inks": 3,
  "stats": { "paths": 268, "opaque_share": 0.32 },
  "warnings": ["…"],
  "prompt_used": "screen print separation artwork, a fox…",
  "subject": "a fox on a skateboard",
  "instruction": "…",
  "seed": 123456
}
```

**`print_file` est obligatoire.** C'est le nom que Rails demandera ensuite à
`GET /jobs/:id/<print_file>?user_id=…`. Sans lui, la génération échoue côté
Rails avec « le service a produit un fichier inutilisable ».

`stats` dépend de la famille :

- **vectorielle** : `paths`, `svg_bytes`, `opaque_share` ;
- **matricielle** : `width_px`, `height_px`, `print_width_cm`,
  `print_height_cm`, `dpi`, `upscale`, `source_dpi`, `net_width_cm`,
  `white_share`, `opaque_share`.

Ces champs sont affichés au client et recopiés dans la fiche technique envoyée
à l'atelier. Un champ manquant n'est pas une erreur — la ligne disparaît de
l'écran — mais un champ faux se retrouve sur un t-shirt.

### `POST /jobs/:id/refine` et `POST /jobs/:id/variants`

Créent des enfants de la même lignée (`root_id`). Rails crée une ligne par
`job_id` renvoyé. `variants` renvoie `job_ids` (un tableau) **et** `job_id`
(le premier) ; l'un ou l'autre suffit.

### `GET /health`

Sans clé. `{"status":"ok"}`. Interrogé par la page `/admin/etat`.

---

## 3. Les codes d'erreur, et ce qu'ils déclenchent

| Code | Ce que Rails en fait |
| --- | --- |
| `401` | Message générique au client, erreur dans les logs. C'est notre faute, pas la sienne. |
| `409` | Reprise demandée sur une version pas encore prête. |
| `422` | **Le `detail` est affiché tel quel au client.** Il doit être en français et compréhensible. |
| `503` | « Service injoignable, réessayez ». L'essai est rendu. |
| `404` | `user_id` ne correspond pas au job, ou le job a expiré. |

### ⚠ Les deux `429` ne se traitent pas pareil

```
429 + en-tête Retry-After   →  limite horaire. Le client réessaie plus tard.
429 + {"reason":"refine_budget"}  →  budget épuisé. Définitif. Ouvre le
                                     parcours graphiste payant.
```

C'est la distinction la plus importante du contrat. Si le service renvoie un
`429` sans l'un ou l'autre marqueur, Rails le traitera comme une limite horaire
et le client attendra pour rien.

---

## 4. Ce que le fichier produit doit respecter

Tout fichier passe par un contrôle avant d'être stocké. **Un fichier refusé
n'est jamais servi, et l'essai est rendu au client** — c'est donc une panne
silencieuse pour vous.

### SVG (`SvgInspector`)

Refusé si le fichier contient :

- une racine autre que `<svg>` ;
- `script`, `foreignObject`, `iframe`, `embed`, `object`, `use`, `image` ;
- un attribut `on*` ;
- une URL `javascript:`, `file:`, `//…` ou `http(s)://` — **y compris dans un
  `<style>` ou un attribut `style`** (`@import`, `url(http…)`) ;
- `<!ENTITY>` ou `<!DOCTYPE>` ;
- plus de 5 Mo.

Le nombre d'encres affiché à l'atelier est **recompté par Rails** à partir des
`fill` distincts, pas repris de `result.inks`. Si votre SVG utilise des
`<style>` ou des classes CSS plutôt que des attributs `fill`, le compte sera
faux. **Mettez la couleur dans un attribut `fill` sur chaque forme.**

### PNG (`RasterInspector`)

Refusé si : ce n'est pas un PNG (vérifié à la signature, pas à l'extension),
illisible, vide, ou au-delà de 25 Mo.

Avertissements (affichés, non bloquants) : absence de canal alpha, et
résolution effective sous **150 dpi à la largeur d'impression demandée**.

---

## 5. Vie privée : ce que le service ne doit jamais apprendre

`user_id` est un **HMAC-SHA256** de l'identifiant de compte, tronqué à 32
caractères, calculé avec `GENERATOR_USER_KEY`. Le service ne reçoit ni email,
ni nom, ni identifiant interne.

Conséquences pour vous :

- **Ne journalisez pas les prompts avec le `user_id` de façon durable** sans
  une durée de conservation décidée : c'est de la donnée personnelle indirecte.
- Si vous changez `GENERATOR_USER_KEY`, tous les pseudonymes changent et les
  budgets de reprises en cours sont perdus.
- Le service n'a aucun moyen de recontacter un utilisateur, et c'est voulu.

---

## 6. Le catalogue des techniques : `GET /techniques`

**Le service est la source de vérité.** Rails met le catalogue en cache une
heure, le rafraîchit toutes les 45 minutes par une tâche, et retombe sur
`config/print_techniques.yml` si le cache est froid.

Chaque entrée :

```json
{
  "key": "screen_printing",
  "label": "Sérigraphie",
  "family": "vector|raster",
  "max_colors": 6,
  "default_colors": 3,
  "gradients": false,
  "white_is_ink": true,
  "dpi": 300,
  "file_name": "design.svg"
}
```

- `max_colors` **absent ou null** = technique sans plafond d'encres. Rails
  n'enverra alors pas de `colors` et n'affichera pas le curseur.
- `family` décide de tout le reste de l'écran : encres et écrans en vectoriel,
  pixels et dpi en matriciel.
- **Renommer une `key` casse les fiches d'atelier existantes** : elles stockent
  la clé. Un ajout est sans risque, un renommage demande une migration côté
  Rails.

---

## 7. Le problème connu, à régler côté moteur

> SDXL dessine en 1 024 px de côté. Le fichier est livré à 300 dpi, mais au-delà
> d'environ 9 cm de large les pixels sont interpolés.

Une poitrine de t-shirt se demande à 25 cm. Sans agrandissement, **le fichier
est livré à environ 100 dpi réels et l'avertissement « définition faible »
s'affiche presque à chaque fois** — ce qui le rend inutile.

Deux façons de le régler, toutes deux **côté moteur, pas côté Rails** :

1. un nœud d'agrandissement dans le workflow ComfyUI, avant vectorisation ;
2. un `IMAGE_SIZE` plus élevé.

Renseignez alors honnêtement `source_dpi`, `net_width_cm` et `upscale` dans
`stats` : Rails s'en sert pour dire au client jusqu'où son visuel reste net.

---

## 8. Attentes de performance

- **5 minutes** entre la demande et `done`, au-delà l'essai est rendu.
- Sondage toutes les **2 secondes** par design en cours. Une file de 20 designs
  fait 10 requêtes par seconde sur `GET /jobs/:id` — prévoyez que cet endpoint
  soit bon marché.
- `position` est affiché au client ; s'il reste à zéro, personne ne sait où il
  en est.
- Les fichiers d'un job sont attendus disponibles **au moins une heure** après
  `done`. Passé ce délai, Rails traite un `404` comme « expiré sur la machine ».

---

## 9. Environnement

| Variable | Rôle |
| --- | --- |
| `GENERATOR_URL` | adresse du service |
| `GENERATOR_API_KEY` | valeur de l'en-tête `X-API-Key` |
| `GENERATOR_USER_KEY` | clé HMAC de pseudonymisation — **différente de la précédente** |

Côté service, la clé se lit sous `API_KEY` et doit valoir la même chose que
`GENERATOR_API_KEY`.

En développement, `bin/dev` lance le service en mode mock (`GENERATOR_MODE=mock`),
sans GPU. Les tests n'appellent jamais le réseau : tout est bouchonné par
WebMock.

---

## 10. Comment vérifier que votre service est compatible

Sans toucher à l'application :

```bash
# 1. Le catalogue répond et a la bonne forme
curl -H "X-API-Key: $GENERATOR_API_KEY" $GENERATOR_URL/techniques | jq '.techniques[0]'

# 2. Une génération aboutit
curl -X POST -H "X-API-Key: $GENERATOR_API_KEY" -H "Content-Type: application/json" \
  -d '{"prompt":"un renard","style":"mascotte","technique":"screen_printing",
       "colors":3,"print_width_cm":25,"remove_background":true,"user_id":"test"}' \
  $GENERATOR_URL/generate

# 3. Le fichier passe nos contrôles
curl -s "$GENERATOR_URL/jobs/<id>/design.svg?user_id=test" > /tmp/essai.svg
bin/rails runner 'r = SvgInspector.call(File.read("/tmp/essai.svg")); \
                  puts r.valid? ? "OK, #{r.inks} encres" : "REFUSÉ : #{r.reason}"'
```

La troisième commande est la plus utile : c'est exactement le contrôle qui
s'appliquera en production, et le seul qui puisse refuser un fichier
silencieusement.
