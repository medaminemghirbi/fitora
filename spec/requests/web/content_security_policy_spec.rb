require "rails_helper"

# The web UI's Content-Security-Policy (config/initializers/
# content_security_policy.rb): reported, not enforced, until CSP_ENFORCE is
# set. openapi: false — not part of the API's contract.
RSpec.describe "Web content security policy", type: :request, openapi: false do
  it "sends the policy as report-only by default" do
    get "/connexion"

    expect(response.headers).not_to have_key("Content-Security-Policy")
    policy = response.headers["Content-Security-Policy-Report-Only"]
    expect(policy).to include("default-src 'self'", "script-src 'self'", "object-src 'none'", "base-uri 'self'",
                              "frame-ancestors 'none'", "https://fonts.googleapis.com", "https://fonts.gstatic.com")
    expect(policy).not_to include("unsafe-eval")
  end
end
