require "rails_helper"

# The sweep: every route the app answers, asked without a token.
#
# The other files in this directory each test a rule someone thought of. This
# one tests the rule nobody has to remember: a controller added next month is
# covered the day its route is drawn, because the list comes from the router
# rather than from a spec someone maintains.
#
# A route that is genuinely public must be named in PUBLIC below. Adding a
# name is a deliberate act with a reason next to it; forgetting to add one is
# a failing build, which is the right way round.
RSpec.describe "Every route is closed by default", type: :request do
  # The unauthenticated surface, in full. Everything here either creates a
  # session or is reached from a link in an email, where the token in the URL
  # is the credential.
  PUBLIC = [
    %r{\A/api/v1/auth/login\z},
    %r{\A/api/v1/password_resets},
    %r{\A/api/v1/email_verifications},
    # A member accepting their gym's invitation — the emailed token is the
    # credential, and they have no password until this sets one.
    %r{\A/api/v1/invitations},
    # Version check — the client asks before it has a session, to tell
    # someone their app is out of date.
    %r{\A/api/v1/app_version\z},
    # The mobile app becoming one salle's app before anyone signs in: the
    # salle's member code or coach key in the URL is the credential (long,
    # random, regeneratable, throttled — Api::V1::TenantsController).
    %r{\A/api/v1/tenants/[^/]+/app_config\z},
    # Health check.
    %r{\A/up\z}
  ].freeze

  # Not part of the API surface: Sidekiq's dashboard has its own HTTP basic
  # auth, and the catch-all only redirects to the landing page.
  IGNORED = [ %r{\A/sidekiq}, /\*path/ ].freeze

  # Every concrete (verb, path) the router will answer, with an id in place
  # of each dynamic segment. The id is a well-formed UUID that matches
  # nothing: authentication runs before any lookup, so the answer must be 401
  # regardless — if it is 404, something looked the record up first.
  def self.api_routes
    Rails.application.routes.routes.filter_map do |route|
      spec = route.path.spec.to_s.sub(/\(\.:format\)\z/, "")
      next if IGNORED.any? { |re| spec.match?(re) }
      next unless spec.start_with?("/api/", "/up")

      verb = route.verb.to_s.presence || "GET"
      next if PUBLIC.any? { |re| spec.match?(re) }

      path = spec.gsub(/:[a-z_]+/, "00000000-0000-4000-8000-000000000000")
      [ verb.downcase.to_sym, path ]
    end.uniq
  end

  ROUTES = api_routes.freeze

  it "finds the routes to sweep at all" do
    # A refactor that breaks the enumeration would otherwise turn this whole
    # file into a silent pass.
    expect(ROUTES.size).to be > 60
    expect(ROUTES).to include([ :get, "/api/v1/clients" ])
  end

  ROUTES.each do |verb, path|
    it "#{verb.to_s.upcase} #{path} refuses an anonymous caller" do
      public_send(verb, path, headers: { "CONTENT_TYPE" => "application/json" })

      expect(response).to have_http_status(:unauthorized),
        "#{verb.to_s.upcase} #{path} answered #{response.status} without a token. " \
        "Either it inherits from Api::V1::BaseController, or it belongs in PUBLIC with a reason."
    end
  end
end

# The other sweep: an admin who has not finished their first sign-in.
#
# The gate lives in one before_action on Api::V1::BaseController, which is
# exactly the kind of thing a new controller can opt out of by accident (a
# stray `skip_before_action`, or not inheriting from the base at all). Rather
# than trust that, ask every operational endpoint.
RSpec.describe "A first sign-in unfinished answers nothing operational", type: :request do
  let(:admin) { create(:user, :admin, :first_sign_in) }
  let!(:company) { create(:company, admin: admin) }

  # Reads only. `/superadmin` is the platform operator, not this tenant. `/me`
  # is a member's own login. `/bootstrap` skips the gate on purpose, so the
  # client can route to the right screen, and `/auth/me` is on AuthController
  # rather than the base for the same reason.
  EXEMPT = %r{\A/api/v1/(superadmin|me)/|\A/api/v1/(bootstrap|app_version|auth/me)\z|\A/api/v1/tenants/[^/]+/app_config\z}

  SWEPT = ROUTES.select { |verb, path| verb == :get && !path.match?(EXEMPT) }.freeze

  it "has operational endpoints to sweep" do
    expect(SWEPT.size).to be > 20
  end

  SWEPT.each do |_verb, path|
    it "GET #{path} refuses them" do
      get path, headers: auth_headers(admin)

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body["error"]).to eq("first_sign_in_required"),
        "GET #{path} answered #{response.status} for an unfinished first sign-in. " \
        "The gate is one before_action on Api::V1::BaseController; this endpoint got past it."
    end
  end
end
