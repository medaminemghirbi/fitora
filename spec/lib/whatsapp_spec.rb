require "rails_helper"

RSpec.describe Whatsapp do
  describe ".number" do
    it "reads a local number as the gym's country's" do
      expect(described_class.number("20 338 183", country: "TN")).to eq("21620338183")
      expect(described_class.number("06 12 34 56 78", country: "FR")).to eq("33612345678")
    end

    it "keeps a number written with its country code, however it is written" do
      expect(described_class.number("+216 20 338 183", country: "FR")).to eq("21620338183")
      expect(described_class.number("0033 6 12 34 56 78", country: "TN")).to eq("33612345678")
      expect(described_class.number("21620338183", country: "TN")).to eq("21620338183")
    end

    it "has nothing to call without a number" do
      expect(described_class.number(nil)).to be_nil
      expect(described_class.number("12")).to be_nil
    end
  end

  it "links to a chat with the message typed in" do
    expect(described_class.link("20 338 183", "Bonjour Salma, à bientôt !", country: "TN"))
      .to eq("https://wa.me/21620338183?text=Bonjour%20Salma%2C%20%C3%A0%20bient%C3%B4t%20%21")
  end
end
