# Prêt-à-tirer

> Le nom est défini dans `config/settings.yml` (`platform_name`) et n'est
> recopié nulle part ailleurs : une seule ligne à changer s'il évolue.

Plateforme vendue par abonnement aux **imprimeurs textiles**. Leurs clients
décrivent une idée, une IA génère un visuel **en aplats** limité aux couleurs
que l'atelier sait imprimer, le service le **vectorise**, et l'atelier reçoit
par email une demande d'impression complète : SVG, palette d'encres, textile,
emplacement, tailles et quantités. Le devis se fait hors plateforme.

Option payante : la **vérification par un graphiste**, payée par Stripe et
reversée au graphiste via Connect.

**Cahier des charges : [docs/SPEC.md](docs/SPEC.md).** Il fait foi.
Conventions de travail et environnement : [CLAUDE.md](CLAUDE.md).

## État

| Étape | Contenu | État |
| --- | --- | --- |
| 0 | Socle | terminée |
| 1 → 10 | Comptes, imprimeurs, designs, demandes, espaces, abonnements, graphistes, revues, administration, finitions | à faire |

## Stack

Rails 8.1 monolithique, Ruby 3.3, PostgreSQL 16, Hotwire (Turbo + Stimulus)
via importmap, Tailwind v4, Solid Queue / Cache / Cable, Active Storage,
Pundit, AASM, Stripe, Geocoder, Leaflet.

Le moteur de génération est un service Python séparé, **déjà livré**, dans
[`services/generator/`](services/generator/) : Rails le consomme en HTTP et ne
le modifie pas.

Pas de Node : `tailwindcss-rails` embarque le binaire Tailwind autonome et les
modules JS passent par importmap.

## Démarrer

Prérequis : Ruby 3.3+, PostgreSQL 16, libvips, Python 3.10+ et Google Chrome
pour les tests système. Sous Windows, tout tourne dans WSL2 — voir CLAUDE.md.

```bash
cp .env.example .env     # puis remplir les clés
bin/setup
bin/dev
```

`bin/dev` lance quatre processus : le serveur Rails, le watcher Tailwind, le
worker Solid Queue et le microservice de génération **en mode mock** (il crée
son virtualenv au premier lancement, sans GPU).

- Application : <http://localhost:3000>
- Emails sortants : <http://localhost:3000/letter_opener>
- Service de génération : <http://127.0.0.1:5000/health>

## Commandes

```bash
bin/rails test          # unitaires et intégration
bin/rails test:system   # Capybara, Chrome sans interface
bin/rubocop             # rubocop-rails-omakase
bin/brakeman --no-pager
bin/bundler-audit check --update
```

La CI GitHub Actions rejoue l'ensemble, plus `importmap audit`, sur PostgreSQL 16.

## Organisation

```
app/services/         logique métier, objets à .call
app/policies/         Pundit, une policy par modèle
app/javascript/       contrôleurs Stimulus
app/assets/fonts/     Barlow Condensed et Figtree auto-hébergées (RGPD)
config/locales/fr.yml tout le texte visible
config/settings.yml   décisions ouvertes, valeurs provisoires marquées
docs/SPEC.md          cahier des charges
services/generator/   microservice FastAPI livré — ne pas modifier
```

Interface en français, code et base de données en anglais.

## Secrets

Rien de sensible dans le dépôt. `.env` est ignoré par git ; `.env.example`
documente les variables sans valeur. Les secrets de production passent par les
credentials Rails chiffrés ou par l'environnement.

⚠ `config/master.key` n'est **pas** versionné : sans lui,
`config/credentials.yml.enc` est illisible. Conservez-le en lieu sûr.
