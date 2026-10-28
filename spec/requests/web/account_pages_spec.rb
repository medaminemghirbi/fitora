require "rails_helper"

# The account pages (module 1): sign up, forgotten and new password, a
# member's invitation, confirming the address, the locked page.
# openapi: false — the contract is the API's (spec/rails_helper.rb).
RSpec.describe "Web account pages", type: :request, openapi: false do
  let(:company) { create(:company, setup_dismissed_at: Time.current) }
  let(:admin) { company.admin }

  describe "/inscription" do
    it "renders RegisterComponent's markup, and takes over the landing page's first name and e-mail" do
      get "/inscription", params: { first_name: "Sana", email: "sana@example.com" }
      expect(response.body).to include('<app-register _nghost-register="">', 'value="Sana"', 'value="sana@example.com"')
    end

    it "opens the account, signs in, and waits for the address" do
      expect do
        post "/inscription", params: { first_name: "Sana", last_name: "Ali", email: "sana@example.com", password: "password123", accept_terms: "1" }
      end.to change(User.admin, :count).by(1).and have_enqueued_mail(AccountMailer, :email_verification)

      expect(response).to redirect_to("/confirmation-email")
      follow_redirect!
      expect(response.body).to include("sana@example.com")
    end

    it "keeps the page's language for the account" do
      cookies[:fitora_locale] = "ar"
      post "/inscription", params: { first_name: "Sana", last_name: "Ali", email: "sana@example.com", password: "password123", accept_terms: "1" }
      expect(User.find_by!(email: "sana@example.com").locale).to eq("ar")
    end

    it "an address already taken: the API's message, as the Angular page shows it" do
      post "/inscription", params: { first_name: "A", last_name: "B", email: admin.email, password: "password123", accept_terms: "1" }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Email has already been taken")
    end

    it "the form's own checks: a malformed address says so; a short password does not" do
      post "/inscription", params: { first_name: "A", last_name: "B", email: "nope", password: "password123", accept_terms: "1" }
      expect(response.body).to include(%(data-check-error="reg-email"))

      post "/inscription", params: { first_name: "A", last_name: "B", email: "ok@example.com", password: "short", accept_terms: "1" }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).not_to include("data-check-error")
      expect(User.find_by(email: "ok@example.com")).to be_nil
    end
  end

  describe "/mot-de-passe-oublie" do
    it "mails a link to an account and says the same either way" do
      expect { post "/mot-de-passe-oublie", params: { email: admin.email } }.to have_enqueued_mail(AccountMailer, :password_reset)
      sent = response.body

      expect { post "/mot-de-passe-oublie", params: { email: "nobody@example.com" } }.not_to have_enqueued_mail
      expect(response.body).to include(Web::Translations.translate("auth.forgot_password_sent_title", locale: :fr))
      expect(response.body.gsub(/value="[^"]*"/, "")).to eq(sent.gsub(/value="[^"]*"/, ""))
    end

    it "an empty address: required" do
      post "/mot-de-passe-oublie", params: { email: "" }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(%(data-check-error="email"))
    end

    it "is one budget with the API's endpoint, and answers with the page when spent" do
      Rack::Attack.enabled = true
      store = Rack::Attack.cache.store
      Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
      5.times { post "/api/v1/password_resets", params: { email: "x@example.com" } }
      post "/mot-de-passe-oublie", params: { email: "x@example.com" }

      expect(response).to have_http_status(:too_many_requests)
      expect(response.body).to include("<app-forgot-password", Web::Translations.translate("auth.too_many_attempts", locale: :fr))
    ensure
      Rack::Attack.enabled = false
      Rack::Attack.cache.store = store
    end
  end

  describe "/auth/reset-password" do
    let(:token) { admin.generate_password_reset_token! }

    it "with no token: says the link is wrong before anything is typed" do
      get "/auth/reset-password"
      expect(response.body).to include(Web::Translations.translate("auth.reset_password_invalid_link", locale: :fr))
    end

    it "sets the new password, then says so and moves on to sign-in" do
      patch "/auth/reset-password", params: { token: token, password: "brand-new-pass", password_confirmation: "brand-new-pass" }

      expect(response.body).to include(Web::Translations.translate("auth.reset_password_done_title", locale: :fr), 'data-redirect-url-value="/connexion"')
      expect(admin.reload.authenticate("brand-new-pass")).to be_truthy
    end

    it "refuses two different passwords, and a spent link" do
      patch "/auth/reset-password", params: { token: token, password: "brand-new-pass", password_confirmation: "other-pass-1" }
      expect(response).to have_http_status(:unprocessable_content)

      patch "/auth/reset-password", params: { token: "spent", password: "brand-new-pass", password_confirmation: "brand-new-pass" }
      expect(response.body).to include(Web::Translations.translate("auth.reset_password_invalid_link", locale: :fr))
    end
  end

  describe "/auth/accept-invitation" do
    it "lets an invited member choose their password, with the invitation's words" do
      member = create(:client, company: company, email: "m@example.com")
      token = member.generate_invitation_token!
      get "/auth/accept-invitation", params: { token: token }
      expect(response.body).to include(Web::Translations.translate("auth.invitation_title", locale: :fr))

      patch "/auth/accept-invitation", params: { token: token, password: "member-pass-1", password_confirmation: "member-pass-1" }
      expect(member.reload.authenticate("member-pass-1")).to be_truthy
    end
  end

  describe "/verify-email" do
    let(:pending) { create(:user, :admin, :unverified) }

    it "arrives checking, without spending the token (a mail scanner runs no script)" do
      token = pending.generate_email_verification_token!
      get "/verify-email", params: { token: token }

      expect(response.body).to include(Web::Translations.translate("auth.verify_email_checking", locale: :fr))
      expect(pending.reload.email_verified?).to be(false)
    end

    it "the page's PATCH confirms, and says where to go" do
      token = pending.generate_email_verification_token!
      web_sign_in(pending)
      patch "/verify-email", params: { token: token }, as: :json

      expect(response.parsed_body).to eq("status" => "success", "continue_url" => "/admin/setup-company")
      expect(pending.reload.email_verified?).to be(true)
    end

    it "a stale link: an error — unless the address signed in here is confirmed already" do
      patch "/verify-email", params: { token: "stale" }, as: :json
      expect(response.parsed_body["status"]).to eq("error")

      web_sign_in(admin)
      patch "/verify-email", params: { token: "stale" }, as: :json
      expect(response.parsed_body["status"]).to eq("success")
    end
  end

  describe "/confirmation-email" do
    let(:pending) { create(:user, :admin, :unverified) }

    it "is the waiting screen of an admin not confirmed yet, and nobody else's" do
      get "/confirmation-email"
      expect(response).to redirect_to("/connexion")

      web_sign_in(admin)
      get "/confirmation-email"
      expect(response).to redirect_to("/admin/#{company.id}/dashboard")
    end

    it "offers the webmail of a known provider" do
      pending.update!(email: "someone@gmail.com")
      web_sign_in(pending)
      get "/confirmation-email"
      expect(response.body).to include("https://mail.google.com/", "someone@gmail.com")
    end

    it "answers the page's questions: clicked yet? send it again" do
      web_sign_in(pending)
      get "/confirmation-email/status"
      expect(response.parsed_body["email_verified"]).to be(false)

      post "/confirmation-email/resend"
      expect(response).to have_http_status(:no_content)
      post "/confirmation-email/resend"
      expect(response).to have_http_status(:too_many_requests)
      expect(response.parsed_body["retry_in"]).to be > 0

      pending.verify_email!
      get "/confirmation-email/status"
      expect(response.parsed_body).to include("email_verified" => true)
    end

    it "start over: signs out and goes to sign-up" do
      web_sign_in(pending)
      delete "/deconnexion", params: { to: "/inscription" }
      expect(response).to redirect_to("/inscription")
    end
  end

  describe "/account-locked" do
    it "tells a locked admin the trial is over and points at the plans" do
      admin.update!(created_at: 30.days.ago)
      Subscription.start_trial!(admin, currency: "TND") unless admin.subscription
      admin.subscription.invoices.update_all(period_start: 30.days.ago.to_date, period_end: 17.days.ago.to_date) # rubocop:disable Rails/SkipsModelValidations
      admin.subscription.update!(active: false)
      web_sign_in(admin)
      get "/account-locked"

      expect(response.body).to include("<app-account-locked", Web::Translations.translate("locked.title_trial_over", locale: :fr), 'href="/admin/subscription"')
    end

    it "tells staff to see their admin" do
      role = create(:role, company: company, permissions: %w[clients])
      web_sign_in(create(:staff_member, company: company, assigned_role: role).user)
      get "/account-locked"
      expect(response.body).to include(ERB::Util.html_escape(Web::Translations.translate("locked.staff_title", locale: :fr)))
    end

    it "the subscription page stays reachable from it while locked" do
      Subscription.start_trial!(admin, currency: "TND") unless admin.subscription
      admin.subscription.update!(active: false)
      web_sign_in(admin)
      get "/admin/#{company.id}/subscription"
      expect(response).to have_http_status(:ok)
    end
  end
end
