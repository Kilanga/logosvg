require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Le nom de domaine servi. Déclaré par l'environnement pour qu'une mise en
  # ligne sur un autre nom — une préproduction, un essai — ne demande pas de
  # toucher au code.
  app_host = ENV.fetch("APP_HOST", "pretatirer.fr")

  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory savings (ignored by Rake tasks).
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Turn on fragment caching in view templates.
  config.action_controller.perform_caching = true

  # Cache assets for far-future expiry since they are all digest stamped.
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # Store uploaded files on the local file system (see config/storage.yml for options).
  config.active_storage.service = :local

  # Le proxy de Kamal termine le TLS et parle en clair au conteneur. Sans ces
  # deux lignes, Rails se croit en clair : les cookies de session perdent leur
  # attribut `secure` et les redirections repartent en http — sur une
  # plateforme qui manipule des comptes et des paiements, ce n'est pas une
  # option.
  config.assume_ssl = true
  config.force_ssl = true

  # Le contrôle de santé est interrogé en http depuis la machine elle-même :
  # le rediriger ferait échouer chaque déploiement alors que tout va bien.
  config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } }

  # Log to STDOUT with the current request id as a default log tag.
  config.log_tags = [ :request_id ]
  config.logger   = ActiveSupport::TaggedLogging.logger(STDOUT)

  # Change to "debug" to log everything (including potentially personally-identifiable information!).
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Prevent health checks from clogging up the logs.
  config.silence_healthcheck_path = "/up"

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Replace the default in-process memory cache store with a durable alternative.
  config.cache_store = :solid_cache_store

  # Replace the default in-process and non-durable queuing backend for Active Job.
  config.active_job.queue_adapter = :solid_queue
  config.solid_queue.connects_to = { database: { writing: :queue } }

  # Ignore bad email addresses and do not raise email delivery errors.
  # Set this to true and configure the email server for immediate delivery to raise delivery errors.
  # config.action_mailer.raise_delivery_errors = false

  # Les liens des emails sortent de l'application sans requête pour les porter :
  # l'hôte se déclare ici, une fois.
  config.action_mailer.default_url_options = { host: app_host, protocol: "https" }

  # Le relais SMTP. Les identifiants viennent de l'environnement plutôt que des
  # credentials chiffrés : Kamal les injecte depuis .kamal/secrets, et changer
  # de relais ne demande alors aucun déploiement de code.
  config.action_mailer.delivery_method = :smtp
  config.action_mailer.perform_deliveries = true
  config.action_mailer.smtp_settings = {
    address: ENV.fetch("SMTP_ADDRESS", "smtp-relay.brevo.com"),
    port: ENV.fetch("SMTP_PORT", "587").to_i,
    user_name: ENV["SMTP_USER_NAME"],
    password: ENV["SMTP_PASSWORD"],
    authentication: :plain,
    enable_starttls_auto: true
  }

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = [ :id ]

  # Protection contre la réécriture d'en-tête `Host` : seules ces adresses sont
  # servies. Le contrôle de santé, lui, arrive par l'IP de la machine et n'a
  # aucun nom à présenter.
  config.hosts = [ app_host, "www.#{app_host}" ]
  # www est accepté puis renvoyé vers le nom nu (voir config/routes.rb).
  config.x.canonical_host = app_host
  config.host_authorization = { exclude: ->(request) { request.path == "/up" } }
end
