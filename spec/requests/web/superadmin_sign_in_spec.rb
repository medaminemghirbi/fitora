require "rails_helper"

# The console's own door (Web::Superadmin::SessionsController): the
# password, then an authenticator app's code (TwoFactor) — and no other door
# for a superadmin, on the web or the API.
RSpec.describe "The superadmin's sign-in", type: :request, openapi: false do
  let(:superadmin) { create(:user, :superadmin, email: "ops@fitora.tn", password: "password123") }

  def sign_in_password(email: superadmin.email, password: "password123")
    post "/superadmin/connexion", params: { email: email, password: password }
  end

  def enter_code(code)
    post "/superadmin/connexion/code", params: { otp: code }
  end

  def signed_in?
    get "/superadmin/overview"
    response.status == 200
  end

  describe "the other doors" do
    it "/connexion refuses a superadmin's right password as it refuses a wrong one" do
      post "/connexion", params: { email: superadmin.email, password: "password123" }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(Web::Translations.translate("auth.invalid_credentials", locale: :fr))
      expect(signed_in?).to be(false)
    end

    it "so does the API's login" do
      post "/api/v1/auth/login", params: { email: superadmin.email, password: "password123" }
      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body).not_to have_key("token")
    end

    it "the console, signed out, sends to its own sign-in; signing out of it lands there" do
      get "/superadmin/companies"
      expect(response).to redirect_to("/superadmin/connexion")

      web_sign_in(superadmin)
      delete "/deconnexion"
      expect(response).to redirect_to("/superadmin/connexion")
    end
  end

  describe "the first sign-in: setting the app up" do
    it "shows a QR code and its key, and turns the app on with the code it makes" do
      sign_in_password
      expect(response).to redirect_to("/superadmin/connexion/code")
      expect(signed_in?).to be(false)

      get "/superadmin/connexion/code"
      expect(response.headers["Cache-Control"]).to include("no-store")
      expect(response.body).to include('class="sa-2fa-qr"', Web::Translations.translate("superadmin.two_factor.setup_title", locale: :fr))
      secret = response.body[%r{<code[^>]*>([A-Z2-7 ]+)</code>}, 1].delete(" ")

      enter_code("000000")
      expect(response).to have_http_status(:unprocessable_content)
      expect(superadmin.reload.two_factor_enabled?).to be(false)

      enter_code(ROTP::TOTP.new(secret).now)
      expect(response).to redirect_to("/superadmin/overview")
      expect(superadmin.reload.two_factor_enabled?).to be(true)
      expect(superadmin.otp_secret_ciphertext).not_to include(secret)
      expect(signed_in?).to be(true)
    end
  end

  describe "with the app set up" do
    let!(:secret) { enable_two_factor(superadmin) }

    it "asks for its code, with no QR code, and opens the console with it" do
      sign_in_password
      follow_redirect!
      expect(response.body).not_to include("sa-2fa-qr")
      expect(response.body).to include(Web::Translations.translate("superadmin.two_factor.code_title", locale: :fr))

      enter_code(ROTP::TOTP.new(secret).now)
      expect(response).to redirect_to("/superadmin/overview")
      expect(signed_in?).to be(true)
    end

    it "takes a code for its own 30 seconds only, as the app shows it" do
      step = Time.zone.at(Time.now.to_i / 30 * 30)
      totp = ROTP::TOTP.new(secret)
      travel_to step + 5.seconds
      sign_in_password

      enter_code(totp.at(step + 30.seconds))
      expect(response).to have_http_status(:unprocessable_content)
      travel_to step + 31.seconds
      enter_code(totp.at(step))
      expect(response).to have_http_status(:unprocessable_content)

      travel_to step + 29.seconds
      enter_code(totp.at(step))
      expect(response).to redirect_to("/superadmin/overview")
    end

    it "takes a code once" do
      code = ROTP::TOTP.new(secret).now
      sign_in_password
      enter_code(code)
      delete "/deconnexion"

      sign_in_password
      enter_code(code)
      expect(response).to have_http_status(:unprocessable_content)
      expect(signed_in?).to be(false)
    end

    it "refuses a wrong password as /connexion does, and an admin's right one" do
      sign_in_password(password: "nope-nope")
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(Web::Translations.translate("auth.invalid_credentials", locale: :fr))

      sign_in_password(email: create(:company).admin.email)
      expect(response).to have_http_status(:unprocessable_content)
      get "/superadmin/connexion/code"
      expect(response).to redirect_to("/superadmin/connexion")
    end

    it "sends back to the password after five wrong codes" do
      sign_in_password
      4.times { enter_code("000000") }
      expect(response).to have_http_status(:unprocessable_content)

      enter_code("000000")
      expect(response).to redirect_to("/superadmin/connexion")
      enter_code(ROTP::TOTP.new(secret).now)
      expect(response).to redirect_to("/superadmin/connexion")
      expect(signed_in?).to be(false)
    end

    it "lets the password stand for five minutes, and not past a new password" do
      sign_in_password
      travel 6.minutes do
        enter_code(ROTP::TOTP.new(secret).now)
        expect(response).to redirect_to("/superadmin/connexion")
      end

      sign_in_password
      superadmin.update!(password: "another-password")
      enter_code(ROTP::TOTP.new(secret).now)
      expect(response).to redirect_to("/superadmin/connexion")
      expect(signed_in?).to be(false)
    end
  end

  it "the reset task turns the app off and ends the sessions" do
    enable_two_factor(superadmin)
    Rails.application.load_tasks unless Rake::Task.task_defined?("superadmin:reset_two_factor")

    ENV["EMAIL"] = superadmin.email
    expect { Rake::Task["superadmin:reset_two_factor"].execute }.to output(/turned off/).to_stdout
    expect(superadmin.reload.two_factor_enabled?).to be(false)
    expect(superadmin.token_version).to eq(1)
  ensure
    ENV.delete("EMAIL")
  end
end
