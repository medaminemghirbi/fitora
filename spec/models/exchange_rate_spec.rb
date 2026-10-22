require "rails_helper"

RSpec.describe ExchangeRate do
  # ExchangeRate-API's answer: units per euro for every currency it knows.
  def answer(rates, result: "success")
    response = Net::HTTPOK.new("1.1", "200", "OK")
    allow(response).to receive(:body).and_return({ result: result, base_code: "EUR", rates: rates }.to_json)
    allow(Net::HTTP).to receive(:start).and_return(response)
  end

  let(:every_rate) { described_class::SNAPSHOT.transform_values { |rate| rate * 1.01 }.merge("EUR" => 1, "JPY" => 160.0) }

  describe ".convert" do
    it "rounds a price to whole units, a total to the cent, and leaves an amount in its own currency alone" do
      expect(described_class.convert(6_000, from: "EUR", to: "TND")).to eq(20_200)
      expect(described_class.convert(6_000, from: "EUR", to: "TND", round: :cents)).to eq(20_180)
      expect(described_class.convert(20_200, from: "TND", to: "TND")).to eq(20_200)
      expect(described_class.convert(nil, from: "EUR", to: "TND")).to be_nil
    end

    it "goes through the euro between two other currencies" do
      # 165 DT → € → DH: 165 ÷ 3.363395 × 10.988794 = 539.08 DH
      expect(described_class.convert(16_500, from: "TND", to: "MAD")).to eq(53_900)
    end
  end

  describe ".table" do
    it "is the stored rates, and the snapshot for any currency never fetched" do
      described_class.create!(currency: "TND", per_eur: 3.5, fetched_at: Time.current)

      expect(described_class.table).to include("TND" => 3.5, "MAD" => described_class::SNAPSHOT["MAD"])
      expect(described_class.table.keys).to match_array(CurrencyCatalog::CODES)
    end
  end

  describe ".refresh!" do
    it "stores every currency Fitora bills in, and only those" do
      answer(every_rate)
      freeze_time do
        described_class.refresh!

        expect(described_class.pluck(:currency)).to match_array(CurrencyCatalog::CODES)
        expect(described_class.find_by!(currency: "TND").per_eur.to_f).to eq(every_rate["TND"])
        expect(described_class.fetched_at).to eq(Time.current)
      end
    end

    it "replaces yesterday's rates" do
      described_class.create!(currency: "TND", per_eur: 3.1, fetched_at: 1.day.ago)
      answer(every_rate)

      described_class.refresh!

      expect(described_class.where(currency: "TND").count).to eq(1)
      expect(described_class.find_by!(currency: "TND").per_eur.to_f).to eq(every_rate["TND"])
    end

    it "stores nothing when a currency is missing or not a positive number" do
      answer(every_rate.except("TND"))
      expect { described_class.refresh! }.to raise_error(described_class::Unavailable)

      answer(every_rate.merge("MAD" => 0))
      expect { described_class.refresh! }.to raise_error(described_class::Unavailable)
      expect(described_class.count).to eq(0)
    end

    it "is unavailable when the source refuses, times out or answers garbage" do
      answer(every_rate, result: "error")
      expect { described_class.refresh! }.to raise_error(described_class::Unavailable, /"error"/)

      allow(Net::HTTP).to receive(:start).and_raise(Net::OpenTimeout)
      expect { described_class.refresh! }.to raise_error(described_class::Unavailable, /OpenTimeout/)

      response = Net::HTTPOK.new("1.1", "200", "OK")
      allow(response).to receive(:body).and_return("<html>")
      allow(Net::HTTP).to receive(:start).and_return(response)
      expect { described_class.refresh! }.to raise_error(described_class::Unavailable, /ParserError/)
    end
  end
end
