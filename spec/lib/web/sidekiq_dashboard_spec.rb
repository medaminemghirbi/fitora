require "rails_helper"

RSpec.describe Web::SidekiqDashboard do
  let(:long) { "x" * described_class::MIN_PASSWORD_LENGTH }

  it "is mounted outside development only behind a long enough password, and says why when it is not" do
    expect(described_class.mount?({ "SIDEKIQ_WEB_PASSWORD" => long })).to be(true)
    expect(described_class.mount?({})).to be(false)

    allow(Rails.logger).to receive(:warn)
    expect(described_class.mount?({ "SIDEKIQ_WEB_PASSWORD" => "short" })).to be(false)
    expect(Rails.logger).to have_received(:warn).with(/shorter than 24 characters/)
  end

  it "takes no password at all while the one set is too short" do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("SIDEKIQ_WEB_PASSWORD").and_return("short")
    expect(described_class.valid_credentials?("fitora", "short")).to be(false)

    allow(ENV).to receive(:[]).with("SIDEKIQ_WEB_PASSWORD").and_return(long)
    expect(described_class.valid_credentials?("fitora", long)).to be(true)
    expect(described_class.valid_credentials?("fitora", "#{long}!")).to be(false)
  end
end
