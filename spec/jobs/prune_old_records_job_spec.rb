require "rails_helper"

RSpec.describe PruneOldRecordsJob do
  let(:company) { create(:company) }

  def notification(age, read:)
    create(:notification, company: company).tap do |n|
      n.update_columns(created_at: age.ago, read_at: (read ? age.ago : nil)) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  def audit_log(age)
    create(:audit_log, company: company).tap { |log| log.update_columns(created_at: age.ago) } # rubocop:disable Rails/SkipsModelValidations
  end

  it "deletes read notifications after 90 days, any after a year, audit logs after two years" do
    old_read = notification(100.days, read: true)
    old_unread = notification(100.days, read: false)
    recent_read = notification(10.days, read: true)
    ancient_unread = notification(400.days, read: false)
    old_log = audit_log(800.days)
    recent_log = audit_log(100.days)

    described_class.perform_now

    expect(Notification.where(id: [ old_read, old_unread, recent_read, ancient_unread ].map(&:id)).ids)
      .to contain_exactly(old_unread.id, recent_read.id)
    expect(AuditLog.where(id: [ old_log, recent_log ].map(&:id)).ids).to eq([ recent_log.id ])
  end

  it "runs every night" do
    schedule = YAML.safe_load_file(Rails.root.join("config/sidekiq_cron.yml"))
    expect(schedule.values.map { |entry| entry["class"] }).to include("PruneOldRecordsJob")
  end
end
