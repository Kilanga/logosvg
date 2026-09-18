# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"

# Leaflet, vendored rather than pinned to a CDN: the content security policy
# allows scripts from the application only, and no visitor's browser should have
# to call a third party. Map tiles still come from OpenStreetMap, which the
# policy allows as images and whose attribution is displayed.
pin "leaflet", to: "leaflet.js", preload: false
