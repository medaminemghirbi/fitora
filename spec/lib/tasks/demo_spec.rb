require "rails_helper"
require Rails.root.join("lib/tasks/demo/studio_lumen")
require Rails.root.join("lib/tasks/demo/abonnements")

# The demos are what a gym is shown before it buys: built here from the
# models as they are now, so a change that breaks them breaks the build
# rather than a sales meeting. Each builds inside the example's transaction
# and leaves nothing behind.
RSpec.describe "The demo gyms" do
  before do
    SubscriptionPrice::PLANS.each { |plan| SubscriptionPrice.base(plan) }
    load Rails.root.join("db/seeds/activity_templates.rb")
  end

  it "builds Studio Lumen — members, a schedule, the door's visits — and takes it back out" do
    logins = Demo::StudioLumen.build!
    company = Company.joins(:admin).find_by!(users: { email: Demo::StudioLumen::ADMIN_EMAIL })

    expect(logins.dig(:admin, :email)).to eq(Demo::StudioLumen::ADMIN_EMAIL)
    expect(company.memberships.count).to be >= 18
    expect(company.memberships.where(card_code: nil)).to be_empty
    expect(company.visits.count).to be_positive
    expect(company.visits.where(forced: true).count).to eq(1)
    expect(company.payments.where(payment_method: :card)).to exist
    expect(company.tax_id).to be_present

    Demo::StudioLumen.remove!
    expect(Company.where(id: company.id)).not_to exist
  end

  it "builds Salle Test Abonnements, one subscription in every state" do
    Demo::Abonnements.build!
    company = Company.joins(:admin).find_by!(users: { email: Demo::Abonnements::ADMIN_EMAIL })

    expect(company.contracts.map(&:state).uniq).to include("active", "expiring", "expired", "paused", "upcoming", "cancelled")

    Demo::Abonnements.remove!
    expect(Company.where(id: company.id)).not_to exist
  end
end
