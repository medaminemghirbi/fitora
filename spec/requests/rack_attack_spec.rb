require "rails_helper"

# Disabled in test by default (config/initializers/rack_attack.rb) so it
# never makes unrelated specs flaky — enabled here, for these examples
# only, to prove the real throttle behaves as configured.
RSpec.describe "Rack::Attack throttling on login", type: :request do
  around do |example|
    Rack::Attack.enabled = true
    Rack::Attack.cache.reset!
    example.run
  ensure
    Rack::Attack.cache.reset!
    Rack::Attack.enabled = false
  end

  describe "POST /api/v1/auth/login" do
    it "throttles a single IP after too many attempts, regardless of the email tried" do
      60.times { |i| post "/api/v1/auth/login", params: { email: "nobody#{i}@example.test", password: "wrong" } }
      expect(response).to have_http_status(:unauthorized) # still under the limit — ordinary failed logins

      post "/api/v1/auth/login", params: { email: "nobody99@example.test", password: "wrong" }

      expect(response).to have_http_status(:too_many_requests)
      expect(response.parsed_body["error"]).to eq("rate_limited")
    end

    it "throttles repeated attempts against one email even from different IPs" do
      5.times { |i| post "/api/v1/auth/login", params: { email: "target@example.test", password: "wrong" }, headers: { "REMOTE_ADDR" => "10.0.0.#{i}" } }

      post "/api/v1/auth/login", params: { email: "target@example.test", password: "wrong" }, headers: { "REMOTE_ADDR" => "10.0.0.99" }

      expect(response).to have_http_status(:too_many_requests)
    end

    it "does not throttle a normal, low-volume login" do
      user = create(:user, :admin, password: "password123")

      post "/api/v1/auth/login", params: { email: user.email, password: "password123" }

      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /api/v1/password_resets" do
    it "throttles repeated reset requests from one IP" do
      5.times { post "/api/v1/password_resets", params: { email: "someone@example.test" } }

      post "/api/v1/password_resets", params: { email: "someone@example.test" }

      expect(response).to have_http_status(:too_many_requests)
    end
  end

  describe "POST /api/v1/email_verifications" do
    it "throttles repeated verification resends from one IP" do
      5.times { post "/api/v1/email_verifications", params: { email: "someone@example.test" } }

      post "/api/v1/email_verifications", params: { email: "someone@example.test" }

      expect(response).to have_http_status(:too_many_requests)
    end
  end

  # A stolen session should not be a way to guess the password behind it —
  # on the web UI's own forms too, not only on the API's.
  describe "password re-checks in the web UI" do
    let(:company) { create(:company, :pro, setup_dismissed_at: Time.current) }
    let(:wrong) { { current_password: "wrong", password: "new-password-1" } }

    it "throttles the admin's password change from one IP" do
      web_sign_in(company.admin)
      10.times { patch "/admin/#{company.id}/settings/password", params: wrong, as: :json }
      expect(response).to have_http_status(:unprocessable_content)

      patch "/admin/#{company.id}/settings/password", params: wrong, as: :json

      expect(response).to have_http_status(:too_many_requests)
    end

    it "throttles a member's password change and account deletion together" do
      subscription = Subscription.find_by!(admin_id: company.admin_id)
      subscription.issue_invoice!(issued_by: create(:user, :superadmin)) unless subscription.pro_features?
      member = create(:client, company: company)
      member.update!(password: "password123")
      web_sign_in(member)
      5.times { patch "/member/password", params: wrong, as: :json }
      5.times { delete "/member/account", params: { password: "wrong" }, as: :json }
      expect(response).to have_http_status(:unprocessable_content)

      delete "/member/account", params: { password: "wrong" }, as: :json

      expect(response).to have_http_status(:too_many_requests)
      expect(member.reload).to be_active
    end
  end

  it "leaves ordinary use of the API alone" do
    150.times { get "/api/v1/auth/me" }

    expect(response).not_to have_http_status(:too_many_requests)
  end

  # A ceiling on every call, not only the doors above (REQUEST_LIMITS):
  # per address, per login, and lower for writes. Stubbed small here.
  describe "every request" do
    let(:company) { create(:company, setup_dismissed_at: Time.current) }

    def limits(ip: 10_000, account: 10_000, account_writes: 10_000)
      stub_const("REQUEST_LIMITS", {
        ip: { limit: ip, period: 1.minute },
        account: { limit: account, period: 1.minute },
        account_writes: { limit: account_writes, period: 1.minute }
      })
    end

    it "throttles one API token, not the others, and says when to try again" do
      limits(account: 3)
      mine = auth_headers(company.admin)
      theirs = auth_headers(create(:company).admin)

      3.times { get "/api/v1/auth/me", headers: mine }
      expect(response).to have_http_status(:ok)
      get "/api/v1/auth/me", headers: mine

      expect(response).to have_http_status(:too_many_requests)
      expect(response.parsed_body["error"]).to eq("rate_limited")
      expect(response.headers["Retry-After"].to_i).to be_between(1, 60)
      get "/api/v1/auth/me", headers: theirs
      expect(response).to have_http_status(:ok)
    end

    it "throttles one signed-in session's pages" do
      limits(account: 3)
      web_sign_in(company.admin)

      3.times { get "/admin/#{company.id}/dashboard" }
      expect(response).to have_http_status(:ok)
      get "/admin/#{company.id}/dashboard"

      expect(response).to have_http_status(:too_many_requests)
    end

    it "holds writes to a lower ceiling than reads" do
      limits(account_writes: 2)
      mine = auth_headers(company.admin)

      2.times { post "/api/v1/notifications/read_all", headers: mine }
      expect(response).to have_http_status(:no_content)
      post "/api/v1/notifications/read_all", headers: mine

      expect(response).to have_http_status(:too_many_requests)
      get "/api/v1/auth/me", headers: mine
      expect(response).to have_http_status(:ok)
    end

    it "caps one address whoever is behind it, and leaves the uncounted paths alone" do
      limits(ip: 3)

      3.times { get "/connexion" }
      expect(response).to have_http_status(:ok)
      get "/connexion"
      expect(response).to have_http_status(:too_many_requests)

      get "/connexion", headers: { "REMOTE_ADDR" => "10.9.9.9" }
      expect(response).to have_http_status(:ok)
      5.times { get "/up" }
      expect(response).to have_http_status(:ok)
    end

    it "gives an API call without a session no session cookie" do
      limits
      get "/api/v1/auth/me", headers: auth_headers(company.admin)

      expect(response.headers["Set-Cookie"].to_s).not_to include("_fitora_session")
    end
  end
end
