require "rails_helper"

# The account pages (module 1): forgotten and new password, a member's
# invitation, confirming the address.
# openapi: false — the contract is the API's (spec/rails_helper.rb).
RSpec.describe "Web account pages", type: :request, openapi: false do
  let(:company) { create(:company, setup_dismissed_at: Time.current) }
  let(:admin) { company.admin }

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

      expect(response.parsed_body).to eq("status" => "success", "continue_url" => "/sans-salle")
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
  end
end
