require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
# require "action_mailbox/engine"
# require "action_text/engine"
require "action_view/railtie"
require "action_cable/engine"
require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module TshirtIa
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # The interface is French and the audience is French: everything the user
    # sees is rendered in Europe/Paris time. Records stay in UTC in the database.
    config.time_zone = "Europe/Paris"
    config.active_record.default_timezone = :utc

    # French is the only locale for now. Keeping the list explicit means a typo
    # in a locale key raises instead of silently falling back to English.
    config.i18n.default_locale = :fr
    config.i18n.available_locales = [ :fr ]
    config.i18n.fallbacks = false

    # Business settings that are still open decisions live in one place, so no
    # provisional value is ever hard-coded. See config/settings.yml.
    config.tshirt = config_for(:settings)

    # Generators: no JS or CSS scaffolding, and Minitest fixtures only.
    config.generators do |g|
      g.assets false
      g.helper false
      g.test_framework :test_unit, fixture: true
      g.system_tests :test_unit
    end
  end
end
