# CLAUDE.md — Prêt-à-tirer

Guide de travail pour Claude Code sur ce dépôt. Le cahier des charges fait foi :
[docs/SPEC.md](docs/SPEC.md). Ce fichier en résume les règles opérationnelles et
ne les remplace pas.

---

## 1. Règles de travail (rappel, non négociables)

1. **Lire `docs/SPEC.md` en entier** avant d'écrire du code.
2. **Suivre le « Plan de construction » étape par étape.** À la fin de chaque
   étape : `bin/rails test` vert, tests système verts, `rubocop` propre,
   `brakeman` propre. Puis **s'arrêter**, résumer ce qui est fait et ce qui
   reste, et **attendre la validation** de l'utilisateur avant l'étape suivante.
3. **Ne pas changer la stack** décidée (§3). **Aucune gem hors liste** sans
   expliquer pourquoi et obtenir un accord explicite.
4. **Ambigu, contradictoire ou « Décision ouverte » → poser la question**,
   ne pas deviner. En attendant, utiliser une valeur de configuration
   clairement marquée (§8) — jamais une constante enfouie dans le code.
5. **Ne pas réécrire le microservice** de `services/generator/`. On consomme son
   API telle quelle : mock en développement, WebMock en test. Il n'évolue que
   par des correctifs fournis par l'utilisateur, jamais à notre initiative.
6. **Branche puis pull request, jamais de push sur `main`.** Commits atomiques,
   messages en français.
7. **Interface en français** (fichiers de locale). **Code, tables, modèles,
   colonnes, noms de classes et commentaires en anglais.**
8. **Aucun secret en dur, jamais dans le dépôt** : credentials Rails chiffrés ou
   variables d'environnement.
9. **Chaque machine à états est testée transition par transition**, y compris
   les transitions interdites (`refute` sur `may_xxx?` et sur l'appel du
   `xxx!` qui doit lever `AASM::InvalidTransition`).
10. **Chaque action de contrôleur passe par une policy Pundit** ; chaque requête
    est limitée aux données de l'utilisateur connecté (`policy_scope`).
    `verify_authorized` et `verify_policy_scoped` actifs partout.
11. **Reprendre les tokens visuels et la structure des écrans** de la section
    « Écrans et routes » du cahier des charges.

Qualité attendue : code propre, interfaces soignées et singulières — pas un
gabarit générique. Voir §7.

---

## 2. Le projet en une page

Plateforme vendue aux **imprimeurs textiles** par abonnement. Leurs clients
décrivent une idée, une IA génère un visuel **en aplats** limité aux couleurs
que l'atelier sait imprimer, le service le **vectorise**, et l'atelier reçoit par
email une demande d'impression complète (SVG, palette d'encres, textile,
emplacement, tailles, quantités). Le devis se fait **hors plateforme**.

Option payante : la **vérification par un graphiste** (revue), avec paiement
Stripe et reversement au graphiste via Connect.

Quatre rôles sur un seul modèle `User` : `client`, `printer`, `designer`,
`admin` — un rôle et un seul par utilisateur.

| Rôle      | Espace       |
| --------- | ------------ |
| Client    | `/mon-espace` |
| Imprimeur | `/atelier`    |
| Graphiste | `/studio`     |
| Admin     | `/admin`      |

---

## 3. Stack (figée)

| Besoin            | Choix                                                              |
| ----------------- | ------------------------------------------------------------------ |
| Langage / cadre   | Ruby ≥ 3.3, Rails 8.x, monolithe Hotwire                            |
| Base de données   | PostgreSQL 16 (`jsonb`, tableaux)                                   |
| Interface         | Hotwire (Turbo, Stimulus), **importmap**, `tailwindcss-rails`       |
| Authentification  | générateur d'authentification Rails 8, rôle en `enum` sur `User`    |
| Autorisations     | `pundit`                                                            |
| Machines à états  | `aasm`                                                              |
| Fond / cache / ws | Solid Queue, Solid Cache, Solid Cable                               |
| Fichiers          | Active Storage (disque en dev, S3-compatible ensuite)               |
| Paiements         | `stripe` (Checkout, Billing, Portal, Connect Express, webhooks)     |
| Géocodage         | `geocoder` + API Adresse (data.gouv.fr)                             |
| Carte             | Leaflet via importmap, tuiles OSM, **attribution affichée**         |
| QR code           | `rqrcode` (SVG et PNG)                                              |
| Images            | `image_processing` + libvips (filigrane des PNG téléchargés)        |
| SVG               | `nokogiri` (contrôle de sécurité + comptage des encres)             |
| Anti-robot        | Cloudflare Turnstile + `TurnstileVerifier` maison                   |
| Emails            | Action Mailer ; `letter_opener_web` en dev ; production à décider   |
| Tests             | Minitest, fixtures, Capybara (système), `webmock`, faux client Stripe |
| Qualité           | `rubocop-rails-omakase`, `brakeman`, `bundler-audit`, GitHub Actions |
| Déploiement       | Kamal (plus tard) ; démo derrière un tunnel Cloudflare              |

**Interdit sans accord préalable** : toute autre gem, tout bundler JS (esbuild,
vite…), toute dépendance HTTP supplémentaire (`GeneratorClient` utilise
`Net::HTTP`), RSpec, FactoryBot.

---

## 4. Commandes utiles

```bash
bin/setup                      # install + préparation de la base
bin/dev                        # app + tailwind watch + Solid Queue + service mock
bin/dev -m all=1,generator=0   # idem, sans le mock : le vrai generateur tient deja le port 5000
bin/rails db:prepare
bin/rails db:seed

bin/rails test                 # unitaires + intégration
bin/rails test:system          # Capybara
bin/rails test test/models/design_test.rb:42

bin/rubocop -a                 # rubocop-rails-omakase
bin/brakeman --no-pager
bundle exec bundler-audit check --update

bin/rails jobs:work            # Solid Queue seul
bin/rails runner 'puts Rails.application.config.tshirt.to_h'   # config provisoire
```

Le microservice, seul, en mode mock :

```powershell
cd services/generator/microservice
.\scripts\install.ps1   # crée .venv et .env, affiche la clé API
.\scripts\run.ps1       # http://127.0.0.1:5000
```

Emails en développement : <http://localhost:3000/letter_opener>.

---

## 5. Conventions

### Code

- **Logique métier dans `app/services`** : un objet, une méthode `call`,
  `Result`-like explicite. Contrôleurs minces (récupérer, autoriser, déléguer,
  rendre).
- **Intégrations externes isolées** et seules à connaître le monde extérieur :
  `GeneratorClient`, `Payments::*`, `TurnstileVerifier`, `Geocoding`,
  `SvgInspector`, `PrinterCompatibility`.
- **Appels réseau uniquement depuis des jobs de fond**, jamais dans le cycle
  requête/réponse.
- **Montants en centimes** : colonnes `*_cents`, entiers, devise EUR. Jamais de
  flottant pour de l'argent.
- Fuseau `Europe/Paris`, locale par défaut `fr`.
- Identifiants publics non devinables pour `Design`, `Review`, `PrintRequest`
  (`to_param` dédié / UUID) — jamais l'id séquentiel dans une URL.

### Interface

- **Tout texte visible dans `config/locales/fr.yml`.** Aucune chaîne française
  dans une vue, un modèle, un mailer ou un contrôleur.
- Polices **auto-hébergées** dans `app/assets/fonts` : aucun appel à Google
  Fonts depuis le navigateur (RGPD).
- Cibles tactiles ≥ 44 px, focus visible, contraste ≥ 4,5:1.
- Un layout par espace (`public`, `client`, `printer`, `designer`, `admin`),
  chacun avec son espace de noms de contrôleurs.

### Tokens visuels

| Token       | Valeur                | Usage                                |
| ----------- | --------------------- | ------------------------------------ |
| `paper`     | `#F2F4F3`             | Fond des pages                       |
| `surface`   | `#FFFFFF`             | Panneaux et champs                   |
| `ink`       | `#1D2433`             | Texte, barre latérale des espaces pros |
| `muted`     | `#505A67`             | Texte secondaire                     |
| `line`      | `#C8D0D4`             | Bordures                             |
| `emulsion`  | `#1F5F7A`             | Action principale                    |
| `success`   | `#1E6B40` sur `#E4F2EA` | Compatibilité, validations         |
| `warning`   | `#6B4200` sur `#FFF3DC` | Alertes d'impression               |
| Titres      | Barlow Condensed 600–700 | Titres et chiffres                |
| Texte       | Figtree 400–700       | Corps et interface                   |

Fond des aperçus : trame fine, lignes `emulsion` à 8 % tous les 8 px — rappel de
l'écran de sérigraphie.

### Base de données

- Migration **réversible**.
- **Index sur toutes les clés étrangères** et sur toute colonne servant à
  filtrer ou trier.
- Contraintes au plus près des données (`null: false`, uniques, check).

### Tests

- Pour chaque étape : tests de **modèles**, de **policies**, de **services**, et
  **au moins un test système par parcours**.
- Fixtures Minitest, pas de FactoryBot.
- **Aucune requête N+1** sur les listes : `includes`, et `strict_loading` activé
  en développement pour le vérifier.
- Tout appel sortant est bouchonné par WebMock ; `WebMock.disable_net_connect!`.

---

## 6. Arborescence

```
app/
  controllers/          public/  client/  printer/  designer/  admin/  webhooks/
  services/             objets métier à .call
  services/payments/    intégration Stripe isolée
  policies/             Pundit, une par modèle
  jobs/                 Solid Queue
  javascript/controllers/  Stimulus
  assets/fonts/         Barlow Condensed, Figtree (auto-hébergées)
config/locales/fr.yml   tout le texte visible
docs/SPEC.md            cahier des charges — fait foi
services/generator/     microservice FastAPI livré — NE PAS MODIFIER
test/                   models  policies  services  system  integration
```

---

## 7. Exigence d'interface

Les écrans doivent avoir une identité propre, pas l'aspect d'un gabarit généré.
Concrètement, sur chaque écran :

- partir de la **structure décrite dans « Écrans et routes »**, pas d'une grille
  de cartes par défaut ;
- assumer le vocabulaire du métier : pots d'encre, écrans de sérigraphie, trame,
  gabarit de t-shirt, affiche comptoir ;
- typographie condensée pour les titres et les chiffres, hiérarchie marquée ;
- pas de dégradé décoratif, pas d'emoji en guise d'icône, pas d'ombre portée
  générique sur tout ;
- les états (chargement, vide, erreur) sont dessinés, pas laissés au navigateur.

---

## 8. Secrets et configuration

### Secrets — jamais dans le dépôt

`bin/rails credentials:edit` ou variables d'environnement. `.env` est ignoré par
git ; `.env.example` documente les clés sans valeur.

| Variable                    | Rôle                                        |
| --------------------------- | ------------------------------------------- |
| `GENERATOR_URL`             | adresse du microservice                     |
| `GENERATOR_API_KEY`         | en-tête `X-API-Key`                         |
| `GENERATOR_USER_KEY`        | clé HMAC de pseudonymisation du `user_id`   |
| `STRIPE_SECRET_KEY`         | API Stripe                                  |
| `STRIPE_PUBLISHABLE_KEY`    | Checkout côté navigateur                    |
| `STRIPE_WEBHOOK_SECRET`     | vérification de signature                   |
| `STRIPE_PRICE_LISTING`      | prix abonnement Référencement               |
| `STRIPE_PRICE_ATELIER_PLUS` | prix abonnement Atelier+                    |
| `TURNSTILE_SITE_KEY`        | widget anti-robot                           |
| `TURNSTILE_SECRET_KEY`      | vérification serveur                        |
| `DATABASE_URL`              | PostgreSQL                                  |

### Valeurs provisoires — décisions ouvertes

Elles vivent **uniquement** dans `config/settings.yml`, lues par
`Rails.application.config.tshirt`. Chaque entrée porte le marqueur
`DÉCISION OUVERTE` ; aucune ne doit être recopiée en dur ailleurs.

| Clé                                | Valeur provisoire | Question ouverte                      |
| ---------------------------------- | ----------------- | ------------------------------------- |
| `platform_name`                    | `Prêt-à-tirer`    | **décidé** — domaine `pretatirer.fr`  |
| `generation_quota_per_day`         | `5`               | confirmé par le cahier des charges     |
| `review_auto_accept_days`          | `7`               | validation automatique                 |
| `proposal_expiry_hours`            | `72`              | réponse à une proposition              |
| `designer_claim_timeout_hours`     | `12`              | graphiste choisi silencieux            |
| `print_request_reminder_hours`     | `48`              | relance atelier                        |
| `print_request_expiry_days`        | `5`               | expiration d'une demande               |
| `platform_fee_rate`                | `0.20`            | **taux de commission à fixer**         |
| `return_rate_alert_threshold`      | `0.25`            | **seuil d'alerte à fixer**             |
| `design_retention_days`            | `180`             | **durée de conservation à fixer**      |
| `print_request_anonymize_days`     | `365`             | **durée de conservation à fixer**      |
| `subscription_price_*`             | —                 | **prix des abonnements à fixer**       |
| `consent_text_version`             | `2026-09-v1`      | version du texte de consentement       |

Décisions déjà tranchées par le cahier des charges : le client télécharge
**le PNG filigrané, jamais le SVG** ; les prix des niveaux de revue sont fixés
par la plateforme (hypothèse à confirmer).

---

## 9. Microservice de génération — contrat

Base : `services/generator/microservice` (FastAPI, port 5000, `127.0.0.1`).
**Ne pas le modifier.** Authentification par en-tête `X-API-Key`.

| Appel                              | Entrée                                                                   | Sortie                                                       |
| ---------------------------------- | ------------------------------------------------------------------------ | ------------------------------------------------------------ |
| `POST /generate`                   | `prompt` (3–300), `style`, `colors` (1–6), `remove_background`, `user_id`, `seed?` | `202` : `job_id`, `status`, `position`, `refinements_left` |
| `POST /jobs/:id/refine`            | `instruction` (3–200), `user_id`                                          | `202` : `job_id`, `status`, `position`, `refinements_left`   |
| `POST /jobs/:id/variants`          | `user_id`, `count`                                                        | `202` : `job_ids`, `job_id`, `status`, `position`, `refinements_left` |
| `GET /jobs/:id?user_id=`           | —                                                                        | `status`, `position`, `error`, `mode`, `parent_id`, `root_id`, `refinements_left`, `result` |
| `GET /jobs/:id/design.svg?user_id=`| —                                                                        | le SVG                                                       |
| `GET /jobs/:id/source.png?user_id=`| —                                                                        | l'image brute                                                |
| `GET /health`                      | — (sans clé)                                                             | `{"status":"ok"}`                                            |

`result` contient `palette`, `inks`, `stats` (dont `paths` et `opaque_share`),
`warnings`, `prompt_used`, `subject`, `instruction`, `seed`.

Codes à traiter : **401** (configuration, message générique), **409** (reprise
demandée sur une version pas encore prête), **422** (terme interdit ou prompt
invalide — afficher le message du service), **503** (file pleine — proposer un
nouvel essai). Un `user_id` qui ne correspond pas au job renvoie **404**.

⚠ **Les deux 429 ne se traitent pas pareil.** Avec l'en-tête `Retry-After`,
c'est la limite horaire de générations : le client réessaie plus tard. Avec
`reason: "refine_budget"`, c'est le budget de reprises du design, définitif, qui
ouvre le parcours graphiste. `GeneratorClient` doit donc exposer **le corps JSON**
de la réponse, pas seulement le code HTTP.

**Reprises.** Un design `ready` ne se modifie pas : une retouche ou une variante
crée un enfant de la même lignée (`root_id`). Budget de trois reprises par
lignée, compté par le service ; `refinements_left` fait foi et n'est jamais
recalculé par Rails.

Règles côté Rails :

- `user_id` transmis = **HMAC-SHA256** de l'id utilisateur avec
  `GENERATOR_USER_KEY`, tronqué à 32 caractères (le service impose
  `^[A-Za-z0-9_-]{1,64}$`).
- `colors` transmis = `min(choix du client, max_colors sérigraphie de l'atelier)`.
- Délai réseau **20 s** par appel, `Net::HTTP`.
- `PollDesignJob` interroge toutes les **2 s**, **5 min** maximum.
- Une génération échouée **ne consomme pas** de quota.
- Chaque changement d'état diffuse un **Turbo Stream** vers la page du design.
- Tout SVG — généré ou déposé par un graphiste — passe par `SvgInspector` :
  racine `<svg>`, aucun `script`, `foreignObject`, attribut `on*`, URL
  `javascript:`, entité XML ni lien externe. Refus sinon.

---

## 10. Plan de construction — avancement

| Étape | Contenu                       | État                          |
| ----- | ----------------------------- | ----------------------------- |
| 0     | Socle                         | terminée                       |
| 1     | Comptes                       | terminée                       |
| 2     | Imprimeurs                    | terminée                       |
| 3     | Designs                       | terminée                       |
| 4     | Demandes d'impression         | terminée                       |
| 5     | Espace client                 | terminée                       |
| 6     | Abonnements                   | terminée                       |
| 7     | Graphistes                    | terminée                       |
| 8     | Revues                        | terminée                       |
| 9     | Administration                | terminée                       |
| 10    | Finitions                     | **terminée**, en attente de validation |

Le plan de construction est arrivé à son terme. Ce qui reste avant une mise en
production est listé en §8 (décisions ouvertes) et dans « Décisions ouvertes »
du cahier des charges : prix, taux de commission, durées de conservation,
validation juridique des pages légales, clés Stripe réelles, hébergement et
fournisseur d'emails.

---

## 11. Environnement de développement

Tout tourne dans **WSL2 / Ubuntu**, jamais côté Windows. Le dépôt vit dans le
**HOME de la distribution** (`~/logosvg`), sur ext4 — pas sous `/mnt/c`, où
chaque accès fichier traverse une passerelle et où le démarrage de Rails prend
plusieurs fois plus de temps.

**Une seule machine porte désormais les deux moitiés du projet** : l'application
dans WSL, et le moteur de génération (ComfyUI + SDXL + Ollama + le microservice)
côté Windows, sur le même poste. Il n'y a donc **ni tunnel ni réseau privé en
développement** : `GENERATOR_URL=http://127.0.0.1:5000` suffit.

Ce que cela impose, et qui se paie cher si on l'oublie : le microservice n'écoute
que sur `127.0.0.1` de Windows, et en mode réseau NAT — le défaut de WSL2 — une
distribution Linux **n'atteint pas** le `127.0.0.1` de son hôte. Il faut le mode
`mirrored`, dans `%USERPROFILE%\.wslconfig` :

```ini
[wsl2]
networkingMode=mirrored

[experimental]
hostAddressLoopback=true
```

puis `wsl --shutdown`. La tentation inverse — lier le service à `0.0.0.0` —
l'exposerait au réseau local alors qu'il tourne sur une machine personnelle :
c'est précisément ce que l'architecture refuse.

Corollaire au lancement : `bin/dev` démarre un service de substitution sur le
port 5000, qui **entre en collision** avec le vrai. Sur cette machine, lancer
`bin/dev -m all=1,generator=0`.

| Outil            | Version installée              | Provenance                    |
| ---------------- | ------------------------------ | ----------------------------- |
| Ruby             | ≥ 3.2 (3.3 visé)               | paquet Ubuntu                 |
| Rails            | 8.1.3.1                        | `bundle install`              |
| Bundler          | 4.0.21 (`BUNDLED WITH`)        | `gem install`                 |
| PostgreSQL       | 16                             | paquet Ubuntu                 |
| libvips          | ≥ 8.15 + librsvg               | paquet Ubuntu                 |
| Chrome/Chromium  | présent                        | tests système                 |
| Python           | 3.12 ou 3.13                   | service de substitution seul  |

Le Gemfile ne fixe pas de version de Ruby et `Gemfile.lock` n'a pas de section
`RUBY VERSION` : toute version ≥ 3.2 convient. `.ruby-version` (3.3.8) n'est
qu'une indication. **libvips sans librsvg** est le piège silencieux : le SVG se
stocke très bien, et seuls les aperçus rasterisés manquent.

**Node n'est pas installé et n'est pas nécessaire** : `tailwindcss-rails`
embarque le binaire Tailwind autonome, et les modules JS passent par importmap.

### Gems dans le HOME

Le Ruby d'Ubuntu installe ses gems dans `/var/lib/gems`, qui appartient à root.
Les gems du projet vont donc dans `~/.gem/ruby/3.3.0`, ce qui a un avantage
secondaire : elles vivent sur **ext4**, pas sur `/mnt/c`, et le démarrage de
Rails s'en trouve nettement accéléré.

`~/.bashrc` et `~/.profile` contiennent :

```bash
export GEM_HOME="$HOME/.gem/ruby/3.3.0"
export PATH="$GEM_HOME/bin:$PATH"
```

⚠ Ne **jamais** définir `GEM_PATH` en plus : cela masque les répertoires par
défaut de Debian où vivent les gems groupées (minitest, rdoc…), et Rails refuse
alors de démarrer.

### Lancer une commande

Depuis PowerShell, en passant par un fichier — PowerShell dévore les `$` d'une
commande bash passée en ligne :

```powershell
wsl -d Ubuntu -u arnaud -- bash /mnt/c/.../script.sh
```

`wsl -u root` fonctionne sans mot de passe : c'est la voie pour installer un
paquet, `sudo` réclamant un mot de passe interactif.

### Bases de données

Quatre bases en développement, comme en production : `primary`, `cache`,
`queue`, `cable`. Ce n'est pas du zèle — `bin/dev` lance le serveur web et le
worker dans deux processus distincts, et l'adaptateur `async` d'Action Cable ne
traverse pas cette frontière : un Turbo Stream émis depuis un job n'arriverait
jamais au navigateur. Solid Cable, lui, le fait.

En test, une seule base : les tests utilisent l'adaptateur de job `:test`, le
cache `:null_store` et l'adaptateur cable `test`.

Connexion par socket Unix avec le rôle système de l'utilisateur : aucun mot de
passe à stocker nulle part. WSL n'a pas toujours `systemd`, donc le cluster ne
démarre pas seul — `service postgresql start` à l'ouverture d'un terminal.

### Pièges rencontrés, à ne pas réintroduire

**`json` est épinglé sous la 3.0 dans le Gemfile.** `activesupport 8.1.3.1`
appelle `JSON.parse(json, options)` avec deux arguments positionnels ; `json 3.0`
a rendu toutes les options nominatives. `ActiveSupport::JSON.decode` lève donc
`ArgumentError`, ce qui casse **toute colonne sérialisée en JSON** — dont les
arguments de job de Solid Queue, qui part alors en boucle de redémarrage sous
`bin/dev`. Retirer l'épingle seulement quand ActiveSupport gère `json` 3.

**Ne pas passer de commande bash en ligne depuis PowerShell.** PowerShell
expanse les `$` avant WSL : `$HOME` devient `C:\Users\ARNAU`, les antislashs
sautent, et Bundler reçoit un chemin absurde contenant `:`. Toujours écrire un
`.sh` et l'exécuter.

**La CSP a besoin d'un nonce, sans quoi elle coupe tout le JavaScript.**
L'importmap et Turbo sont servis en balises `<script>` en ligne, que
`script-src 'self'` bloque. Sans
`content_security_policy_nonce_generator`, l'application perd Stimulus et Turbo
**pendant que toutes les pages continuent de s'afficher** — la panne la plus
facile à ne pas voir. Configuré dans `config/initializers/content_security_policy.rb`.

**`Printer` est le modèle, `Workshop` est l'espace.** Une classe de modèle et un
module d'espace de noms de contrôleurs ne peuvent pas porter le même nom : Ruby
lève `TypeError: Printer is not a module`. D'où `Workshop::ProfilesController`
pour `/atelier`, alors que le rôle sur `User` reste `printer`.

**Les tests système attendent, ils ne supposent pas.** Un helper de connexion
qui rend la main avant la fin de la redirection fait échouer le test bien plus
loin, sur un symptôme sans rapport. Terminer par une assertion qui attend
(`assert_no_current_path new_session_path`).

**Le virtualenv du microservice est sur Python 3.13, pas 3.14.** `vtracer`
publie une roue `cp314` qui s'importe sans broncher puis **segfault au premier
appel** — y compris sur une image de 64×64 dans le thread principal. Python 3.13
vient du dépôt deadsnakes. `bin/generator` choisit l'interpréteur le plus récent
qui fonctionne. Cela ne concerne que le **mode mock local** : la génération et la
vectorisation réelles tournent sur la machine GPU, avec son propre environnement.

**`yes`, `no`, `on`, `off` doivent être entre guillemets dans un fichier YAML.**
Sans eux, YAML les lit comme des booléens : la clé de locale `yes:` devient
`true`, et l'écran affiche « Yes » au lieu de « Oui ».

**`format` est une clé réservée par I18n.** L'utiliser en interpolation lève
`reserved key :format used in …`. Nommer le paramètre autrement (`file_format`).

**Le catalogue des techniques vient du microservice, pas de la locale.** Les
libellés, familles et plafonds sont servis par `GET /techniques` et mis en cache
par `PrintTechniques` ; chaque atelier peut ensuite les habiller des siens. Ne
jamais recopier la liste des techniques dans `fr.yml` ni dans un enum Rails.
La lecture ne fait **jamais** d'appel réseau : un job rafraîchit le cache, un
cache froid retombe sur `config/print_techniques.yml`.

**Le texte rendu n'est pas le texte écrit.** Les titres sont en capitales via
`text-transform`, et un navigateur renvoie le texte tel qu'il est *rendu*. Dans
les tests système, comparer avec le helper `displayed(clé)` d'
`ApplicationSystemTestCase`, qui construit une expression régulière insensible à
la casse.

**libvips refuse le SVG tant qu'on ne le débloque pas.** `image_processing`
appelle `Vips.block_untrusted(true)` au chargement, ce qui coupe *tous* les
chargeurs que libvips juge non sûrs — dont rsvg. Or un design de sérigraphie
**est** un SVG, et la seule image qu'un client reçoit est un aperçu rastérisé :
laissé bloqué, aucun design vectoriel n'aurait d'aperçu, **en silence**, puisque
le fichier lui-même se stocke très bien. `config/initializers/vips.rb` débloque
le seul chargeur SVG ; tout le reste demeure refusé. Ce qui le rend acceptable,
c'est qu'aucun SVG n'atteint le moteur de rendu sans examen : `SvgInspector`
passe une première fois au stockage, et `DesignPreview` **repasse sur les octets
stockés** juste avant de rastériser.

**Une chaîne JSON dans une colonne `jsonb` est réencodée en chaîne.** Une fixture
écrite `palette: '[{"hex":"#1F5F7A"}]'` ne donne pas un tableau mais la *chaîne*
`"[{\"hex\"…}]"`, et la vue lève `undefined method 'each' for a String`. Écrire
les fixtures `jsonb` en vraies structures YAML.

**`t(".clé")` dans un bloc `render ... do` se résout contre le partiel.** Les
arguments du `render` sont évalués chez l'appelant, mais le corps du bloc est
rendu dans le contexte du partiel : dans `edit.html.erb`, un `t(".description_hint")`
placé à l'intérieur d'un `render "section" do` cherche
`workshop.profiles.section.description_hint`. Employer une clé absolue.

**`raise_on_missing_translations` est actif en test, exprès.** Sans lui, une clé
manquante rend une chaîne « translation missing » et l'échec survient bien plus
loin, méconnaissable — c'est ainsi qu'un doublon de clé de premier niveau dans
`fr.yml` s'est manifesté en `undefined method 'each'` au fond d'un partiel.

**Un doublon de clé YAML se cache aussi en profondeur.** Le cas s'est reproduit
avec deux `status:` sous `admin:`, que le contrôle des clés de premier niveau ne
voyait pas. `test/integration/locale_integrity_test.rb` lit désormais l'arbre
Psych brut — le seul endroit où les deux clés existent encore, le chargeur
normal ne gardant que la dernière — et échoue sur un doublon à n'importe quelle
profondeur.

**Une policy oubliée ferme un écran entier, sans rien dire.**
`ReviewPolicy#index?` n'autorisait que le client et le graphiste : la liste des
vérifications était inaccessible à l'administration, et la redirection Pundit
ressemblait à une page vide. Quand un espace gagne un écran déjà existant,
vérifier que `index?` connaît le nouveau rôle.

**L'unicité est le travail de l'index, pas d'une validation.** Une
`validates :uniqueness` lit la table puis écrit : deux livraisons de webhook
arrivant ensemble la passent toutes les deux, et surtout elle lève
`RecordInvalid` **avant** que l'index ait la moindre chance de dire non — le
`rescue ActiveRecord::RecordNotUnique` de `StripeEvent.claim` ne se déclenchait
donc jamais. Index unique seul, et `rescue RecordNotUnique`.

**Un scope et son équivalent d'instance doivent s'accorder.** `Printer.listed`
filtre l'annuaire, mais c'est `Printer#listed?` que la policy interroge pour la
page d'un atelier. Le premier mis à jour sans le second, une fiche disparaît de
l'annuaire mais reste lisible par quiconque a le lien.

**Les horodatages de migration ne peuvent pas être dans le futur.** Rails 8
refuse un fichier dont le nom dépasse l'heure courante : « Timestamp must be in
form YYYYMMDDHHMMSS, and less than … ». Ne pas les écrire à la main :
l'horloge de cette machine a déjà reculé en cours de session, et des migrations
déjà appliquées se sont retrouvées « dans le futur ». `bin/rails generate
migration` repart de la dernière migration existante et s'en sort tout seul.

**`form_with` ne devine `multipart` qu'à partir d'un `file_field` du form
builder.** Avec un `file_field_tag` nu, le formulaire reste urlencodé et **le
fichier ne quitte jamais le navigateur** — le serveur reçoit un paramètre vide
et répond « joignez un fichier ». Écrire `multipart: true` explicitement dès
qu'on n'utilise pas le builder.

**`def methode = expression if condition` ne fait pas ce qu'on croit.** Ruby lit
`(def methode = expression) if condition` : la condition est évaluée **dans le
corps de la classe**, pas dans la méthode. `def read! = update!(...) if
read_at.nil?` levait donc `NameError: undefined local variable read_at` au
chargement du modèle. Écrire la méthode en toutes lettres.

**Deux champs de même nom sur une page rendent les tests ambigus — et le
formulaire aussi.** L'écran d'une revue portait deux `message` et deux `body`
dans des formulaires différents. Capybara lève `Capybara::Ambiguous`, et un
navigateur remplit n'importe lequel. Donner un `id:` distinct à chacun.

**Un test qui compte des emails doit dire de quelle ligne il parle.** Les
balayages parcourent toutes les fixtures : `SweepReviewsJob` en notifiait
plusieurs, et `assert_emails 1` échouait sur des envois sans rapport. Neutraliser
les autres candidats dans le `setup`, et **vider la file** (`perform_enqueued_jobs`)
avant une assertion qui en contient un deuxième — sinon la livraison du premier
passage est comptée dans le second.

**Une validation de complétude appartient au moment où elle compte.** Le profil
graphiste se sauvegarde à moitié écrit — on rédige sa présentation en trois
fois — mais l'administration ne peut pas publier une page vide. D'où un contexte
`on: :activation`, interrogé par `ready_for_activation?`. Le réflexe de faire
passer l'enregistrement par l'état cible pour « déclencher les validations »,
puis de revenir en arrière avec `update_column`, rend l'objet publiquement
visible entre les deux et saute les callbacks.

**`assert_text` prend le *type* en second argument positionnel**, pas un message
d'échec. `assert_text shown(x), "mon message"` lève
« is not a valid type for a text query ». Et la valeur d'un champ n'est pas du
texte : c'est `assert_field with:` qu'il faut. **`assert_select` a le même
piège** : l'argument suivant le sélecteur sert de texte à comparer, si bien
qu'un message d'échec devient une assertion sur le contenu de la page.

**Un service qui construit des URL ne s'appelle pas sans requête.** La leçon a
resservi deux fois — `ClientDashboard`, puis `AccountExport`. Un service ne
reçoit pas la vue : soit le chemin se calcule dans un helper, soit on lui passe
l'hôte. Sinon il devient impossible à appeler depuis un job ou une console, et
impossible à tester sans fabriquer une requête.

**`strict_loading` est actif en développement, et il a raison.** `db/seeds.rb`
a échoué sur un `profil.user` paresseux. Charger avec `includes`, ne pas
contourner.

**Et il ne protège que le développement, où personne ne regarde.** Le réglage
n'existe qu'en développement : la suite de tests, elle, tourne sans. Un saut
paresseux oublié passe donc l'intégration continue et casse la page dans le
navigateur. C'est arrivé au pire endroit — `Current.user` déréférence la
session, Pundit le lit dès le premier `before_action`, et **toutes** les pages
authentifiées levaient `StrictLoadingViolationError`, sans qu'aucun des
750 tests ne bronche. `test/integration/strict_loading_test.rb` active
désormais le réglage et rejoue chaque écran d'accueil : la panne apparaît là.

**L'utilisateur courant n'est le point de départ d'aucun chargement.** Ni
`Current.user.printer`, ni `Current.user.designer_profile`, ni
`Current.user.sessions` : personne ne l'a préchargé, et le précharger dans la
lecture de session ferait payer à chaque page client des enregistrements que
seuls les professionnels possèdent. Chaque espace charge le sien dans son
`BaseController` (`current_printer`, `current_designer_profile`), avec les
associations que cet espace montre. Une policy, qui ne voit pas ces aides, fait
sa propre requête ou une sous-requête — jamais un saut depuis `user`.

**Et le filet posé sur les contrôleurs ne couvre pas les travaux de fond.** Le
même oubli s'est reproduit deux fois de suite après le correctif des
contrôleurs : dans `ApplicationCable::Connection`, qui relit la session pour son
compte hors du cycle d'une requête, puis dans toute la chaîne de génération, que
Solid Queue nourrit d'un `Design.find` nu. Un travail y est rendu **sans aucune
association**, et `design.user` — lu au fond de `GeneratorClient` pour le seul
pseudonyme RGPD — tuait la génération avant son premier appel HTTP. La réponse
n'est pas de précharger : c'est de ne demander que l'identifiant, qui est déjà
sur l'enregistrement (`design.user_id`). `test/channels/application_cable/connection_test.rb`
et `test/jobs/strict_loading_test.rb` rejouent ces chemins avec le réglage du
développement.

**Un travail qui lève laisse l'écran du client tourner pour toujours.** La file
enregistre bien l'échec, mais le design reste dans son état et rien ne le
diffuse : côté navigateur, « génération en cours » à l'infini. `GenerateDesignJob`
et `PollDesignJob` attrapent donc `StandardError` en dernier recours, marquent le
design échoué, rendent l'essai, **puis relancent l'erreur** — elle est notre
affaire et doit rester visible dans la file.

**`strict_loading_mode = :n_plus_one_only` ne remplace pas `:all`.** La piste
paraissait élégante : n'interdire que les N+1, ce que dit la règle. Mesure
faite, sous ce mode `Design.limit(5).each { |d| d.user }` ne lève **plus rien** —
c'est-à-dire précisément la forme de N+1 la plus courante. Le mode ne resserre
pas la garde, il l'ouvre.

**Une validation qui rejuge le passé fige l'enregistrement.** Le minimum de
commande d'un atelier et la date souhaitée par le client jugent la demande
*telle qu'elle a été envoyée* : en `on: :create` uniquement. Sans cela, un
atelier qui relève son minimum le mois suivant — ou une date qui arrive tout
simplement — rend impossible le moindre `save`, et la demande reste **bloquée
dans son état**, y compris pour l'atelier qui l'a en main.

**Les vues de mailer se résolvent sur `<mailer>.<action>`, pas sur `mailers.`.**
Un `t(".titre")` dans `print_request_mailer/to_printer.html.erb` cherche
`fr.print_request_mailer.to_printer.titre`. Le projet range ses textes sous
`mailers.<objet>.<action>` : employer la clé absolue, comme le fait déjà
`passwords_mailer`.

**`ActionMailer::TestHelper` n'est pas inclus par défaut.** Il l'est désormais
dans `test/test_helper.rb`, à côté de celui d'Active Job : une demande
d'impression qui n'envoie aucun email n'a pas été envoyée, et `assert_emails`
doit être disponible partout, pas seulement dans `test/mailers`.

**`config_for` symbolise les clés en profondeur.** Un `preset['key']` sur une
entrée de `config/settings.yml` renvoie `nil`, toujours — il faut `preset[:key]`.
Le piège n'est pas le `nil` lui-même : interpolé dans une clé de traduction, il
donne `…size_presets.`, et I18n, plutôt que de lever une erreur, **retombe sur
le hash parent**. Chaque bouton affichait donc les quatre libellés à la fois,
`raise_on_missing_translations` compris. Employer `fetch(:key)`, qui échoue.

**Ne pas lancer `bin/rails runner` en `RAILS_ENV=test` sans transaction.** Les
tables Active Storage ne sont pas des fixtures : un attachement créé par un essai
de débogage **reste** dans la base de test et fait passer, au hasard des seeds,
un test qui attendait « aucun fichier ». Nettoyer, ou envelopper dans un
`ActiveRecord::Base.transaction { … raise ActiveRecord::Rollback }`.

### Ce que la machine impose

Les tests système restent volontairement sérialisés (`parallelize(workers: 1)`
dans `ApplicationSystemTestCase`). C'était une nécessité sur l'ancien poste
(4 Go de RAM, i3-5005U de 2015) ; sur la machine actuelle c'est une précaution
peu coûteuse, et la sérialisation supprime une source d'échecs intermittents.

Cette machine porte aussi le GPU de génération (RTX 4070 Ti, 12 Go). Une
génération réelle occupe la carte pendant ~20 à 45 s ; les tests, eux, ne
touchent jamais au service — tout appel sortant passe par WebMock.
