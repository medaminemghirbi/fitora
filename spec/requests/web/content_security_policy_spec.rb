require "rails_helper"

# The web UI's Content-Security-Policy (config/initializers/
# content_security_policy.rb): enforced, unless CSP_REPORT_ONLY is set.
# openapi: false — not part of the API's contract.
RSpec.describe "Web content security policy", type: :request, openapi: false do
  it "enforces the policy" do
    get "/connexion"

    expect(response.headers).not_to have_key("Content-Security-Policy-Report-Only")
    policy = response.headers["Content-Security-Policy"]
    expect(policy).to include("default-src 'self'", "script-src 'self'", "object-src 'none'", "base-uri 'self'",
                              "frame-ancestors 'none'", "form-action 'self'", "https://fonts.googleapis.com", "https://fonts.gstatic.com")
    expect(policy).not_to include("unsafe-eval")
    expect(policy[/script-src [^;]*/]).not_to include("unsafe-inline")
  end

  # The views' inline scripts are JSON for the page's code to read, which a
  # browser never runs: script-src 'self' leaves them alone. A script a
  # browser would run has to come from this origin.
  it "has no inline script on a page that the policy would block" do
    admin = create(:user, :admin)
    company = create(:company, admin: admin, setup_dismissed_at: Time.current)
    web_sign_in(admin)

    [ "/connexion", "/admin/#{company.id}/dashboard", "/admin/#{company.id}/clients", "/admin/#{company.id}/settings" ].each do |path|
      get path
      Nokogiri::HTML(response.body).css("script:not([src])").each do |script|
        expect(script["type"]).to match(%r{\Aapplication/(ld\+)?json\z}), "#{path}: #{script.to_html[0, 80]}"
      end
      expect(response.body).not_to match(/\son[a-z]+=["']/i), "#{path} has an inline event handler"
    end
  end
end
