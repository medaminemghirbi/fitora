require "rails_helper"

RSpec.describe "Api::V1::Superadmin::SubscriptionPricing", type: :request do
  let(:superadmin) { create(:user, :superadmin) }

  describe "GET /api/v1/superadmin/subscription_pricing" do
    it "returns both plans for the reference (TND) currency + the annual discount by default" do
      SubscriptionPrice.for("TND", plan: "starter").update!(monthly_cents: 19_000)

      get "/api/v1/superadmin/subscription_pricing", headers: auth_headers(superadmin)

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["currency"]).to eq("TND")
      expect(body["annual_discount_percent"]).to eq(10)
      expect(body["currencies"]).to include("TND", "EUR")

      starter = body["plans"].find { |p| p["plan"] == "starter" }
      expect(starter["monthly_cents"]).to eq(19_000)
      expect(starter["annual_cents"]).to eq((19_000 * 12 * 0.9).round)
      expect(body["plans"].map { |p| p["plan"] }).to eq(%w[starter pro])
    end

    it "counts the accounts on each plan, whatever they pay in, and the gyms in each currency" do
      create(:subscription, :pro, company: create(:company, currency: "TND"))
      create(:subscription, company: create(:company, currency: "EUR"))

      get "/api/v1/superadmin/subscription_pricing", headers: auth_headers(superadmin)

      body = response.parsed_body
      expect(body["plans"].to_h { |p| [ p["plan"], p["accounts_count"] ] }).to eq("starter" => 1, "pro" => 1)
      expect(body["conversions"].find { |c| c["currency"] == "EUR" }["companies_count"]).to eq(1)
    end

    it "shows another currency's prices converted, and every currency's with its rate" do
      SubscriptionPrice.for("TND", plan: "starter").update!(monthly_cents: 17_000)

      get "/api/v1/superadmin/subscription_pricing", params: { currency: "EUR" }, headers: auth_headers(superadmin)

      body = response.parsed_body
      expect(body.values_at("currency", "price_currency")).to eq(%w[EUR TND])
      # 170 DT ÷ 3.363395 = 50.54 €
      expect(body["plans"].find { |p| p["plan"] == "starter" }["monthly_cents"]).to eq(5_100)
      eur = body["conversions"].find { |c| c["currency"] == "EUR" }
      expect(eur["rate"]).to be_within(0.000001).of(1 / 3.363395)
      expect(eur["monthly_cents"]["starter"]).to eq(5_100)
      expect(SubscriptionPrice.where(currency: "EUR")).to be_none
    end

    it "is superadmin-only" do
      get "/api/v1/superadmin/subscription_pricing", headers: auth_headers(create(:user, :admin))
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "PATCH /api/v1/superadmin/subscription_pricing" do
    it "updates a currency's plans and the global annual discount" do
      patch "/api/v1/superadmin/subscription_pricing",
            params: { currency: "EUR", plans: { "starter" => 4500, "pro" => 9000 }, annual_discount_percent: 15 },
            headers: auth_headers(superadmin)

      expect(response).to have_http_status(:ok)
      expect(SubscriptionPrice.for("EUR", plan: "starter").monthly_cents).to eq(4500)
      expect(SubscriptionPrice.for("EUR", plan: "pro").monthly_cents).to eq(9000)
      expect(PlatformSetting.current.annual_discount_percent).to eq(15)

      starter = response.parsed_body["plans"].find { |p| p["plan"] == "starter" }
      expect(starter["annual_cents"]).to eq((4500 * 12 * 0.85).round)
    end

    it "makes the currency the prices are set in, and converts a plan the request leaves out" do
      SubscriptionPrice.for("TND", plan: "pro").update!(monthly_cents: 30_000)

      patch "/api/v1/superadmin/subscription_pricing", params: { currency: "EUR", plans: { "starter" => 4500 } }, headers: auth_headers(superadmin)

      expect(PlatformSetting.current.price_currency).to eq("EUR")
      # 300 DT ÷ 3.363395 = 89.20 €
      expect(SubscriptionPrice.for("EUR", plan: "pro").monthly_cents).to eq(8_900)
      # …and a Tunisian gym sees 4500 cents of euro in dinars: 45 € × 3.363395 = 151.35 DT
      expect(SubscriptionPrice.for("TND", plan: "starter").monthly_cents).to eq(15_100)
    end

    it "leaves a plan not mentioned in the request as it was" do
      SubscriptionPrice.for("TND", plan: "pro").update!(monthly_cents: 30_000)

      patch "/api/v1/superadmin/subscription_pricing", params: { currency: "TND", plans: { "starter" => 9000 } }, headers: auth_headers(superadmin)

      expect(SubscriptionPrice.for("TND", plan: "pro").monthly_cents).to eq(30_000)
    end

    it "ignores a plan Fitora does not sell" do
      patch "/api/v1/superadmin/subscription_pricing", params: { currency: "EUR", plans: { "premium" => 1 } }, headers: auth_headers(superadmin)

      expect(response).to have_http_status(:ok)
      expect(SubscriptionPrice.where(plan: "premium")).to be_none
    end

    it "rejects a negative price" do
      patch "/api/v1/superadmin/subscription_pricing", params: { currency: "EUR", plans: { "pro" => -1 } }, headers: auth_headers(superadmin)

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "rejects an out-of-range discount" do
      patch "/api/v1/superadmin/subscription_pricing",
            params: { annual_discount_percent: 250 }, headers: auth_headers(superadmin)

      expect(response).to have_http_status(:unprocessable_content)
    end
  end
end
