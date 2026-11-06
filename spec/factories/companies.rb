FactoryBot.define do
  factory :company do
    association :admin, factory: [ :user, :admin ]
    sequence(:name) { |n| "Studio #{n}" }
    timezone { "Africa/Tunis" }
    currency { "TND" }

    # Out of the directory. Set after create, not as an attribute: the column
    # defaults to now() and Rails omits an attribute whose value matches the
    # default it knows, so Postgres would fill it back in.
    trait :unlisted do
      after(:create) { |company| company.update!(listed_at: nil) }
    end

    # Packs are opt-in (CompanySettings FEATURES[:packs]).
    trait :with_packs do
      after(:create) { |company| company.update!(settings: { features: { packs: true } }) }
    end

    after(:create) do |company|
      Role.seed_defaults_for(company) if company.roles.empty?
      # An admin can run several companies now — current_company resolves
      # through active_company, not "the" company, so specs that just
      # `create(:company, admin: admin)` and expect current_company to be
      # it need this set, same as the real signup flow does.
      company.admin.update!(active_company: company) if company.admin.active_company_id.nil?
    end
  end
end
