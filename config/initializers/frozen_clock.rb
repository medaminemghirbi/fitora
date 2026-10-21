# A stopped clock for the parity screenshots (MIGRATION_AUDIT §12.1): the
# Angular reference and the Rails pages are compared pixel for pixel, and
# "today", "in 3 days" and "last seen 2 hours ago" have to read the same on
# both sides — and on every run. The demo seed is run under the same clock,
# so its relative dates land on the same days too.
#
#   FITORA_FROZEN_TIME=2026-10-14T10:00:00+01:00 bin/rails server
#
# Never in production: a server whose clock does not move would never expire
# a token, a trial or a contract.
if (frozen_at = ENV["FITORA_FROZEN_TIME"].presence)
  raise "FITORA_FROZEN_TIME is for development and test only" if Rails.env.production?

  require "active_support/testing/time_helpers"

  Rails.application.config.after_initialize do
    Object.new.extend(ActiveSupport::Testing::TimeHelpers).travel_to(Time.iso8601(frozen_at))
  end

  # The browser judges a cookie's Expires by its own clock, which moves. A
  # session cookie dated "7 days after the frozen instant" is already in the
  # past once a week has gone by for real, and the browser drops it on
  # arrival (no session, so every form fails its CSRF check). Under a stopped
  # clock the cookie lasts for the browser session instead; the session's own
  # 7-day limit (Web::Authentication) is still checked, on the server's clock.
  Rails.application.config.session_options.delete(:expire_after)
end
