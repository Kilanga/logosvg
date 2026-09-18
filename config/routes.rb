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

  # --- Espaces professionnels ------------------------------------------------
  # One entry point per role. Later steps nest their screens under each of them.
  get "mon-espace", to: "client/dashboards#show",   as: :client_dashboard
  get "atelier",    to: "printer/dashboards#show",  as: :printer_dashboard
  get "studio",     to: "designer/dashboards#show", as: :designer_dashboard
  get "admin",      to: "admin/dashboards#show",    as: :admin_dashboard

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Outgoing mail is previewed rather than delivered in development.
  if Rails.env.development?
    mount LetterOpenerWeb::Engine, at: "/letter_opener"
  end
end
