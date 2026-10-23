require "rails_helper"

# One word for a term, read off its dates — nothing ever stores `expired`,
# so the stored status cannot be what the desk reads — and the work lists
# that select by the same rules (the subscriptions page, the dashboard).
RSpec.describe Contract, "#state and the work lists" do
  let(:plan) { create(:contract_type) }
  let(:company) { plan.company }

  def term(**attributes)
    create(:contract, contract_type: plan, **attributes)
  end

  it "reads each term the way its list selects it" do
    running = term(starts_at: 5.days.ago, expires_at: 25.days.from_now)
    to_renew = term(starts_at: 25.days.ago, expires_at: 5.days.from_now)
    lapsed = term(starts_at: 40.days.ago, expires_at: 10.days.ago)
    paused = term(starts_at: 5.days.ago, expires_at: 25.days.from_now, paused_at: 1.day.ago)
    queued = term(starts_at: 3.days.from_now, expires_at: 33.days.from_now)
    cancelled = term(status: :cancelled)

    expect([ running, to_renew, lapsed, paused, queued, cancelled ].map(&:state))
      .to eq(%w[active expiring expired paused upcoming cancelled])
    expect(company.contracts.running).to contain_exactly(running, to_renew)
    expect(company.contracts.to_renew).to contain_exactly(to_renew)
    expect(company.contracts.lapsed).to contain_exactly(lapsed)
    expect(company.contracts.upcoming).to contain_exactly(queued)
    expect(lapsed.status).to eq("active")
  end

  it "counts a carnet out of sessions as one to renew" do
    plan.update!(unlimited_bookings: false, session_count: 10)
    spent = term(starts_at: 5.days.ago, expires_at: 50.days.from_now, remaining_bookings: 0)

    expect(spent.state).to eq("expiring")
    expect(company.contracts.to_renew).to contain_exactly(spent)
  end

  it "says from when a term far from its end can be renewed" do
    far = term(starts_at: 1.day.ago, expires_at: 29.days.from_now)

    expect(far.renewable_on).to eq((far.expires_at - Contract::RENEWAL_WINDOW).to_date)
    expect(term(starts_at: 25.days.ago, expires_at: 5.days.from_now).renewable_on).to be_nil
  end

  it "forgives what a cancelled term owed" do
    owing = term(payment_status: :unpaid)
    term(payment_status: :unpaid, status: :cancelled)

    expect(company.contracts.owing).to contain_exactly(owing)
  end

  it "takes a discount agreed for the renewal, or carries the current one" do
    due = term(starts_at: 25.days.ago, expires_at: 5.days.from_now, discount: 10)

    expect(due.renew!.discount.to_f).to eq(10.0)
    second = term(starts_at: 25.days.ago, expires_at: 5.days.from_now, discount: 10)
    expect(second.renew!(discount: 0).discount.to_f).to eq(0.0)
  end
end
