require "rails_helper"

RSpec.describe RefreshExchangeRatesJob do
  it "refreshes the rates" do
    allow(ExchangeRate).to receive(:refresh!)

    described_class.perform_now

    expect(ExchangeRate).to have_received(:refresh!)
  end

  it "keeps the rates there were when the source fails, and reports it" do
    ExchangeRate.create!(currency: "TND", per_eur: 3.4, fetched_at: 1.day.ago)
    allow(ExchangeRate).to receive(:refresh!).and_raise(ExchangeRate::Unavailable, "down")
    allow(Rails.error).to receive(:report)

    expect { described_class.perform_now }.not_to raise_error

    expect(Rails.error).to have_received(:report).with(an_instance_of(ExchangeRate::Unavailable), hash_including(handled: true))
    expect(ExchangeRate.find_by!(currency: "TND").per_eur.to_f).to eq(3.4)
  end

  it "runs every night" do
    schedule = YAML.load_file(Rails.root.join("config/sidekiq_cron.yml"))
    expect(schedule.values.map { |job| job["class"] }).to include("RefreshExchangeRatesJob")
  end
end
