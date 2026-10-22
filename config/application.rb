require_relative "boot"

require "csv"
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
# require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Backend
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.0

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    # `rubocop/` holds custom cops loaded by .rubocop.yml's `require:` — it is
    # dev tooling, not application code, and must not be autoloaded/eager-loaded
    # (its `RuboCop::` namespace also trips Zeitwerk's inflector).
    config.autoload_lib(ignore: %w[assets tasks rubocop])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"

    # Where the web UI is served. One default, read by the production
    # host list and by every link a mail sends (AccountMailer), so the two
    # can never point at different domains.
    config.x.app_host = ENV.fetch("APP_HOST", "app.fitora.com")
    config.x.frontend_url = ENV.fetch("FRONTEND_URL") do
      Rails.env.production? ? "https://#{config.x.app_host}" : "http://localhost:3000"
    end
    # The Sentry project the web UI's browser errors go to
    # (app/javascript/lib/error_reporting.js), or nil: nothing is sent.
    config.x.sentry_browser_dsn = ENV["SENTRY_BROWSER_DSN"].presence
    # config.eager_load_paths << Rails.root.join("extras")

    # Not API-only any more: the server-rendered web UI (app/controllers/web)
    # needs cookies, the session and flash. /api/v1 is unaffected — its
    # controllers still inherit ActionController::API, which never reads the
    # session, and they authenticate with the bearer JWT as before.
    config.api_only = false

    # The web UI's session cookie: encrypted, HttpOnly, never sent cross-site
    # on a POST, HTTPS-only in production. It outlives the browser, as the
    # Angular app's JWT in localStorage does; the 7 days themselves are
    # enforced by Web::Authentication against the sign-in time it carries,
    # not by the cookie's own (sliding) expiry.
    config.session_store :cookie_store, key: "_fitora_session", same_site: :lax,
                                        secure: Rails.env.production?, httponly: true,
                                        expire_after: 7.days

    # The web UI speaks fr / en / ar. The default stays English so the API's
    # validation messages are unchanged. Its words are the translation files
    # brought over from the Angular app, read as they are
    # (config/locales/web/ng.rb, Web::Translations).
    config.i18n.available_locales = %i[en fr ar]
    config.i18n.load_path += [ Rails.root.join("config/locales/web/ng.rb") ]

    # bootstrap-icons' font files, which its stylesheet asks for as
    # url("./fonts/bootstrap-icons.woff2") — served by Propshaft from here.
    config.assets.paths << Rails.root.join("node_modules/bootstrap-icons/font")

    # Background jobs run on Sidekiq (see config/initializers/sidekiq.rb and
    # config/sidekiq_cron.yml). The default :async adapter is not persistent.
    config.active_job.queue_adapter = :sidekiq

    # Every table in this app uses a uuid primary key — Active Storage's own
    # tables (and their record_id/blob_id foreign keys) need to match, or
    # attaching a file to any model here fails.
    config.generators.orm :active_record, primary_key_type: :uuid
  end
end
