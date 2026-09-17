# Be sure to restart your server when you modify this file.

# Version of your assets, change this if you want to expire all your assets.
Rails.application.config.assets.version = "1.0"

# Self-hosted typefaces. They are served by the application rather than by
# Google Fonts, so no visitor's browser ever calls a third party (GDPR).
# Adding the directory as a root keeps logical paths flat, which is what the
# `url("Figtree-400.woff2")` references in the Tailwind entrypoint resolve against.
Rails.application.config.assets.paths << Rails.root.join("app/assets/fonts")
