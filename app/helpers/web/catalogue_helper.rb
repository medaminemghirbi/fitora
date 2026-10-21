module Web
  # The catalogue's small decisions, as CatalogueComponent, its tabs and
  # shared/utils/client-list.ts make them.
  module CatalogueHelper
    # filterBySearch: case-insensitive, anywhere in any of the fields.
    def catalogue_filter(items, term, &fields)
      needle = term.to_s.strip.downcase
      return items if needle.empty?

      items.select { |item| fields.call(item).any? { |field| field.to_s.downcase.include?(needle) } }
    end

    # pageSlice + clientPageMeta.
    def catalogue_page(items, page, per_page = Web::Admin::CatalogueController::PER_PAGE)
      page = [ page, 1 ].max
      [ items.slice((page - 1) * per_page, per_page) || [], { page: page, per_page: per_page, total: items.size, total_pages: [ (items.size.to_f / per_page).ceil, 1 ].max } ]
    end

    def active_activities = catalogue[:activities].select { |a| a[:active] }
    def active_plans = catalogue[:plans].select { |p| p[:active] }
    def active_packs = catalogue[:packs].select { |p| p[:active] }

    # CatalogueStore#pricesForActivity / #pricesForPack: read off the formules.
    def catalogue_prices_for(kind, id)
      catalogue[:plans].filter_map do |plan|
        row = kind == :activity ? plan[:activity_prices].find { |r| r[:activity_id] == id } : Array(plan[:pack_prices]).find { |r| r[:pack_id] == id }
        row && { plan: plan, price: row[:price].to_f }
      end
    end

    def catalogue_packs_with(activity_id)
      catalogue[:packs].select { |p| p[:active] && p[:activity_ids].include?(activity_id) }
    end

    # PriceGridComponent#priceOf (null: not sold under that formule).
    def grid_price(plan, kind, id)
      row = kind == :activity ? plan[:activity_prices].find { |r| r[:activity_id] == id } : Array(plan[:pack_prices]).find { |r| r[:pack_id] == id }
      row && row[:price].to_f
    end

    # String(price): JavaScript's number-to-text (120, 12.5).
    def js_number(value)
      return "" if value.nil?

      value.to_f == value.to_f.truncate ? value.to_i.to_s : value.to_f.to_s
    end

    # The grid's currency: the first formule's, else the first activity's.
    def grid_currency
      active_plans.first&.dig(:currency) || active_activities.first&.dig(:currency) || ""
    end

    # What the catalogue controller says (toasts, dialog titles, the
    # confirmations and the form's checks).
    def catalogue_labels
      keys = %w[common.save common.saving common.deactivate common.confirm common.error_generic activities.new activities.edit
                activities.capacity_min activities.capacity_range contract_types.new common.edit contract_types.needs_validity
                contract_types.needs_session_count contract_types.needs_a_price packs.new packs.edit packs.needs_two
                packs.deactivate_body packs.separately activity_catalogue.none_selected activity_catalogue.n_selected
                activity_catalogue.add_n activity_catalogue.added activity_catalogue.no_match]
      formats = %w[individual small_group collective].to_h { |f| [ f, ngt("activities.format_#{f}_hint") ] }
      keys.to_h { |key| [ key, ngt(key) ] }.merge("format_hints" => formats, "currency_symbols" => currency_symbols)
    end

    def currency_symbols
      codes = (catalogue[:plans].map { |p| p[:currency] } + catalogue[:activities].map { |a| a[:currency] }).compact.uniq
      codes.to_h { |code| [ code, Web::Currency.symbol(code) ] }
    end

    # templateName(): the language's name, else the French one, else the key.
    def template_name(template)
      names = template[:names].to_h.stringify_keys
      names[I18n.locale.to_s].presence || names["fr"].presence || template[:key]
    end
  end
end
