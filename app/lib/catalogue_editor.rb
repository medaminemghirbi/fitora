# Writing what a gym sells: a formule's prices, a pack and its activities —
# for /api/v1/contract_types, /api/v1/packs and the web UI's catalogue alike
# (moved unchanged from those API controllers).
module CatalogueEditor
  # The plan's pricing grid: one { activity_id, price } per activity this
  # plan is sold for. Activities not listed are dropped — the plan simply
  # isn't offered for them. Ids from another company are ignored, same guard
  # the old activity_ids sync used.
  #
  # Each list is optional: one that is absent (nil) is left alone, an empty
  # one clears the plan's rows, so a caller pricing one activity doesn't
  # have to restate every pack, and vice versa.
  def self.price_plan(plan, company, activity_prices: nil, pack_prices: nil)
    sync_activity_prices(plan, company, activity_prices) unless activity_prices.nil?
    sync_pack_prices(plan, company, pack_prices) unless pack_prices.nil?
  end

  # On a saved pack, assigning `activities` writes the join rows at once,
  # before the validation that needs two of them has run — hence the
  # transaction, which a refused save rolls back. activity_ids nil leaves
  # the pack's activities as they are.
  def self.save_pack(pack, company, attributes, activity_ids: nil)
    Pack.transaction do
      pack.assign_attributes(attributes)
      pack.activities = company.activities.where(id: Array(activity_ids)) unless activity_ids.nil?
      pack.save!
    end
    pack.reload
  end

  def self.sync_activity_prices(plan, company, rows)
    own_activity_ids = company.activities.ids
    rows = Array(rows).filter_map do |row|
      activity_id = row[:activity_id].presence
      next unless own_activity_ids.include?(activity_id)

      { activity_id: activity_id, price: row[:price].to_f }
    end

    plan.contract_type_activities.where.not(activity_id: rows.map { |r| r[:activity_id] }).destroy_all
    rows.each do |row|
      plan.contract_type_activities.find_or_initialize_by(activity_id: row[:activity_id]).update!(price: row[:price])
    end
  end
  private_class_method :sync_activity_prices

  def self.sync_pack_prices(plan, company, rows)
    own_pack_ids = company.packs.ids
    rows = Array(rows).filter_map do |row|
      pack_id = row[:pack_id].presence
      next unless own_pack_ids.include?(pack_id)

      { pack_id: pack_id, price: row[:price].to_f }
    end

    plan.contract_type_packs.where.not(pack_id: rows.map { |r| r[:pack_id] }).destroy_all
    rows.each do |row|
      plan.contract_type_packs.find_or_initialize_by(pack_id: row[:pack_id]).update!(price: row[:price])
    end
  end
  private_class_method :sync_pack_prices
end
