Rails.application.routes.draw do
  # Public paths are in French; controllers, models and columns stay in English.
  # See docs/SPEC.md, "Écrans et routes".

  root "public/home#show"

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Outgoing mail is previewed rather than delivered in development.
  if Rails.env.development?
    mount LetterOpenerWeb::Engine, at: "/letter_opener"
  end
end
