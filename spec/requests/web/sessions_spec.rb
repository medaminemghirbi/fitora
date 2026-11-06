require "rails_helper"

# The web UI's sign-in (MIGRATION_AUDIT §9.1, §12.4 items 1–2).
# openapi: false — the contract is the API's (spec/rails_helper.rb).
RSpec.describe "Web sign-in", type: :request, openapi: false do
  let(:company) { create(:company, setup_dismissed_at: Time.current) }
  let(:admin) { company.admin }

  describe "GET /connexion" do
    it "renders the Angular sign-in page's markup, scoped as Angular scopes it" do
      get "/connexion"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('<app-pro-login _nghost-pro-login="">')
      expect(response.body).to include('_ngcontent-auth-pro-shell="" class="apro"')
      expect(response.body).to include("Se connecter")
    end

    it "sends someone already signed in home (guestGuard)" do
      web_sign_in(admin)
      get "/connexion"

      expect(response).to redirect_to("/admin/#{company.id}/dashboard")
    end
  end

  describe "POST /connexion — where each kind of account lands (B-01)" do
    it "an admin whose setup is done: the dashboard" do
      web_sign_in(admin)
      expect(response).to redirect_to("/admin/#{company.id}/dashboard")
    end

    it "a new admin: onboarding first" do
      company.update!(setup_dismissed_at: nil)
      web_sign_in(admin)
      expect(response).to redirect_to("/admin/#{company.id}/onboarding")
    end

    it "a login with no salle: the page that says so, and no way into a shell" do
      lonely = create(:user, :admin)
      web_sign_in(lonely)
      expect(response).to redirect_to("/sans-salle")
      follow_redirect!
      expect(response.body).to include(Web::Translations.translate("auth.no_salle_title", locale: :fr), "contact@fitora.io")
    end

    it "an admin whose first sign-in is unfinished: the form that finishes it" do
      admin.update!(terms_accepted_at: nil)
      web_sign_in(admin)
      expect(response).to redirect_to("/premiere-connexion")
    end

    it "an admin whose address is not confirmed: the inbox screen" do
      admin.update!(email_verified_at: nil)
      web_sign_in(admin)
      expect(response).to redirect_to("/confirmation-email")
    end

    it "staff without the dashboard: the schedule" do
      role = create(:role, company: company, permissions: %w[clients])
      staff = create(:staff_member, company: company, assigned_role: role).user
      web_sign_in(staff)
      expect(response).to redirect_to("/admin/#{company.id}/calendar")
    end

    it "front-desk staff (check-in and bookings): the desk, in their salle" do
      role = create(:role, company: company, permissions: %w[checkin bookings clients])
      staff = create(:staff_member, company: company, assigned_role: role).user
      web_sign_in(staff)
      expect(response).to redirect_to("/desk/#{company.id}/dashboard")
    end

    it "a coach: their own day, in their salle" do
      coach = create(:staff_member, company: company, role: :coach).user
      web_sign_in(coach)
      expect(response).to redirect_to("/coach/#{company.id}/today")
    end

    it "the platform superadmin: the console" do
      web_sign_in(create(:user, :superadmin))
      expect(response).to redirect_to("/superadmin/overview")
    end

    it "takes the salle's own language, as the Angular app does from /bootstrap" do
      company.update!(locale: "ar")
      web_sign_in(admin)
      expect(cookies[:fitora_locale]).to eq("ar")
    end
  end

  describe "POST /connexion — refusals" do
    it "a wrong password: the translated message, not the API's English (B-02)" do
      web_sign_in(admin, password: "nope")

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("E-mail ou mot de passe invalide")
      expect(response.body).not_to include("Invalid email or password")
    end

    it "an empty form: both fields required, and nothing is checked" do
      expect(SignIn).not_to receive(:call)
      post "/connexion", params: { email: "", password: "" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body.scan(%(data-check-error=)).size).to eq(2)
    end

    it "a malformed address counts as missing, as Validators.email makes it" do
      post "/connexion", params: { email: "not-an-address", password: "x" }
      expect(response.body).to include(%(data-check-error="email"))
    end

    it "a suspended account: the admin and the team are told, once the password has checked out" do
      staff = create(:staff_member, company: company, role: :moderator).user
      SuperadminActions.suspend_access(company, by: create(:user, :superadmin))
      words = CGI.escapeHTML(Web::Translations.translate("auth.access_suspended", locale: :fr))

      [ admin, staff ].each do |login|
        web_sign_in(login)
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include(words)

        web_sign_in(login, password: "wrong-password")
        expect(response.body).not_to include(words)
      end
    end

    it "a suspended account's members still sign in to their own app" do
      member = create(:client, company: company, email: "m@example.com")
      member.update!(password: "password123")
      SuperadminActions.suspend_access(company, by: create(:user, :superadmin))

      web_sign_in(member)

      expect(response).to redirect_to("/member/home")
    end

    it "ends a session already open when the account is suspended" do
      company.update!(setup_dismissed_at: Time.current)
      web_sign_in(admin)
      get "/admin/#{company.id}/dashboard"
      expect(response).to have_http_status(:ok)

      SuperadminActions.suspend_access(company, by: create(:user, :superadmin))

      get "/admin/#{company.id}/dashboard"
      expect(response).to redirect_to("/connexion")
    end

    it "a member who has left their last gym" do
      member = create(:client, company: company, email: "m@example.com")
      member.update!(password: "password123")
      member.memberships.destroy_all
      web_sign_in(member)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(CGI.escapeHTML(Web::Translations.translate("auth.no_gym", locale: :fr)))
    end

    it "an inactive account" do
      admin.update!(active: false)
      web_sign_in(admin)
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "the session" do
    it "signs out" do
      web_sign_in(admin)
      delete "/deconnexion"
      get "/admin/#{company.id}/clients"

      expect(response).to redirect_to("/connexion")
    end

    it "stays signed out for a copy of the cookie kept from before signing out" do
      web_sign_in(admin)
      copy = cookies[:_fitora_session]
      delete "/deconnexion"

      cookies[:_fitora_session] = copy
      get "/admin/#{company.id}/clients"
      expect(response).to redirect_to("/connexion")
    end

    it "leaves the account's other sessions open when one signs out" do
      web_sign_in(admin)
      other_browser = cookies[:_fitora_session]
      reset! # a second browser
      web_sign_in(admin)
      delete "/deconnexion"

      cookies[:_fitora_session] = other_browser
      get "/admin/#{company.id}/clients"
      expect(response).to have_http_status(:ok)
    end

    it "ends when the account signs out everywhere (token_version), like a JWT" do
      web_sign_in(admin)
      admin.revoke_all_tokens!
      get "/admin/#{company.id}/clients"

      expect(response).to redirect_to("/connexion")
    end

    it "outlives the browser (a persistent cookie), as the JWT in localStorage does" do
      web_sign_in(admin)
      expect(response.headers["Set-Cookie"].to_s).to match(/_fitora_session=.*expires=/i)
    end

    it "ends seven days after signing in, like a JWT" do
      web_sign_in(admin)
      travel(JwtService::EXPIRATION + 1.minute) do
        get "/admin/#{company.id}/clients"
        expect(response).to redirect_to("/connexion")
      end
    end

    it "is refused once the account is deactivated" do
      web_sign_in(admin)
      admin.update!(active: false)
      get "/admin/#{company.id}/clients"

      expect(response).to redirect_to("/connexion")
    end
  end

  describe "PATCH /locale (D6)" do
    it "remembers the language and returns to the same page, query string and all" do
      patch "/locale", params: { locale: "ar", return_to: "/connexion?x=1" }

      expect(response).to redirect_to("/connexion?x=1")
      expect(cookies[:fitora_locale]).to eq("ar")
      get "/connexion"
      expect(response.body).to include('lang="ar"', 'dir="rtl"')
    end

    it "never sends anyone off the site" do
      patch "/locale", params: { locale: "fr", return_to: "//evil.example" }
      expect(response).to redirect_to("/connexion")
    end
  end
end
