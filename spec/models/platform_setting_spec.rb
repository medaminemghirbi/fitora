require "rails_helper"

RSpec.describe PlatformSetting do
  it "keeps one row, created on first access" do
    expect { described_class.current }.to change(described_class, :count).by(1)
    expect { described_class.current }.not_to change(described_class, :count)
  end

  it "says whether the legal pages can name a publisher" do
    setting = described_class.current
    expect(setting).not_to be_identity_complete

    setting.update!(legal_name: " Fitora SARL ", tax_id: "1234567/A/M/000", email: "")
    expect(setting.reload.legal_name).to eq("Fitora SARL")
    expect(setting.email).to be_nil
    expect(setting).to be_identity_complete
  end

  it "refuses an address that is no address" do
    expect(described_class.current.update(email: "nope")).to be(false)
  end
end
