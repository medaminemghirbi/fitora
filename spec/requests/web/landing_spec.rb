require "rails_helper"

# The landing page (module 11). openapi: false — the contract is the API's
# (spec/rails_helper.rb).
RSpec.describe "Web landing page", type: :request, openapi: false do
  it "renders LandingComponent's markup, scoped as Angular scopes it" do
    get "/"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('<app-landing _nghost-landing="">', '<div _ngcontent-landing="" class="lp"')
    expect(response.body).to include(%(href="/#pricing"), %(href="/inscription"), %(href="/connexion"))
  end

  it "says what today is in the page's language, in the platform's time zone (M-06)" do
    travel_to Time.utc(2026, 10, 13, 23, 30) do # already the 14th in Tunis
      get "/"
      expect(response.body).to include("Mercredi 14 octobre")
      expect(response.body).to include("© 2026 Fitora.")
    end
  end

  it "prints both periods' prices, the year's after the discount, grouped as Chromium groups French" do
    get "/"
    expect(response.body).to include(%(data-monthly="165" data-yearly="1 782"), %(data-monthly="249" data-yearly="2 689,20"))
  end

  it "comes in the language the visitor chose, right to left in Arabic" do
    cookies[:fitora_locale] = "ar"
    get "/"
    expect(response.body).to include('<html lang="ar"', 'dir="rtl"')
    expect(response.body).to include(Web::Translations.translate("landing.hero_cta_primary", locale: :ar))
  end

  describe "the Angular app's other redirects (app.routes.ts)" do
    it "the earlier layouts' addresses, the query kept" do
      {
        "/trial-expired" => "/account-locked", "/pro" => "/", "/pro/connexion" => "/connexion",
        "/pro/mot-de-passe-oublie" => "/mot-de-passe-oublie", "/auth/login" => "/connexion",
        "/auth/register" => "/inscription", "/auth/forgot-password" => "/mot-de-passe-oublie", "/gyms" => "/"
      }.each do |from, to|
        get from
        expect(response).to redirect_to(to), from
      end
      get "/auth/register", params: { email: "a@b.tn" }
      expect(response).to redirect_to("/inscription?email=a%40b.tn")
    end

    it "`**` → \"\": any other page, a member's and the console's too" do
      %w[/nowhere /member/nowhere /superadmin/nowhere/at/all].each do |path|
        get path
        expect(response).to redirect_to("/"), path
      end
    end
  end

  it "guestGuard: a signed-in admin goes to their home" do
    company = create(:company, setup_dismissed_at: Time.current)
    web_sign_in(company.admin)
    get "/"
    expect(response).to redirect_to("/admin/#{company.id}/dashboard")
  end
end
