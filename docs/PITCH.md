# Prêt-à-tirer — pitch et user stories

Ce document ne fait pas foi : c'est [docs/SPEC.md](SPEC.md) qui tranche en cas
de doute. Il sert à vérifier, d'un coup d'œil, que ce qui a été construit
correspond bien à ce qui était voulu — les user stories décrivent ce qui est
**implémenté**, pas ce qui est envisagé.

---

## Le pitch

**Prêt-à-tirer** se vend aux imprimeurs textiles, par abonnement.

Un atelier de sérigraphie, de DTF ou de broderie a un problème récurrent : ses
clients arrivent avec une image trouvée sur Internet ou générée par une IA
grand public — en pixels, dans n'importe quelle résolution, avec des dégradés
qu'aucune machine ne sait imprimer. Vectoriser ça proprement, ou l'agrandir
sans le dégrader, coûte du temps que personne ne facture.

Prêt-à-tirer inverse le problème : c'est l'atelier qui indique sa technique
d'impression, et l'IA dessine **pour cette machine-là** — aplats bornés aux
couleurs qu'un écran de sérigraphie sait poser, dégradés fins réservés au DTF,
densité de fils pensée pour la broderie. Le service produit ensuite le fichier
que la machine attend : SVG vectorisé, ou image matricielle détourée à 300 dpi,
à la bonne taille. L'atelier reçoit par email une demande complète — le
fichier, la palette, le textile, l'emplacement, les tailles, les quantités —
et répond avec son devis, hors plateforme : Prêt-à-tirer ne facture jamais
l'impression elle-même.

Chaque atelier a son propre lien et son propre QR code, à distribuer en
boutique ou sur ses réseaux : son client crée son design dessus, sans jamais
avoir à choisir un atelier au hasard dans un annuaire. Un annuaire existe tout
de même, avec carte et filtres, pour les clients qui n'en ont pas encore.

Option payante pour le client qui veut une seconde paire d'yeux avant
d'envoyer : la vérification par un graphiste indépendant, rémunéré via Stripe
Connect, qui peut retoucher le fichier ou signaler qu'une autre technique
conviendrait mieux.

**Trois sources de revenus** : l'abonnement des ateliers (deux formules,
Référencement et Atelier+), la commission de plateforme sur chaque vérification
graphiste, et rien d'autre — pas de commission sur l'impression, qui reste
entre l'atelier et son client.

---

## Les user stories

Classées par rôle. `User` porte un rôle unique parmi les quatre — un compte
n'est jamais à la fois client et imprimeur, par exemple.

### Visiteur (sans compte)

- En tant que visiteur, je découvre le principe sur la page d'accueil
  (avant/après pixel et vecteur, fonctionnement, exemple d'email, abonnements)
  et je suis invité à m'inscrire comme atelier ou comme graphiste.
- En tant que visiteur, je consulte l'annuaire des imprimeurs — carte, filtres
  avec la technique d'impression en tête, puis rayon, textile, délai,
  livraison — et j'ouvre une fiche détaillée.
- En tant que visiteur arrivé par le lien ou le QR code d'un atelier
  (`/a/:slug`), cet atelier est présélectionné pour toute ma session, sans
  qu'on me demande de choisir.
- En tant que visiteur arrivé par un lien d'atelier, on me demande si
  j'accepte un cookie pour que cet atelier reste associé à moi au-delà de ma
  session (30 jours) ; refuser ne change rien à l'usage du site, et je peux
  changer d'avis à tout moment depuis `/cookies`.
- En tant que visiteur, je dois créer un compte pour générer un design.

### Client

- En tant que client, je crée un design : je choisis la technique
  d'impression en premier — elle façonne tout le reste du formulaire — puis je
  décris mon idée, je choisis un style, un nombre de couleurs si la technique
  le demande, et une taille d'impression ; je suis la génération en direct.
- En tant que client, l'aperçu qu'on me montre est le **rendu du fichier
  d'impression** — jamais l'image brute que l'IA a dessinée, et jamais le
  fichier lui-même : un rendu filigrané, produit côté serveur.
- En tant que client, je dispose de trois reprises par lignée de design — une
  retouche par instruction en chat, ou trois variantes en un clic — et je vois
  toujours combien il m'en reste.
- En tant que client dont le budget de reprises est épuisé, on me propose la
  vérification payante par un graphiste plutôt que de me laisser bloqué.
- En tant que client, j'envoie mon design à un atelier compatible — le mien
  par défaut, ou un autre trouvé dans l'annuaire — avec le textile,
  l'emplacement, les tailles, les quantités, une date souhaitée et mes
  coordonnées.
- En tant que client, je peux annuler une demande d'impression tant que
  l'atelier n'a pas encore envoyé son devis.
- En tant que client, mon tableau de bord me montre d'abord ce qui m'attend —
  une génération ratée à relancer, un design prêt jamais envoyé, un atelier
  resté silencieux — puis mon activité récente.
- En tant que client, je gère mon compte : coordonnées, mot de passe (huit
  caractères au moins), export JSON de mes données, fermeture de compte, avec
  ce qui survit à la fermeture expliqué clairement.

### Imprimeur

- En tant qu'imprimeur, je m'inscris, je m'abonne via Stripe (Référencement ou
  Atelier+), je remplis ma fiche, et elle n'est publiée qu'après validation
  par l'administration.
- En tant qu'imprimeur, je déclare chacune de mes techniques avec mon propre
  nom pour elle, le format de fichier que j'attends, mon espace colorimétrique
  et mes propres plafonds (encres, dimensions).
- En tant qu'imprimeur, je partage mon lien et mon QR code — qui distinguent
  déjà un scan d'affiche d'un clic sur le lien — et, avec Atelier+, je crée des
  liens nommés (flyer, salon, réseau social) pour savoir lequel amène
  vraiment des clients.
- En tant qu'imprimeur Atelier+, mes statistiques me disent combien de
  demandes reçues confirment réellement mon propre lien, plutôt qu'un client
  qui m'a trouvé ailleurs pour un design commencé chez un confrère.
- En tant qu'imprimeur, je reçois chaque demande par email avec les fichiers
  et une fiche technique complète, je confirme réception d'un clic, et je
  fais avancer son statut depuis `/atelier/demandes`.

### Graphiste

- En tant que graphiste, je m'inscris, je remplis mon profil et les niveaux de
  vérification que j'accepte, et j'active mes versements via Stripe Connect
  avant de pouvoir prendre la moindre revue en charge.
- En tant que graphiste, je prends en charge une revue, je dépose une version,
  j'échange par messagerie avec le client.
- En tant que graphiste, si l'option choisie par le client ne permet pas de
  faire le travail correctement, je la lui renvoie avec un motif et une
  proposition — une seule fois par revue.

### Administration

- En tant qu'admin, je valide ou je suspends les fiches d'atelier et les
  profils de graphiste.
- En tant qu'admin, je tranche les litiges de revue, avec remboursement total
  ou partiel.
- En tant qu'admin, je gère les niveaux de vérification proposés et la liste
  des termes que le générateur refuse de dessiner.
- En tant qu'admin, je vois d'un coup d'œil l'état de la plateforme — le
  générateur, Stripe et Turnstile sont-ils configurés.

### Délibérément hors V1

Paiement de l'impression sur la plateforme, suivi de production détaillé
au-delà de statuts simples, application mobile native, éditeur de placement
libre du design sur le vêtement, impression papier (offset, numérique). Voir
« Décisions ouvertes » dans [docs/SPEC.md](SPEC.md) pour ce qui reste à
trancher avant la mise en production commerciale.
