Rails.application.routes.draw do
  # www.pretatirer.fr est servi (certificat et config.hosts) pour ne jamais
  # échouer, mais une seule adresse fait foi : redirection permanente vers le
  # nom nu, chemin et paramètres conservés. En premier, avant toute autre route.
  # Ne joue qu'en production, où config.x.canonical_host est posé : les tests
  # d'intégration tournent par défaut sur www.example.com.
  constraints(lambda { |request|
    canonical = Rails.application.config.x.canonical_host
    canonical.present? && request.host == "www.#{canonical}"
  }) do
    match "(*path)", via: :all, format: false, to: redirect(status: 301) { |_params, request|
      "#{request.protocol}#{Rails.application.config.x.canonical_host}#{request.port_string}#{request.fullpath}"
    }
  end

  # Public paths are in French; controllers, models and columns stay in English.
  # See docs/SPEC.md, "Écrans et routes".

  root "public/home#show"

  # --- Comptes ---------------------------------------------------------------
  get    "connexion",   to: "sessions#new",     as: :new_session
  post   "connexion",   to: "sessions#create",  as: :session
  delete "connexion",   to: "sessions#destroy"

  get  "inscription", to: "registrations#new",    as: :new_registration
  post "inscription", to: "registrations#create", as: :registration

  resources :passwords, path: "mot-de-passe", param: :token, only: %i[ new create edit update ]

  # --- Designs ---------------------------------------------------------------
  # La page de l'atelier pour ses clients. Avec son code (affiche, QR code,
  # liens nommés), le client est admis d'office ; sans, il demande à l'atelier,
  # qui accepte ou refuse dans son espace. Voir docs/SPEC.md, « Rattachement
  # d'un client à un atelier ».
  get  "a/:slug",           to: "public/workshop_links#show", as: :workshop_link
  post "a/:slug/rejoindre", to: "public/workshop_links#join", as: :join_workshop
  get  "a/:slug/:code",     to: "public/workshop_links#show", as: :workshop_invite

  get  "designs/nouveau", to: "client/designs#new",    as: :new_design
  # Un visuel déjà fait, mis au format de l'atelier sans être redessiné.
  get  "designs/deposer", to: "client/uploads#new",    as: :new_design_upload
  post "designs/deposer", to: "client/uploads#create", as: :design_uploads
  post "designs",         to: "client/designs#create", as: :designs
  get  "designs/:token",  to: "client/designs#show",   as: :design
  # Le rendu filigrané : jamais le fichier d'impression lui-même.
  get  "designs/:token/apercu", to: "client/designs#image", as: :design_image
  # Pour comparer : l'image d'origine, elle aussi filigranée, jamais envoyée
  # telle quelle. Voir docs/SPEC.md, "Détails d'interface à respecter" → "Aperçu".
  get  "designs/:token/original", to: "client/designs#original_image", as: :design_original_image
  # Le fichier d'impression avec sa transparence, pour la silhouette de t-shirt :
  # le blanc non imprimé doit laisser voir la couleur du tissu.
  get  "designs/:token/sur-textile", to: "client/designs#garment_image", as: :design_garment_image
  # L'image du client dont le design est parti, telle qu'elle a été réencodée.
  get  "designs/:token/image-de-depart", to: "client/designs#reference_image", as: :design_reference_image
  post "designs/:token/variantes", to: "client/designs#variants", as: :design_variants
  post "designs/:token/retouche",  to: "client/designs#refine",   as: :design_refine
  # Garder une des propositions d'un clic ; les autres sont écartées.
  post "designs/:token/choisir",   to: "client/designs#choose",   as: :design_choice

  # --- Demandes d'impression -------------------------------------------------
  get  "designs/:design_token/demande", to: "client/print_requests#new",
       as: :new_design_print_request
  post "designs/:design_token/demande", to: "client/print_requests#create",
       as: :design_print_requests

  get  "demandes/:token", to: "client/print_requests#show", as: :print_request
  post "demandes/:token/annuler", to: "client/print_requests#cancel", as: :cancel_print_request

  # La page que l'atelier ouvre depuis son email, sans connexion. Seul le POST
  # change le statut : les antivirus de messagerie suivent les liens tout seuls.
  get  "demandes/confirmation/:token", to: "public/print_request_confirmations#show",
       as: :print_request_confirmation
  post "demandes/confirmation/:token", to: "public/print_request_confirmations#create"

  # --- Vérifications par un graphiste ----------------------------------------
  get  "designs/:design_token/verification", to: "client/reviews#new",
       as: :new_design_review
  post "designs/:design_token/verification", to: "client/reviews#create",
       as: :design_reviews

  get  "verifications/:token", to: "client/reviews#show", as: :review
  post "verifications/:token/valider",   to: "client/reviews#accept",   as: :accept_review
  post "verifications/:token/retour",    to: "client/reviews#revision", as: :revision_review
  post "verifications/:token/proposition/accepter", to: "client/reviews#accept_proposal",
       as: :accept_review_proposal
  post "verifications/:token/proposition/refuser",  to: "client/reviews#decline_proposal",
       as: :decline_review_proposal
  post "verifications/:token/proposition/graphiste", to: "client/reviews#pick_designer",
       as: :pick_review_designer
  post "verifications/:token/relancer",  to: "client/reviews#reopen", as: :reopen_review
  post "verifications/:token/note",      to: "client/reviews#rate",   as: :rate_review
  post "verifications/:token/messages",  to: "client/reviews#message", as: :review_messages
  # Litiges (08/10/2026) : le client signale, accepte la correction offerte
  # ou retire son signalement.
  post "verifications/:token/signaler",  to: "client/reviews#dispute", as: :dispute_review
  post "verifications/:token/correction", to: "client/reviews#accept_fix", as: :accept_fix_review
  post "verifications/:token/retirer-signalement", to: "client/reviews#withdraw_dispute",
       as: :withdraw_dispute_review

  # --- Annuaire public -------------------------------------------------------
  get "imprimeurs",       to: "public/printers#index", as: :printers
  get "imprimeurs/:slug", to: "public/printers#show",  as: :printer

  get "graphistes",     to: "public/designers#index", as: :designers
  get "graphistes/:id", to: "public/designers#show",  as: :designer

  # --- Espaces professionnels ------------------------------------------------
  # One entry point per role. Later steps nest their screens under each of them.
  get "mon-espace", to: "client/dashboards#show",   as: :client_dashboard

  # Les listes du client, toutes restreintes à ses propres données.
  get    "mon-espace/designs",       to: "client/designs#index",       as: :client_designs
  get    "mon-espace/demandes",      to: "client/print_requests#index", as: :client_print_requests
  get    "mon-espace/verifications", to: "client/reviews#index",       as: :client_reviews
  get    "mon-espace/compte",        to: "client/accounts#edit",       as: :client_account
  patch  "mon-espace/compte",        to: "client/accounts#update"
  patch  "mon-espace/compte/mot-de-passe", to: "client/accounts#update_password",
         as: :client_account_password
  get    "mon-espace/compte/export", to: "client/accounts#export",  as: :client_account_export
  delete "mon-espace/compte",        to: "client/accounts#destroy"

  delete "designs/:token", to: "client/designs#destroy", as: :delete_design
  get "atelier",    to: "workshop/dashboards#show",  as: :workshop_dashboard
  get "studio",     to: "designer/dashboards#show", as: :designer_dashboard
  get "admin",      to: "admin/dashboards#show",    as: :admin_dashboard

  # La fiche de l'atelier : une seule par compte imprimeur.
  get   "atelier/fiche/edit", to: "workshop/profiles#edit",   as: :edit_workshop_profile
  patch "atelier/fiche",      to: "workshop/profiles#update", as: :workshop_profile
  post  "atelier/fiche/soumettre", to: "workshop/profiles#submit", as: :submit_workshop_profile

  # Abonnement de l'atelier : Checkout et portail client, rien de plus — le
  # changement de formule et les factures vivent chez Stripe.
  get  "atelier/abonnement",          to: "workshop/subscriptions#show",   as: :workshop_subscription
  post "atelier/abonnement",          to: "workshop/subscriptions#create"
  post "atelier/abonnement/portail",  to: "workshop/subscriptions#portal", as: :workshop_subscription_portal

  # Le lien client, son QR code et l'affiche comptoir.
  get "atelier/lien",           to: "workshop/links#show", as: :workshop_link_share
  get "atelier/lien/qr.:format", to: "workshop/links#qr",   as: :workshop_link_qr
  get "atelier/lien/affiche",   to: "workshop/links#poster", as: :workshop_link_poster

  # Les liens nommés (flyer, salon, réseau social), un compteur chacun.
  post   "atelier/lien/canaux",      to: "workshop/link_channels#create",  as: :workshop_link_channels
  delete "atelier/lien/canaux/:key", to: "workshop/link_channels#destroy", as: :workshop_link_channel

  # Le code de l'affiche : un nouveau rend l'ancien inopérant.
  post "atelier/lien/code",     to: "workshop/links#regenerate_code", as: :workshop_link_code

  # L'aide de l'atelier : le fonctionnement et ses questions, et la fiche qu'il
  # remet à ses clients pour leur expliquer le parcours.
  get "atelier/aide",              to: "workshop/help#show",         as: :workshop_help
  get "atelier/aide/fiche-client", to: "workshop/help#client_sheet", as: :workshop_client_sheet

  # Les clients de l'atelier, et les demandes qui attendent sa réponse.
  get  "atelier/clients",                to: "workshop/clients#index",   as: :workshop_clients
  post "atelier/clients/demandes/:id/accepter", to: "workshop/clients#accept",
       as: :accept_workshop_client_request
  post "atelier/clients/demandes/:id/refuser",  to: "workshop/clients#decline",
       as: :decline_workshop_client_request
  delete "atelier/clients/:id",          to: "workshop/clients#remove",  as: :workshop_client

  # Les demandes reçues par l'atelier, et leur suivi.
  get   "atelier/demandes",        to: "workshop/print_requests#index",  as: :workshop_print_requests
  get   "atelier/demandes/:token", to: "workshop/print_requests#show",   as: :workshop_print_request
  patch "atelier/demandes/:token", to: "workshop/print_requests#update"

  # Le profil du graphiste, ses niveaux et ses versements.
  # Pas d'action « soumettre » : un profil naît en relecture, et c'est
  # l'administration qui l'active.
  get   "studio/profil", to: "designer/profiles#edit",   as: :edit_designer_profile
  patch "studio/profil", to: "designer/profiles#update", as: :designer_profile

  # La file du graphiste et ce qu'il y fait.
  get  "studio/revues",        to: "designer/reviews#index", as: :designer_reviews
  get  "studio/revues/:token", to: "designer/reviews#show",  as: :designer_review
  post "studio/revues/:token/prendre",   to: "designer/reviews#claim",    as: :claim_designer_review
  post "studio/revues/:token/versions",  to: "designer/reviews#deliver",  as: :deliver_designer_review
  post "studio/revues/:token/renvoyer",  to: "designer/reviews#return_to_client",
       as: :return_designer_review
  post "studio/revues/:token/messages",  to: "designer/reviews#message", as: :designer_review_messages
  post "studio/revues/:token/terminer",  to: "designer/reviews#finish",   as: :finish_designer_review
  post "studio/revues/:token/correction", to: "designer/reviews#offer_fix", as: :offer_fix_designer_review

  get  "studio/paiements",            to: "designer/payouts#show",   as: :designer_payouts
  post "studio/paiements/inscription", to: "designer/payouts#onboard", as: :designer_payouts_onboarding
  post "studio/paiements/tableau-de-bord", to: "designer/payouts#dashboard",
       as: :designer_payouts_dashboard

  # Validation des fiches par l'administration.
  get   "admin/imprimeurs",       to: "admin/printers#index",  as: :admin_printers
  patch "admin/imprimeurs/:slug", to: "admin/printers#update", as: :admin_printer

  get   "admin/graphistes",     to: "admin/designers#index",  as: :admin_designers
  patch "admin/graphistes/:id", to: "admin/designers#update", as: :admin_designer

  # Revues et litiges : l'admin ne rejoue pas la conversation, il tranche.
  get  "admin/verifications",        to: "admin/reviews#index", as: :admin_reviews
  get  "admin/verifications/:token", to: "admin/reviews#show",  as: :admin_review
  post "admin/verifications/:token/regler", to: "admin/reviews#settle", as: :settle_admin_review

  # Niveaux de vérification, termes bloqués, état du service.
  resources :admin_levels, path: "admin/niveaux", controller: "admin/review_levels",
            only: %i[ index create update ]
  resources :admin_blocked_terms, path: "admin/termes", controller: "admin/blocked_terms",
            only: %i[ index create update destroy ]
  get "admin/etat", to: "admin/status#show", as: :admin_status

  # --- Pages légales -----------------------------------------------------------
  # Une action, une page par document : le contenu vit dans les vues, pas dans
  # une base que personne ne relit.
  get "mentions-legales",        to: "public/legal#show", page: "legal_notice",   as: :legal_notice
  get "conditions-utilisation",  to: "public/legal#show", page: "terms",          as: :terms
  get "conditions-abonnement",   to: "public/legal#show", page: "subscription_terms",
      as: :subscription_terms
  get "conditions-graphistes",   to: "public/legal#show", page: "designer_terms", as: :designer_terms
  get "confidentialite",         to: "public/legal#show", page: "privacy",        as: :privacy
  get "classement-annuaire",     to: "public/legal#show", page: "ranking",        as: :ranking
  get "cookies",                 to: "public/legal#show", page: "cookies",        as: :cookies

  # Pas un document légal : pas de bandeau "document de travail", juste
  # comment nous écrire, pour une question comme pour une réclamation.
  get "contact", to: "public/contact#show", as: :contact

  # Les questions des clients, ouvertes à tous : on les lit avant de créer un
  # compte autant qu'après.
  get "aide", to: "public/help#show", as: :help

  # Le choix du visiteur sur le cookie qui retient l'atelier qui l'a envoyé.
  post "cookies", to: "public/cookie_consents#create", as: :cookie_consent

  # --- Webhooks ---------------------------------------------------------------
  # Signature vérifiée, jamais de session : Stripe n'est pas un visiteur.
  post "webhooks/stripe", to: "webhooks/stripe#create", as: :stripe_webhook

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Ce que les moteurs de recherche et les navigateurs demandent d'office.
  get "robots.txt",  to: "public/discovery#robots",  as: :robots, format: false
  get "sitemap.xml", to: "public/discovery#sitemap", as: :sitemap, format: false
  get "favicon.ico", to: "public/discovery#favicon", format: false

  # Outgoing mail is previewed rather than delivered in development.
  if Rails.env.development?
    mount LetterOpenerWeb::Engine, at: "/letter_opener"
  end
end
