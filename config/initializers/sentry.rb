# Error tracking — unhandled exceptions used to only ever surface via a
# support ticket, never automatically. Safely a no-op with no SENTRY_DSN
# set (dev/test never send anywhere); set it in production once the
# project exists in Sentry (see config/deploy.yml's secret list).
#
# sentry-rails (loaded via Bundler.require) hooks in on its own — request
# exceptions, with Rails' own config.filter_parameters (already scrubs
# password/email/token/etc, see filter_parameter_logging.rb) applied
# automatically. sentry-sidekiq does the same for background jobs, which
# otherwise fail completely silently: no request, no user watching, nothing.
Sentry.init do |config|
  config.dsn = ENV["SENTRY_DSN"]
  config.environment = Rails.env

  # Error tracking only — no performance/APM tracing (that's a separate,
  # quota-costing decision to make later; leave at 0 until then).
  config.traces_sample_rate = 0.0

  # Company/user context is attached per-request from
  # ApplicationController#tag_sentry_context! instead — not global here.
  config.breadcrumbs_logger = [ :active_support_logger ]

  # sentry-sidekiq copies the failed job's whole payload, "args" included,
  # into the event's sidekiq context, and ignores data_collection.queues
  # when it does. A mail job's args hold the raw token of a reset or
  # invitation link (see action_mailer.rb), so an SMTP outage would ship
  # working links to Sentry. Jobs load their records by id, so the class,
  # jid and retry count are what a report needs; the args are dropped.
  # sentry-rails' own Active Job reporting (adapters other than Sidekiq)
  # puts them under extra[:arguments].
  config.before_send = lambda do |event, _hint|
    sidekiq = event.contexts[:sidekiq]
    if sidekiq.is_a?(Hash)
      sidekiq.delete("args")
      sidekiq.delete(:args)
    end
    event.extra&.delete(:arguments)
    event
  end
end
