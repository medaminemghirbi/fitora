# Brute-force protection for the real login endpoint — POST
# /api/v1/auth/login had no rate limiting at all until now: an attacker
# could try passwords as fast as the network allowed, for any account
# (admin/staff/client all share this one endpoint). Also lightly covers
# password-reset requests and admin self-registration, the other
# unauthenticated account surfaces, to stop them being scripted for
# inbox-spam or mass account creation.
#
# Disabled in test by default — spec/requests/rack_attack_spec.rb flips it
# on for the duration of its own examples only. Also disabled when running
# a local k6 load test (load_test/): every VU there shares one real source
# IP, which is nothing like the thousands of distinct IPs real concurrent
# traffic arrives from, so the per-IP throttle would just measure itself
# instead of the app. Never set DISABLE_RACK_ATTACK outside that.
Rack::Attack.enabled = !Rails.env.test? && ENV["DISABLE_RACK_ATTACK"] != "1"

# Shared across Puma workers (WEB_CONCURRENCY in config/deploy.yml) — an
# in-memory store would count separately per worker, making the limits
# below several times more permissive than they look. Redis is already a
# hard dependency (Sidekiq/ActionCable).
Rack::Attack.cache.store = ActiveSupport::Cache::RedisCacheStore.new(
  url: ENV.fetch("REDIS_URL", "redis://localhost:6379/1")
)

# Short, tight window — stops a fast automated guessing burst outright.
# Sized well above what real concurrent traffic from one IP looks like
# (a gym's own front-desk wifi, an office, mobile carrier NAT/CGNAT can
# put a lot of genuine simultaneous logins behind one address — a load
# test surfaced this throttling out nearly all of them at 5/20s) — the
# per-email throttle below is the real brute-force defense; this one is
# a backstop against a single-IP flood, not the primary defense.
# The API's login and the web UI's sign-in form (Web::SessionsController)
# are the same door: one budget for both — and the console's, password and
# code (Web::Superadmin::SessionsController), on the same.
LOGIN_PATHS = %w[/api/v1/auth/login /connexion /superadmin/connexion /superadmin/connexion/code].freeze

Rack::Attack.throttle("logins/ip/burst", limit: 60, period: 20.seconds) do |req|
  req.ip if req.post? && LOGIN_PATHS.include?(req.path)
end

# Longer window, higher ceiling — catches a slower attempt that stays
# under the burst limit but is still clearly not a human typing a password.
Rack::Attack.throttle("logins/ip/sustained", limit: 300, period: 5.minutes) do |req|
  req.ip if req.post? && LOGIN_PATHS.include?(req.path)
end

# Keyed on the attempted email rather than the caller's IP — the burst/
# sustained throttles above are per-IP, so a distributed attempt (many
# IPs, one targeted account) would sail through both. Cheaply defeated by
# also throttling per email tried, regardless of source. This is the throttle
# that actually stops password guessing — it stays tight regardless of the
# per-IP limits above, since it doesn't matter how many legitimate logins
# share an IP if only one of them is for the account being guessed.
#
# Three windows on the same key. The 20-second one alone still allowed about
# 21,600 guesses a day against one account; the hourly and daily ceilings
# bring that to 50, while someone who mistypes a few times in a row is only
# ever held back by the short one.
login_email = lambda do |req|
  next unless req.post? && LOGIN_PATHS.include?(req.path)

  req.params["email"].to_s.downcase.strip.presence
end
Rack::Attack.throttle("logins/email", limit: 5, period: 20.seconds, &login_email)
Rack::Attack.throttle("logins/email/hour", limit: 20, period: 1.hour, &login_email)
Rack::Attack.throttle("logins/email/day", limit: 50, period: 1.day, &login_email)

# Every endpoint that takes a password to prove who you are, other than
# login: changing it, and deleting a member account. Signed in already, but a
# stolen token should not be a way to guess the password behind it.
PASSWORD_CHECKS = [
  [ "PATCH", "/api/v1/auth/password" ],
  [ "DELETE", "/api/v1/me/account" ]
].freeze
# …and their twins in the web UI: the admin shell's (the salle is in the
# path) and the member's own.
WEB_PASSWORD_CHECKS = [
  [ "PATCH", %r{\A/admin/[0-9a-f-]{36}/settings/password\z} ],
  [ "PATCH", %r{\A/member/password\z} ],
  [ "DELETE", %r{\A/member/account\z} ]
].freeze
Rack::Attack.throttle("password_checks/ip", limit: 10, period: 5.minutes) do |req|
  req.ip if PASSWORD_CHECKS.include?([ req.request_method, req.path ]) ||
            WEB_PASSWORD_CHECKS.any? { |method, path| req.request_method == method && req.path.match?(path) }
end

# The web UI's twins of those endpoints: the token is in the form, not the path.
WEB_EMAILED_TOKENS = %w[/auth/reset-password /auth/accept-invitation /verify-email].freeze

# The emailed-token endpoints: accepting an invitation, finishing a reset,
# confirming an address. The tokens are 256 bits and not guessable, but
# nothing unauthenticated should take unlimited attempts.
Rack::Attack.throttle("emailed_tokens/ip", limit: 10, period: 1.minute) do |req|
  req.ip if req.patch? && (req.path.match?(%r{\A/api/v1/(invitations|password_resets|email_verifications)/[^/]+\z}) || WEB_EMAILED_TOKENS.include?(req.path))
end

Rack::Attack.throttle("password_resets/ip", limit: 5, period: 1.minute) do |req|
  req.ip if req.post? && %w[/api/v1/password_resets /mot-de-passe-oublie].include?(req.path)
end

# Signing up is unauthenticated, creates a User and emails the address given,
# with no ownership check. Unthrottled, a script could mass-create accounts or
# use Fitora's own mailer to bomb a third party's inbox.
Rack::Attack.throttle("register/ip", limit: 5, period: 10.minutes) do |req|
  req.ip if req.post? && %w[/api/v1/auth/register /inscription].include?(req.path)
end

# Re-sending a verification email is unauthenticated and mails whatever
# address it is given — the same inbox-bombing surface as a password reset,
# and it was the one account-mail endpoint with no ceiling on it.
Rack::Attack.throttle("email_verifications/ip", limit: 5, period: 1.minute) do |req|
  req.ip if req.post? && %w[/api/v1/email_verifications /confirmation-email/resend].include?(req.path)
end

# The API's paths answer {error: "rate_limited"}; the web UI's forms answer
# with their own page, refused (Web::RateLimit).
Rack::Attack.throttled_responder = ->(request) { Web::RateLimit.respond(request) }

# The mobile app's key lookup is public: a coach key lists a salle's team.
# Keys are long and random, but nothing unauthenticated takes unlimited
# guesses.
Rack::Attack.throttle("app_config/ip", limit: 20, period: 1.minute) do |req|
  req.ip if req.get? && req.path.match?(%r{\A/api/v1/tenants/[^/]+/app_config\z})
end

# ---- Every request ---------------------------------------------------------
# A ceiling on every call, not only the doors above: well over what a person,
# a page or the mobile app does, so only a flood, a scraper or a runaway
# script meets it. Not counted: built assets, the health check, the live
# connection, Active Storage's file links and the Sidekiq dashboard — a page
# loads several of them, and none of them runs the app's own code.
UNCOUNTED_PATHS = %r{\A/(assets/|cable|up\z|rails/active_storage/|sidekiq)}

# Read on each request (the throttles take them as lambdas), so a spec can
# stub them.
REQUEST_LIMITS = {
  # Everyone behind one gym's wifi, or a carrier's NAT, shares an address.
  ip: { limit: 3000, period: 5.minutes },
  # One login: a bearer token on the API, a signed-in session on the pages.
  account: { limit: 300, period: 1.minute },
  # …of which writes (POST, PATCH, PUT, DELETE).
  account_writes: { limit: 60, period: 1.minute }
}.freeze

# Who is asking, for counting only (the controllers still check it): a digest
# of the bearer token — never the token itself as a Redis key — or the
# account the encrypted session names. The session is read only when its
# cookie came with the request: loading it for an API call would send that
# call a session cookie it never had.
request_account = lambda do |req|
  if (bearer = req.get_header("HTTP_AUTHORIZATION").presence)
    "token:#{Digest::SHA256.hexdigest(bearer)}"
  elsif req.cookies.key?(Rails.application.config.session_options[:key])
    claims = req.session[Web::Authentication::SESSION_KEY.to_s]
    "#{claims['kind']}:#{claims['id']}" if claims.is_a?(Hash)
  end
end
counted = ->(req) { !req.path.match?(UNCOUNTED_PATHS) }
request_limit = ->(name) { { limit: ->(_req) { REQUEST_LIMITS.fetch(name)[:limit] }, period: ->(_req) { REQUEST_LIMITS.fetch(name)[:period] } } }

Rack::Attack.throttle("requests/ip", **request_limit.(:ip)) do |req|
  req.ip if counted.(req)
end

Rack::Attack.throttle("requests/account", **request_limit.(:account)) do |req|
  request_account.(req) if counted.(req)
end

Rack::Attack.throttle("writes/account", **request_limit.(:account_writes)) do |req|
  request_account.(req) if counted.(req) && !(req.get? || req.head?)
end
