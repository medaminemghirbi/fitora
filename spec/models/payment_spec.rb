require "rails_helper"

RSpec.describe Payment do
  let(:company) { create(:company) }
  let(:client) { create(:client, company: company) }
  let(:booking) { create(:booking, client: client, session: create(:session, activity: create(:activity, company: company))) }

  it "accepts a card paid on the desk's terminal" do
    payment = build(:payment, client: client, company: company, booking: booking, payment_method: :card)
    expect(payment).to be_valid
  end

  it "rejects a method that is not one of the selectable ones" do
    payment = build(:payment, client: client, company: company, booking: booking, payment_method: :cheque)
    expect(payment).not_to be_valid
    expect(payment.errors[:payment_method]).to be_present
  end

  it "accepts the selectable methods" do
    Payment::SELECTABLE_METHODS.each do |method|
      payment = build(:payment, client: client, company: company, booking: booking, payment_method: method)
      expect(payment).to be_valid, "expected #{method} to be valid"
    end
  end

  it "keeps a payment's method when it is re-saved" do
    payment = create(:payment, client: client, company: company, booking: booking, payment_method: :card)

    payment.update!(notes: "reconciled")
    expect(payment.reload.payment_method).to eq("card")
  end
end
