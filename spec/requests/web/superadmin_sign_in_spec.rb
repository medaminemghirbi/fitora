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

  it "keeps the console open for a working day, not a week" do
    web_sign_in(superadmin)
    travel(Web::Authentication::SUPERADMIN_LIFETIME - 1.minute) { expect(signed_in?).to be(true) }
    travel(Web::Authentication::SUPERADMIN_LIFETIME + 1.minute) { expect(signed_in?).to be(false) }
  end

  describe "without an app set up" do
    it "refuses the password with the way to set one up, and never offers to set one up itself" do
      sign_in_password
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(CGI.escapeHTML(Web::Translations.translate("superadmin.two_factor.not_set_up", locale: :fr)))

      get "/superadmin/connexion/code"
      expect(response).to redirect_to("/superadmin/connexion")
      enter_code("123456")
      expect(superadmin.reload.two_factor_enabled?).to be(false)
      expect(signed_in?).to be(false)
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

    # A code the app is not showing, whatever the time.
    def wrong_code
      ((ROTP::TOTP.new(secret).now.to_i + 1) % 1_000_000).to_s.rjust(6, "0")
    end

    it "counts the codes on the server: the cookie from before the first wrong one buys no more" do
      sign_in_password
      before_any_code = cookies["_fitora_session"]

      max = Web::Superadmin::SessionsController::MAX_TRIES
      answers = Array.new(max + 3) do
        cookies["_fitora_session"] = before_any_code
        enter_code(wrong_code)
        response.status
      end
      expect(answers.first(max - 1)).to all(eq(422))
      expect(answers.drop(max - 1)).to all(eq(302))

      cookies["_fitora_session"] = before_any_code
      enter_code(ROTP::TOTP.new(secret).now)
      expect(response).to redirect_to("/superadmin/connexion")
      expect(signed_in?).to be(false)
    end

    it "keeps the count through a new password step, and starts it again once the console opens" do
      max = Web::Superadmin::SessionsController::MAX_TRIES
      sign_in_password
      (max - 1).times { enter_code(wrong_code) }
      sign_in_password
      enter_code(wrong_code)
      expect(response).to redirect_to("/superadmin/connexion")

      Sidekiq.redis { |redis| redis.call("DEL", "superadmin_2fa_tries:#{superadmin.id}") } # the window, run out
      sign_in_password
      (max - 1).times { enter_code(wrong_code) }
      enter_code(ROTP::TOTP.new(secret).now)
      expect(signed_in?).to be(true)
      delete "/deconnexion"

      sign_in_password
      (max - 1).times { enter_code(wrong_code) }
      expect(response).to have_http_status(:unprocessable_content)
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

  describe "the setup task" do
    let(:secret) { TwoFactor.new_secret }

    def run_setup(input)
      allow(TwoFactor).to receive(:new_secret).and_return(secret)
      Rails.application.load_tasks unless Rake::Task.task_defined?("superadmin:setup_two_factor")
      ENV["EMAIL"] = superadmin.email
      $stdin = StringIO.new(input)
      Rake::Task["superadmin:setup_two_factor"].execute
    ensure
      $stdin = STDIN
      ENV.delete("EMAIL")
    end

    it "shows a QR code, and sets the app up with the code it makes" do
      expect { run_setup("000000\n#{ROTP::TOTP.new(secret).now}\n") }.to output(/That is not the app's code.*set up for ops@fitora.tn/m).to_stdout
      expect(superadmin.reload.two_factor_enabled?).to be(true)
      expect(superadmin.otp_secret_ciphertext).not_to include(secret)

      sign_in_password
      travel(TwoFactor::INTERVAL.seconds) { enter_code(ROTP::TOTP.new(secret).now) }
      expect(signed_in?).to be(true)
    end

    it "replaces a lost phone's app, and ends the sessions" do
      old = enable_two_factor(superadmin)
      expect { run_setup("#{ROTP::TOTP.new(secret).now}\n") }.to output(/set up/).to_stdout
      expect(superadmin.reload.token_version).to eq(1)

      sign_in_password
      travel(TwoFactor::INTERVAL.seconds) { enter_code(ROTP::TOTP.new(old).now) }
      expect(signed_in?).to be(false)
    end

    it "changes nothing until the app's code is given" do
      old = enable_two_factor(superadmin)
      expect { expect { run_setup("000000\n111111\n222222\n") }.to raise_error(SystemExit) }.to output.to_stdout.and output(/Nothing changed/).to_stderr
      expect { expect { run_setup("") }.to raise_error(SystemExit) }.to output.to_stdout.and output(/No code given/).to_stderr

      expect(superadmin.reload.token_version).to eq(0)
      sign_in_password
      enter_code(ROTP::TOTP.new(old).now)
      expect(signed_in?).to be(true)
    end

    it "goes by its old name too" do
      Rails.application.load_tasks unless Rake::Task.task_defined?("superadmin:reset_two_factor")
      expect(Rake::Task["superadmin:reset_two_factor"].prerequisites).to eq([ "setup_two_factor" ])
    end
  end
end
