require "rails_helper"

RSpec.describe Payment, ".collect! under concurrency" do
  let(:company) { create(:company) }
  let(:client) { create(:client, company: company) }
  let(:contract) { create(:contract, client: client, contract_type: create(:contract_type, company: company), payment_status: :unpaid) }
  # Each thread loads its own copy of the contract, as two requests would.
  def settle
    Payment.collect!(client: client, company: company, created_by: company.admin,
                     payment_method: "cash", contract: Contract.find(contract.id))
    :paid
  rescue ApplicationRecord::Refused => e
    e.message
  end

  it "records a double click once" do
    results = 2.times.map do
      Thread.new { ActiveRecord::Base.connection_pool.with_connection { settle } }
    end.map(&:value)

    expect(results).to contain_exactly(:paid, "This is already paid.")
    expect(contract.payments.count).to eq(1)
  end

  it "will not settle another gym's contract for the same person" do
    other_gym = create(:company)
    client.join!(other_gym)

    expect {
      Payment.collect!(client: client, company: other_gym, created_by: other_gym.admin,
                       payment_method: "cash", contract: contract)
    }.to raise_error(ActiveRecord::RecordInvalid, /belongs to another gym/)
    expect(contract.reload).to be_unpaid
  end
end

RSpec.describe "POST /api/v1/payments across gyms", type: :request do
  it "cannot reach a contract another gym sold the same person" do
    gym_a = create(:company)
    gym_b = create(:company)
    member = create(:client, company: gym_a)
    member.join!(gym_b)
    contract = create(:contract, client: member, contract_type: create(:contract_type, company: gym_a), payment_status: :unpaid)

    post "/api/v1/payments", params: { client_id: member.id, contract_id: contract.id, payment_method: "cash" },
                             headers: auth_headers(gym_b.admin)

    expect(contract.reload).to be_unpaid
    expect(Payment.where(contract: contract)).to be_empty
  end
end
