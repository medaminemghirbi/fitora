require "rails_helper"

# The session's crossings while some shells are still Angular's
# (MIGRATION_AUDIT §9.3), and a shell switched back to Angular (§8.4).
# openapi: false.
RSpec.describe "Web session hand-off", type: :request, openapi: false do
  let(:company) { create(:company, setup_dismissed_at: Time.current) }
  let(:desk) { create(:staff_member, company: company, role: :moderator) }

  def serve(*shells)
    allow(Web::Routing).to receive(:shells).and_return(shells.map(&:to_s))
  end

  describe "Rails → Angular" do
    before { serve(:admin) }

    it "sends a login whose home is an Angular shell through the hand-off" do
      web_sign_in(desk.user)
      expect(response).to redirect_to("/session/handoff?to=%2Fdesk%2F#{company.id}%2Fdashboard")
    end

    it "writes the Angular app's session — a token ending with this session — then opens its route" do
      web_sign_in(desk.user)
      get "/session/handoff", params: { to: "/desk/#{company.id}/dashboard" }

      expect(response.body).to include("location.replace(\"/desk/dashboard\")", %("#{company.id}"))
      token = response.body[/"fitora_token":"([^"]+)"/, 1]
      claims = JwtService.decode(token)
      expect(claims[:user_id]).to eq(desk.user.id)
      expect(claims[:expires_at]).to be_within(5.seconds).of(JwtService::EXPIRATION.from_now)
      expect(response.body).to include("fitora_user_v2")
    end

    it "answers a path Rails serves with that path, and never another site's" do
      web_sign_in(desk.user)
      get "/session/handoff", params: { to: "/admin/#{company.id}/clients" }
      expect(response).to redirect_to("/admin/#{company.id}/clients")
      get "/session/handoff", params: { to: "//evil.example" }
      expect(response).to redirect_to("/connexion")
    end
  end

  describe "Angular → Rails" do
    before { serve(:desk) }

    it "asks the Angular app for its session before sending anyone to sign in" do
      get "/desk/#{company.id}/dashboard"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("fitora_token", "/session/exchange")
    end

    it "turns a valid Angular token into the cookie session, keeping its end" do
      token = JwtService.for_user(desk.user)
      get "/desk/#{company.id}/dashboard"
      post "/session/exchange", params: { token: token, to: "/desk/#{company.id}/dashboard", locale: "ar", theme: "dark" }

      expect(response).to redirect_to("/desk/#{company.id}/dashboard")
      expect(cookies[:fitora_locale]).to eq("ar")
      get "/desk/#{company.id}/dashboard"
      expect(response.body).to include("desk-topbar")
    end

    it "refuses a token signed out everywhere, and clears the Angular app's keys" do
      token = JwtService.for_user(desk.user)
      desk.user.revoke_all_tokens!
      get "/desk/#{company.id}/dashboard"
      post "/session/exchange", params: { token: token, to: "/desk/#{company.id}/dashboard" }
      expect(response.body).to include("localStorage.removeItem", "fitora_token")
    end

    it "carries an impersonation across with the superadmin's own session to return to" do
      superadmin = create(:user, :superadmin)
      serve(:admin, :superadmin)
      get "/connexion"
      post "/session/exchange", params: {
        token: JwtService.for_user(company.admin, impersonator: superadmin), impersonator_token: JwtService.for_user(superadmin),
        company_name: company.name, to: "/admin/#{company.id}/dashboard"
      }
      get "/admin/#{company.id}/dashboard"
      expect(response.body).to include("impersonation-banner", company.name)

      delete "/deconnexion"
      expect(response).to redirect_to("/superadmin/overview")
    end

    it "ends the cookie session when the Angular app logs out" do
      post "/session/exchange", params: { token: JwtService.for_user(desk.user), to: "/desk/#{company.id}/dashboard" }
      delete "/session"
      expect(response).to have_http_status(:no_content)
      get "/desk/#{company.id}/dashboard"
      expect(response.body).to include("/session/exchange")
    end
  end

  it "clears the Angular app's session too when signing out during the transition" do
    serve(:admin)
    web_sign_in(company.admin)
    delete "/deconnexion"
    expect(response.body).to include("localStorage.removeItem", "location.replace(\"/connexion\")")
  end

  it "keeps a shell's Rails URLs working once it is switched back to Angular (§8.4)" do
    serve(:desk)
    get "/admin/#{company.id}/clients?status=active"
    expect(response).to redirect_to("/admin/clients?status=active")
  end
end
