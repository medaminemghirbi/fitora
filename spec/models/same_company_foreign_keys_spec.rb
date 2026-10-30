require "rails_helper"

# Past every model validation (update_columns writes straight to the
# table), the database itself keeps a gym's rows on its own records
# (AddSameCompanyForeignKeys).
RSpec.describe "Same-company foreign keys" do
  let(:company) { create(:company) }
  let!(:other) { create(:company) } # outside the savepoints, which roll back what they make

  # In a savepoint of its own: a refused write aborts the transaction it is in.
  def refused(&write)
    expect { ActiveRecord::Base.transaction(requires_new: true, &write) }
      .to raise_error(ActiveRecord::InvalidForeignKey, /_same_company/)
  end

  it "keeps a session on its own gym's activity, coach and room" do
    session = create(:session, company: company, activity: create(:activity, company: company))

    refused { session.update_columns(activity_id: create(:activity, company: other).id) }
    refused { session.update_columns(coach_id: create(:coach, company: other).id) }
    refused { session.update_columns(space_id: create(:space, company: other).id) }
  end

  it "keeps a contract on its own gym's plan and earlier contract, and a payment on its own gym's contract" do
    contract = create(:contract, contract_type: create(:contract_type, company: company))
    elsewhere = create(:contract, contract_type: create(:contract_type, company: other))

    refused { contract.update_columns(contract_type_id: elsewhere.contract_type_id) }
    refused { contract.update_columns(renewed_from_id: elsewhere.id) }
    refused { create(:payment, contract: contract).update_columns(contract_id: elsewhere.id) }
  end

  it "keeps a staff member on their own gym's role" do
    staff = create(:staff_member, company: company)
    Role.seed_defaults_for(other)

    refused { staff.update_columns(role_id: other.roles.first.id) }
  end

  it "takes the same writes within one gym, and the deletes that clear a link" do
    coach = create(:coach, company: company)
    session = create(:session, company: company, activity: create(:activity, company: company))

    session.update_columns(coach_id: coach.id)
    coach.destroy!
    expect(session.reload.coach_id).to be_nil
    expect { company.destroy! }.not_to raise_error
  end
end
