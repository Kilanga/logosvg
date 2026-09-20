Rails.application.routes.draw do
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
  # Le lien que l'imprimeur partage : il retient l'atelier pour la session.
  get "a/:slug", to: "public/workshop_links#show", as: :workshop_link

  get  "designs/nouveau", to: "client/designs#new",    as: :new_design
  post "designs",         to: "client/designs#create", as: :designs
  get  "designs/:token",  to: "client/designs#show",   as: :design
  # Le rendu filigrané : jamais le fichier d'impression lui-même.
  get  "designs/:token/apercu", to: "client/designs#image", as: :design_image
  post "designs/:token/variantes", to: "client/designs#variants", as: :design_variants
  post "designs/:token/retouche",  to: "client/designs#refine",   as: :design_refine

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

  # Les demandes reçues par l'atelier, et leur suivi.
  get   "atelier/demandes",        to: "workshop/print_requests#index",  as: :workshop_print_requests
  get   "atelier/demandes/:token", to: "workshop/print_requests#show",   as: :workshop_print_request
  patch "atelier/demandes/:token", to: "workshop/print_requests#update"

  # Le profil du graphiste, ses niveaux et ses versements.
  # Pas d'action « soumettre » : un profil naît en relecture, et c'est
  # l'administration qui l'active.
  get   "studio/profil", to: "designer/profiles#edit",   as: :edit_designer_profile
  patch "studio/profil", to: "designer/profiles#update", as: :designer_profile

  get  "studio/paiements",            to: "designer/payouts#show",   as: :designer_payouts
  post "studio/paiements/inscription", to: "designer/payouts#onboard", as: :designer_payouts_onboarding
  post "studio/paiements/tableau-de-bord", to: "designer/payouts#dashboard",
       as: :designer_payouts_dashboard

  # Validation des fiches par l'administration.
  get   "admin/imprimeurs",       to: "admin/printers#index",  as: :admin_printers
  patch "admin/imprimeurs/:slug", to: "admin/printers#update", as: :admin_printer

  get   "admin/graphistes",     to: "admin/designers#index",  as: :admin_designers
  patch "admin/graphistes/:id", to: "admin/designers#update", as: :admin_designer

  # --- Webhooks ---------------------------------------------------------------
  # Signature vérifiée, jamais de session : Stripe n'est pas un visiteur.
  post "webhooks/stripe", to: "webhooks/stripe#create", as: :stripe_webhook

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Outgoing mail is previewed rather than delivered in development.
  if Rails.env.development?
    mount LetterOpenerWeb::Engine, at: "/letter_opener"
  end
end
