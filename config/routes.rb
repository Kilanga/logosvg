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

  # --- Annuaire public -------------------------------------------------------
  get "imprimeurs",       to: "public/printers#index", as: :printers
  get "imprimeurs/:slug", to: "public/printers#show",  as: :printer

  # --- Espaces professionnels ------------------------------------------------
  # One entry point per role. Later steps nest their screens under each of them.
  get "mon-espace", to: "client/dashboards#show",   as: :client_dashboard
  get "atelier",    to: "workshop/dashboards#show",  as: :workshop_dashboard
  get "studio",     to: "designer/dashboards#show", as: :designer_dashboard
  get "admin",      to: "admin/dashboards#show",    as: :admin_dashboard

  # La fiche de l'atelier : une seule par compte imprimeur.
  get   "atelier/fiche/edit", to: "workshop/profiles#edit",   as: :edit_workshop_profile
  patch "atelier/fiche",      to: "workshop/profiles#update", as: :workshop_profile
  post  "atelier/fiche/soumettre", to: "workshop/profiles#submit", as: :submit_workshop_profile

  # Validation des fiches par l'administration.
  get   "admin/imprimeurs",       to: "admin/printers#index",  as: :admin_printers
  patch "admin/imprimeurs/:slug", to: "admin/printers#update", as: :admin_printer

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Outgoing mail is previewed rather than delivered in development.
  if Rails.env.development?
    mount LetterOpenerWeb::Engine, at: "/letter_opener"
  end
end
