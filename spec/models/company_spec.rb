require "rails_helper"

RSpec.describe Company do
  it "rejects a currency outside the catalogue" do
    company = build(:company, currency: "BTC")
    expect(company).not_to be_valid
    expect(company.errors[:currency]).to be_present
  end

  it "rejects an unsupported locale" do
    company = build(:company, locale: "de")
    expect(company).not_to be_valid
    expect(company.errors[:locale]).to be_present
  end

  it "defaults locale to fr" do
    expect(create(:company).locale).to eq("fr")
  end

  it "exposes the currency symbol" do
    expect(build(:company, currency: "EUR").currency_symbol).to eq("€")
    expect(build(:company, currency: "TND").currency_symbol).to eq("DT")
  end

  describe "logo validation" do
    let(:sample_path) { Rails.root.join("spec/fixtures/files/sample.png") }

    it "rejects a disallowed logo content type" do
      company = build(:company)
      company.logo.attach(
        io: File.open(sample_path), filename: "virus.exe", content_type: "application/x-msdownload", identify: false
      )

      expect(company).not_to be_valid
      expect(company.errors[:logo]).to be_present
    end

    it "rejects a logo over the size ceiling" do
      company = build(:company)
      company.logo.attach(io: File.open(sample_path), filename: "logo.png", content_type: "image/png")
      allow(company.logo.blob).to receive(:byte_size).and_return(Company::MAX_LOGO_SIZE + 1)

      expect(company).not_to be_valid
      expect(company.errors[:logo]).to be_present
    end

    it "accepts an allowed image logo" do
      company = build(:company)
      company.logo.attach(io: File.open(sample_path), filename: "logo.png", content_type: "image/png")

      expect(company).to be_valid
    end

    it "is valid with no logo attached" do
      expect(build(:company)).to be_valid
    end
  end

  # Prawn decodes a PNG whole to put it in a PDF, and a small file can declare
  # an enormous one (Receipts::PrintableImage).
  describe "PNG pixel ceiling, for the PDFs" do
    it "refuses a logo or a signature larger than the PDFs can draw" do
      company = build(:company)
      company.logo.attach(io: png_declaring(5000, 5000), filename: "logo.png", content_type: "image/png")
      company.signature.attach(io: png_declaring(5000, 5000), filename: "signature.png", content_type: "image/png")

      expect(company).not_to be_valid
      expect(company.errors[:logo]).to include(/megapixels/)
      expect(company.errors[:signature]).to include(/megapixels/)
    end

    it "accepts a wide signature within the ceiling" do
      company = build(:company)
      company.signature.attach(io: png_declaring(4000, 1000), filename: "signature.png", content_type: "image/png")

      expect(company).to be_valid
    end
  end
end
