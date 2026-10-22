require "rails_helper"

RSpec.describe SubscriptionPrice do
  describe ".for" do
    it "creates the reference (TND) Starter row at its default price" do
      row = described_class.for("TND", plan: "starter")
      expect(row.monthly_cents).to eq(described_class::DEFAULT_MONTHLY_CENTS["starter"])
    end

    it "prices Pro from its own default, above Starter's" do
      expect(described_class.for("TND", plan: "pro").monthly_cents).to eq(described_class::DEFAULT_MONTHLY_CENTS["pro"])
      expect(described_class::DEFAULT_MONTHLY_CENTS["pro"]).to be > described_class::DEFAULT_MONTHLY_CENTS["starter"]
    end

    it "converts the price into a gym's currency at the day's rate, rounded to whole units, and saves nothing" do
      PlatformSetting.current.update!(price_currency: "EUR")
      described_class.base("starter").update!(monthly_cents: 6_000)

      # 60 € × 3.363395 = 201.80 DT
      price = described_class.for("TND", plan: "starter")
      expect([ price.currency, price.monthly_cents ]).to eq([ "TND", 20_200 ])
      expect(price).to be_readonly
      expect(described_class.where(currency: "TND")).to be_none
    end

    it "converts at the stored rate once there is one" do
      PlatformSetting.current.update!(price_currency: "EUR")
      described_class.base("starter").update!(monthly_cents: 6_000)
      ExchangeRate.create!(currency: "TND", per_eur: 3.5, fetched_at: Time.current)

      expect(described_class.for("TND", plan: "starter").monthly_cents).to eq(21_000)
    end

    it "starts a new price currency's plans from their default, converted" do
      PlatformSetting.current.update!(price_currency: "EUR")

      # 165 DT ÷ 3.363395 = 49.06 €
      expect(described_class.base("starter").monthly_cents).to eq(4_900)
    end

    it "reads a blank or unknown currency as the price currency" do
      expect(described_class.for(nil, plan: "starter").currency).to eq("TND")
      expect(described_class.for("XXX", plan: "starter").currency).to eq("TND")
    end

    it "reads an unknown plan as Starter rather than raising" do
      expect(described_class.for("TND", plan: "enterprise").plan).to eq("starter")
    end

    it "keeps each plan of a currency priced independently" do
      described_class.for("TND", plan: "starter").update!(monthly_cents: 10_000)
      described_class.for("TND", plan: "pro").update!(monthly_cents: 20_000)

      expect(described_class.for("TND", plan: "starter").monthly_cents).to eq(10_000)
      expect(described_class.for("TND", plan: "pro").monthly_cents).to eq(20_000)
    end
  end

  describe "#annual_cents" do
    it "is twelve months less the platform's annual discount" do
      PlatformSetting.current.update!(annual_discount_percent: 10)
      price = described_class.for("TND", plan: "starter")
      price.update!(monthly_cents: 10_000)

      expect(price.annual_cents).to eq(108_000)
    end
  end

  it "validates the currency, the plan, and a non-negative price" do
    expect(described_class.new(currency: "XXX", plan: "starter", monthly_cents: 100)).to be_invalid
    expect(described_class.new(currency: "TND", plan: "premium", monthly_cents: 100)).to be_invalid
    expect(described_class.new(currency: "TND", plan: "starter", monthly_cents: -1)).to be_invalid
  end

  it "rejects a duplicate currency+plan pair" do
    create(:subscription_price, currency: "EUR", plan: "starter")
    duplicate = build(:subscription_price, currency: "EUR", plan: "starter")

    expect(duplicate).not_to be_valid
  end

  it "allows the same currency on the other plan" do
    create(:subscription_price, currency: "EUR", plan: "starter")
    other_plan = build(:subscription_price, currency: "EUR", plan: "pro")

    expect(other_plan).to be_valid
  end
end
