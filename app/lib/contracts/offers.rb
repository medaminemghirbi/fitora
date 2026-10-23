module Contracts
  # What the desk can sell, one line each: a formule on sale for one
  # activity or one pack, at the price the grid gives it — "Musculation ·
  # Mensuel — 60 DT". The sale, renewal and new-member dialogs pick one of
  # these, instead of a formule, then what it covers, then finding out
  # whether that pair has a price at all.
  module Offers
    Offer = Struct.new(:plan, :activity, :pack, :price, keyword_init: true) do
      # "<formule>|activity|<id>" or "<formule>|pack|<id>".
      def key
        "#{plan.id}|#{item_key}"
      end

      # What it covers, whatever the formule: "activity|<id>" or "pack|<id>".
      def item_key
        pack ? "pack|#{pack.id}" : "activity|#{activity.id}"
      end
    end

    # Formules on sale × active activities and packs they are priced for,
    # grouped by what they cover (activities by name, then packs by name),
    # shortest formule first within each.
    def self.for(company)
      plans = company.contract_types.active
                     .preload({ contract_type_activities: :activity }, { contract_type_packs: { pack: :activities } })
      offers = plans.flat_map do |plan|
        plan.contract_type_activities.select { |row| row.activity.active? }
            .map { |row| Offer.new(plan: plan, activity: row.activity, price: row.price) } +
          plan.contract_type_packs.select { |row| row.pack.active? }
              .map { |row| Offer.new(plan: plan, pack: row.pack, price: row.price) }
      end
      offers.sort_by do |offer|
        [ offer.pack ? 1 : 0, (offer.pack || offer.activity).name.downcase, offer.plan.duration_days, offer.plan.name.downcase ]
      end
    end

    # What a sold term covers, in the same terms: nil for an all-access one,
    # which no offer sells.
    def self.item_key(contract)
      return "pack|#{contract.pack_id}" if contract.pack_id
      return "activity|#{contract.activity_id}" if contract.activity_id

      nil
    end
  end
end
