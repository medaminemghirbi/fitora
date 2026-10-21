# What a gym sells, in the order its lists show it: shared by
# GET /api/v1/contract_types, GET /api/v1/activities, GET /api/v1/packs and the web UI (the
# new-member wizard and the members page's filters read the same rows).
module CatalogueListing
  # Was ordered by the flat price, which no longer exists — a plan now has
  # one price per activity. Shortest commitment first, then name.
  def self.plans(company)
    company.contract_types
           .preload({ contract_type_activities: :activity }, { contract_type_packs: { pack: :activities } })
           .order(:billing_period, :name)
  end

  def self.activities(company)
    company.activities.order(:name)
  end

  # Every pack, active or not, by name (GET /api/v1/packs).
  def self.packs(company)
    company.packs.preload(:company, :activities, contract_type_packs: :contract_type).order(:name)
  end
end
