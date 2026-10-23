require "rails_helper"

RSpec.describe Invoice do
  describe ".next_number" do
    # Each call hands a number out; it is not a peek. Inside a transaction
    # that rolls back, the number goes back with it.
    it "starts a year at one and counts up" do
      travel_to(Date.new(2026, 3, 1)) do
        expect(described_class.next_number).to eq("FIT-2026-0001")
        expect(described_class.next_number).to eq("FIT-2026-0002")
      end
    end

    it "gives a number back when the invoice that took it rolls back" do
      travel_to(Date.new(2026, 3, 1)) do
        ActiveRecord::Base.transaction(requires_new: true) do
          described_class.next_number
          raise ActiveRecord::Rollback
        end

        expect(described_class.next_number).to eq("FIT-2026-0001")
      end
    end

    it "restarts the count in a new year" do
      create(:invoice, number: "FIT-2026-0042")

      travel_to(Date.new(2027, 1, 4)) do
        expect(described_class.next_number).to eq("FIT-2027-0001")
      end
    end

    it "never hands out the same number twice" do
      first = create(:invoice, number: described_class.next_number)

      expect { create(:invoice, number: first.number) }
        .to raise_error(ActiveRecord::RecordInvalid)
    end
  end

  it "refuses a period that runs backwards" do
    invoice = build(:invoice, period_start: Date.current, period_end: Date.current - 1)

    expect(invoice).not_to be_valid
    expect(invoice.errors[:period_end]).to be_present
  end

  it "knows which day it covers" do
    invoice = build(:invoice, period_start: Date.new(2026, 9, 1), period_end: Date.new(2026, 9, 30))

    expect(invoice).to be_covers(Date.new(2026, 9, 15))
    expect(invoice).not_to be_covers(Date.new(2026, 10, 1))
  end
  describe "its tax terms" do
    let(:setting) { PlatformSetting.current }

    it "splits a TTC price in dinars into HT, TVA and the timbre, to the millime" do
      invoice = create(:invoice, amount_cents: 16_500, currency: "TND")

      expect(invoice.totals.to_h).to eq(ht: 137_815, vat: 26_185, stamp: 1_000, ttc: 165_000, vat_percent: 19)
    end

    it "takes the rates in force when issued, and keeps them when they change" do
      setting.update!(vat_percent: 13, stamp_duty_millimes: 600)
      invoice = create(:invoice, amount_cents: 100_000, currency: "TND")
      setting.update!(vat_percent: 19, stamp_duty_millimes: 1_000)

      invoice.update!(paid_at: Time.current, notes: "Virement")
      # The template's own figures: 884,425 + 114,975 + 0,600 = 1 000,000 DT
      expect(invoice.reload.totals.to_h).to eq(ht: 884_425, vat: 114_975, stamp: 600, ttc: 1_000_000, vat_percent: 13)
    end

    it "takes today's rates again when a bill is issued again" do
      setting.update!(vat_percent: 13)
      invoice = create(:invoice, :due, amount_cents: 16_500, currency: "TND")
      setting.update!(vat_percent: 19)

      invoice.update!(issued_at: Time.current)
      expect(invoice.reload.vat_percent).to eq(19)
    end

    it "carries neither TVA nor timbre outside dinars, nor on a free trial" do
      euros = create(:invoice, amount_cents: 6_000, currency: "EUR")
      trial = create(:invoice, amount_cents: 0, currency: "TND", trial: true, plan: nil)

      expect(euros.totals.to_h).to eq(ht: 60_000, vat: 0, stamp: 0, ttc: 60_000, vat_percent: nil)
      expect(trial.totals.to_h).to eq(ht: 0, vat: 0, stamp: 0, ttc: 0, vat_percent: nil)
    end

    it "keeps who issued it once Fitora's identity is complete, and reads today's until then" do
      early = create(:invoice)
      setting.update!(legal_name: "Fitora SARL", tax_id: "1234567/A/M/000")
      issued = create(:invoice)
      setting.update!(legal_name: "Fitora SA")

      expect(issued.issuer_details).to include("legal_name" => "Fitora SARL", "tax_id" => "1234567/A/M/000")
      expect(early.reload.issuer_details).to include("legal_name" => "Fitora SA")
    end
  end
end
