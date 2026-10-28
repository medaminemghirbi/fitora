require "rails_helper"

RSpec.describe CashClosing do
  let(:company) { create(:company) }
  let(:desk) { create(:staff_member, company: company, role: :moderator).user }
  let(:other_desk) { company.admin }
  let(:client) { create(:client, company: company) }
  let(:plan) { create(:contract_type, company: company, price: 100) }

  def take(amount, by:, method: :cash, status: :paid, at: Time.current)
    contract = create(:contract, client: client, contract_type: plan)
    create(:payment, client: client, company: company, contract: contract, amount: amount, payment_method: method,
                     status: status, paid_at: at, created_by: by)
  end

  it "expects the cash this login took that day, and keeps the difference" do
    take(60, by: desk)
    take(40, by: desk, method: :card)
    take(25, by: other_desk)
    take(15, by: desk, status: :refunded)
    take(30, by: desk, at: 1.day.ago)

    closing = described_class.close!(company: company, user: desk, date: Date.current, counted: "55,5")
    expect([ closing.expected_cash, closing.counted_cash, closing.difference ]).to eq([ 60, 55.5, -4.5 ])
  end

  it "counts again in place, the same day" do
    take(60, by: desk)
    first = described_class.close!(company: company, user: desk, date: Date.current, counted: "50")
    again = described_class.close!(company: company, user: desk, date: Date.current, counted: "60", notes: "Recompté")

    expect(again).to eq(first)
    expect([ again.reload.difference, again.notes ]).to eq([ 0, "Recompté" ])
  end

  it "refuses an amount that is not one, and a day still to come" do
    expect { described_class.close!(company: company, user: desk, date: Date.current, counted: "abc") }
      .to raise_error(ApplicationRecord::Refused) { |e| expect(e.key).to eq("cash.errors.invalid_amount") }
    expect { described_class.close!(company: company, user: desk, date: Date.current, counted: "-5") }
      .to raise_error(ApplicationRecord::Refused)
    expect { described_class.close!(company: company, user: desk, date: Date.tomorrow, counted: "5") }
      .to raise_error(ApplicationRecord::Refused) { |e| expect(e.key).to eq("cash.errors.future_day") }
  end
end

RSpec.describe Payments::Till do
  let(:company) { create(:company) }
  let(:desk) { create(:staff_member, company: company, role: :moderator).user }
  let(:client) { create(:client, company: company) }
  let(:plan) { create(:contract_type, company: company) }

  def take(amount, method:, by: desk)
    contract = create(:contract, client: client, contract_type: plan)
    create(:payment, client: client, company: company, contract: contract, amount: amount, payment_method: method,
                     status: :paid, paid_at: Time.current, created_by: by)
  end

  it "sums the day by method — every method shown — and by login" do
    take(50, method: :cash)
    take(20, method: :card)
    take(10, method: :cash, by: company.admin)
    till = described_class.new(company, date: Date.current)

    expect(till.total).to eq(80)
    expect(till.by_method).to eq("cash" => 60, "card" => 20, "bank_transfer" => 0, "other" => 0)
    expect(till.by_staff.map { |row| [ row[:user], row[:count], row[:cash] ] })
      .to contain_exactly([ desk, 2, 50 ], [ company.admin, 1, 10 ])
  end

  it "narrows to one login's payments" do
    take(50, method: :cash)
    take(10, method: :cash, by: company.admin)

    expect(described_class.new(company, date: Date.current, user: desk).total).to eq(50)
  end
end
