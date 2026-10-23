module Web
  # The subscriptions page's and dialogs' small decisions — what a term's
  # state says, what is left of it, what the desk may do to it — and what
  # the dialogs read: the offers on sale, a member and what they hold, one
  # term. Shared by the subscriptions page, the member's file and the
  # new-member wizard. `m` is a term as ContractSerializer writes it (or
  # that, round-tripped through JSON, on the member's file).
  module SubscriptionsHelper
    # The tabs that show: each list the controller names, unless it is one
    # of the usually-empty ones, empty, and not the one open.
    def subscription_lists(counts, filters)
      Web::Admin::ContractsController::LISTS.filter_map do |value, label, tone, always|
        count = counts[value.presence || "all"] || 0
        next unless always || count.positive? || filters[:status].to_s == value

        { value: value, label: ngt(label), tone: tone, count: count, active: filters[:status].to_s == value }
      end
    end

    # The badge: its words, and the status whose colour it takes.
    def subscription_state_label(m)
      # A carnet spent before its date is to renew for that, not for the date.
      return ngt("contracts.state_sessions_used") if m[:state] == "expiring" && m[:remaining_bookings]&.zero?

      case m[:state]
      when "expiring" then m[:days_left] ? ngt("contracts.state_expiring_in", count: m[:days_left]) : ngt("contracts.state_expiring")
      when "upcoming" then ngt("contracts.state_upcoming")
      else ngt("contracts.state_#{m[:state]}")
      end
    end

    # Under the dates: how long is left, since when it is over, when it
    # begins.
    def subscription_period_note(m)
      return nil if m[:state] == "cancelled"

      expires = subscription_time(m[:expires_at])
      starts = subscription_time(m[:starts_at])
      if m[:state] == "upcoming" && starts
        ngt("contracts.starts_in", count: [ (starts.to_date - Date.current).to_i, 1 ].max)
      elsif m[:state] == "expired" && expires
        days = (Date.current - expires.to_date).to_i
        days.zero? ? ngt("contracts.ended_today") : ngt("contracts.ended_ago", count: days)
      elsif m[:state] == "paused"
        ngt("contracts.paused_since", date: ng_date(m[:paused_at], "d MMM"))
      elsif m[:days_left]
        ngt("contracts.days_left", count: m[:days_left])
      end
    end

    # Sessions left, for a counted formule; nil for an unlimited one.
    def subscription_sessions_note(m)
      return nil if m[:remaining_bookings].nil? || m[:state] == "cancelled"

      ngt("contracts.sessions_left", count: m[:remaining_bookings])
    end

    # What it covers, in a word: the activity, or the pack by its name.
    def subscription_covers(m)
      m.dig(:pack, :name).presence || m[:activity_label].presence
    end

    # "Musculation · Mensuel": what it covers, then the formule.
    def subscription_label(m)
      [ subscription_covers(m), m.dig(:plan, :name) ].compact.join(" · ")
    end

    # Whether "Modifier" applies (Contract#update_term!).
    def subscription_editable?(m)
      %w[active pending].include?(m[:status])
    end

    # Whether "Mettre en pause" applies (Contract#pause!).
    def subscription_pausable?(m)
      m[:status] == "active" && !m[:paused] && %w[active expiring].include?(m[:state])
    end

    # What the dialogs need to act on this term (subscriptions controller).
    def subscription_payload(m)
      plan = m[:plan] || {}
      {
        id: m[:id], ref: m[:invoice_ref],
        client: { id: m.dig(:client, :id), name: m.dig(:client, :full_name) },
        label: subscription_label(m), plan_id: plan[:id], item: subscription_item_key(m),
        duration_days: plan[:duration_days], currency: plan[:currency],
        price: m[:base_price].to_f, discount: m[:discount].to_f, total: m[:final_price].to_f, amount_due: m[:amount_due].to_f,
        paid: m[:payment_status] == "paid", paused: m[:paused], state: m[:state],
        starts_on: subscription_date(m[:starts_at]), expires_on: subscription_date(m[:expires_at]),
        next_starts_on: subscription_date(m[:next_term_starts_at])
      }
    end

    # What a term covers, as the offers name it ("activity|<id>",
    # "pack|<id>"), nil for an all-access one (Contracts::Offers.item_key).
    def subscription_item_key(m)
      return "pack|#{m.dig(:pack, :id)}" if m[:pack]
      return "activity|#{m.dig(:activity, :id)}" if m[:activity]

      nil
    end

    # The member as the sale dialog reads them, with what they already hold
    # (running or queued), to warn before a sale overlaps it.
    def subscription_member(client, contracts)
      {
        id: client.id, name: client.full_name, phone: client.phone,
        holds: contracts.filter_map do |contract|
          item = Contracts::Offers.item_key(contract)
          next if item.nil?

          { item: item, label: [ contract.activity_label, contract.contract_type.name ].join(" · "),
            until: ng_date(contract.expires_at, "d MMM y") }
        end
      }
    end

    # The member's file: what is current — running, paused or queued — and,
    # when nothing is, the last term that ended, to renew it from there.
    def subscription_current(contracts)
      live = contracts.reject { |m| m[:state] == "cancelled" || subscription_superseded?(m) }
      current = live.reject { |m| m[:state] == "expired" }
      return current.sort_by { |m| subscription_time(m[:starts_at]) || Time.current } if current.any?

      [ live.select { |m| m[:state] == "expired" }.max_by { |m| subscription_time(m[:expires_at]) || Time.at(0) } ].compact
    end

    # The offers on sale, as the dialogs list them (Contracts::Offers).
    def subscription_offers(company)
      Contracts::Offers.for(company).map do |offer|
        plan = offer.plan
        {
          key: offer.key, item: offer.item_key,
          contract_type_id: plan.id, activity_id: offer.activity&.id, pack_id: offer.pack&.id,
          group_label: offer.pack ? offer.pack.name : [ offer.activity.emoji.presence, offer.activity.name ].compact.join(" "),
          group_sub: offer.pack&.activity_names&.join(" + "),
          name: plan.name, meta: subscription_plan_meta(plan), color: plan.color,
          price: offer.price.to_f, currency: plan.currency, duration_days: plan.duration_days
        }
      end
    end

    # This salle's, once a request.
    def subscription_sale_offers
      @subscription_sale_offers ||= subscription_offers(salle)
    end

    # "1 mois · illimité", "56 jours · 10 séances".
    def subscription_plan_meta(plan)
      length = ngt("catalogue.length_#{plan.billing_period}", days: plan.validity_days)
      sessions = plan.booking_limit || plan.session_count
      count = plan.unlimited_bookings? || sessions.blank? ? ngt("catalogue.unlimited_short") : "#{sessions} #{ngt("contract_types.sessions")}"
      "#{length} · #{count}"
    end

    # The subscriptions controller's values, as attributes for the element
    # it sits on: where to send, what is on sale, the member when the page
    # is one member's (nil to pick one), today, the currencies' symbols.
    def subscription_controller_attributes(member:)
      offers = subscription_sale_offers
      codes = ([ salle.currency ] + offers.map { |o| o[:currency] }).compact.uniq
      tag.attributes(data: {
        subscriptions_url_value: admin_page_path("contracts"),
        subscriptions_offers_value: offers.to_json,
        subscriptions_member_value: (member || {}).to_json,
        subscriptions_today_value: Date.current.iso8601,
        subscriptions_locale_value: I18n.locale.to_s,
        subscriptions_symbols_value: codes.to_h { |code| [ code, Web::Currency.symbol(code) ] }.to_json,
        subscriptions_labels_value: subscription_labels.to_json
      })
    end

    # The labels the subscriptions controller writes into its dialogs.
    def subscription_labels
      keys = %w[
        contracts.sell_title contracts.renew_title contracts.current contracts.sell_submit contracts.renew_submit contracts.collect_submit
        contracts.ends_on contracts.starts_on_renewal contracts.overlap contracts.sold contracts.renewed
        contracts.collected contracts.updated contracts.cancelled_done contracts.paused_done contracts.resumed_done
        contracts.cancel_confirm_title contracts.cancel_confirm_body contracts.cancel_confirm_ok
        contracts.pause_confirm_title contracts.pause_confirm_body contracts.no_member_found
        contracts.searching common.error_generic
      ]
      keys.to_h { |key| [ key.split(".").last, ngt(key) ] }
    end

    private

    def subscription_superseded?(m)
      renewal = m[:renewal]
      return false unless renewal

      starts = subscription_time(renewal[:starts_at])
      starts.nil? || starts <= Time.current
    end

    def subscription_time(value)
      value.presence&.in_time_zone
    end

    def subscription_date(value)
      subscription_time(value)&.to_date&.iso8601
    end
  end
end
