require "rails_helper"

RSpec.describe "Api::V1::Subscription", type: :request do
  let(:admin) { create(:user, :admin) }
  let!(:company) { create(:company, admin: admin) }

  describe "GET /api/v1/subscription" do
    it "reports access as the boolean it is, with the invoices behind it" do
      create(:subscription, company: company)
      create(:invoice, :current, company: company, number: "FIT-2026-0001")

      get "/api/v1/subscription", headers: auth_headers(admin)

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["subscription"]["active"]).to be true
      expect(body["subscription"]["current_period_paid"]).to be true
      expect(body["invoices"].map { |i| i["number"] }).to eq([ "FIT-2026-0001" ])
    end

    it "says a gym on its free days is on trial, and how many are left" do
      create(:subscription, company: company)
      create(:invoice, :trial, company: company)

      get "/api/v1/subscription", headers: auth_headers(admin)

      body = response.parsed_body
      expect(body["subscription"]["trial"]).to be true
      expect(body["subscription"]["trial_days_left"]).to eq(Subscription::TRIAL_DAYS)
      expect(body["trial_days"]).to eq(Subscription::TRIAL_DAYS)
      expect(body["arrears_cents"]).to eq(0)
    end

    it "counts what is owed rather than taking it from a field" do
      create(:subscription, company: company)
      create(:invoice, company: company, period_start: Date.current - 60, period_end: Date.current.prev_month.end_of_month)

      get "/api/v1/subscription", headers: auth_headers(admin)

      expect(response.parsed_body["arrears_cents"]).to eq(company.monthly_subscription_cents)
    end

    # Fitora's own bank details are not something the app holds or hands out —
    # whatever the environment of a server set up before they were removed.
    it "sends no bank details" do
      ENV["FITORA_RIB"] = "TN59 1000 6035 0123 4567 8901"
      create(:subscription, company: company)

      get "/api/v1/subscription", headers: auth_headers(admin)

      expect(response.parsed_body).not_to have_key("payout")
      expect(response.body).not_to include("TN59")
    ensure
      ENV.delete("FITORA_RIB")
    end

    it "is closed to staff — it is the admin's business" do
      staff = create(:staff_member, company: company, role: :moderator).user
      create(:subscription, company: company)

      get "/api/v1/subscription", headers: auth_headers(staff)

      expect(response).to have_http_status(:forbidden)
    end

    it "no longer offers anything to ask for" do
      post "/api/v1/subscription/request_upgrade", headers: auth_headers(admin)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /api/v1/invoices" do
    it "returns the gym's own, newest first" do
      create(:subscription, company: company)
      create(:invoice, company: company, number: "FIT-2026-0001", period_start: Date.current - 60, period_end: Date.current - 31)
      create(:invoice, company: company, number: "FIT-2026-0002", period_start: Date.current - 30, period_end: Date.current)

      get "/api/v1/invoices", headers: auth_headers(admin)

      expect(response.parsed_body["invoices"].map { |i| i["number"] }).to eq([ "FIT-2026-0002", "FIT-2026-0001" ])
    end

    it "never returns another gym's" do
      create(:subscription, company: company)
      create(:invoice, company: create(:company))

      get "/api/v1/invoices", headers: auth_headers(admin)

      expect(response.parsed_body["invoices"]).to be_empty
    end

    it "404s on another gym's invoice rather than admitting it exists" do
      create(:subscription, company: company)
      theirs = create(:invoice, company: create(:company))

      get "/api/v1/invoices/#{theirs.id}", headers: auth_headers(admin)

      expect(response).to have_http_status(:not_found)
    end
  end
end
