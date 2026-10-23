require "rails_helper"

# A plan is either unlimited or counted. It used to be able to be both, which
# is how a plan named "24 Séances" came to sell as unlimited: the count named
# it and the flag decided what it did.
RSpec.describe ContractType, "unlimited or counted" do
  let(:company) { create(:company) }

  it "drops a session count when the plan is unlimited" do
    plan = create(:contract_type, company: company, unlimited_bookings: true, session_count: 24)

    expect(plan.session_count).to be_nil
  end

  it "drops a booking limit too" do
    plan = create(:contract_type, company: company, unlimited_bookings: true, booking_limit: 8)

    expect(plan.booking_limit).to be_nil
  end

  it "keeps the count on a counted plan" do
    plan = create(:contract_type, company: company, unlimited_bookings: false, session_count: 10)

    expect(plan.session_count).to eq(10)
  end

  it "cleans an existing contradictory row on its next save, rather than refusing it" do
    plan = create(:contract_type, company: company, unlimited_bookings: false, session_count: 24)
    plan.update_columns(unlimited_bookings: true)

    # The row is still valid — a validation here would strand it unsaveable.
    expect(plan.reload).to be_valid

    plan.save!
    expect(plan.reload.session_count).to be_nil
  end
end

# What the formule form asks for is "a number of sessions" (session_count);
# what a sale counts down is booking_limit. Apart, "Carte 10 séances" sold
# with no limit at all.
RSpec.describe ContractType, "counting what the gym typed" do
  let(:company) { create(:company) }
  let(:activity) { create(:activity, company: company) }

  it "limits bookings to the session count, so a sale counts down from it" do
    plan = create(:contract_type, company: company, unlimited_bookings: false, session_count: 10, booking_limit: nil)
    expect(plan.booking_limit).to eq(10)

    plan.contract_type_activities.find_or_create_by!(activity: activity) { |row| row.price = 80 }
    contract = Contract.sell!(client: create(:client, company: company), contract_type: plan, activity: activity, created_by: nil)
    expect(contract.remaining_bookings).to eq(10)
  end

  it "follows the count when it changes" do
    plan = create(:contract_type, company: company, unlimited_bookings: false, session_count: 10)
    plan.update!(session_count: 12)
    expect(plan.reload.booking_limit).to eq(12)
  end
end
