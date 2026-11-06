require "rails_helper"

RSpec.describe AuditLog do
  it "requires action, auditable_type, and auditable_id" do
    log = build(:audit_log, action: nil, auditable_type: nil, auditable_id: nil)

    expect(log).not_to be_valid
    expect(log.errors[:action]).to be_present
    expect(log.errors[:auditable_type]).to be_present
    expect(log.errors[:auditable_id]).to be_present
  end

  it "is valid without a user" do
    expect(build(:audit_log, user: nil)).to be_valid
  end

  describe "#auditable" do
    it "resolves the referenced record via auditable_type and auditable_id" do
      company = create(:company)
      log = create(:audit_log, company: company, auditable_type: "Company", auditable_id: company.id)

      expect(log.auditable).to eq(company)
    end

    it "returns nil when the referenced record no longer exists" do
      log = create(:audit_log)
      expect(log.auditable).to be_nil
    end
  end

  describe ".recent" do
    it "orders logs by created_at descending" do
      company = create(:company)
      older = create(:audit_log, company: company, created_at: 2.days.ago)
      newer = create(:audit_log, company: company, created_at: 1.hour.ago)

      expect(company.audit_logs.recent).to eq([ newer, older ])
    end
  end

  it "keeps an entry about something the product no longer has, pointing at nothing" do
    expect(described_class.new(auditable_type: "CashClosing", auditable_id: SecureRandom.uuid).auditable).to be_nil
  end
end
