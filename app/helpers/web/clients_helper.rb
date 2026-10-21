module Web
  # ClientsListComponent's per-row and per-filter decisions, as it makes them.
  module ClientsHelper
    # What is true about this member's subscription, in one short phrase,
    # leading with whatever needs doing (ClientsListComponent#contractState).
    def clients_contract_state(client)
      contract = client[:current_contract]
      return "" unless contract
      return ngt("payments.status_unpaid") if contract[:payment_status] == "unpaid"
      return ngt("contract.status_expired") if contract[:status] == "expired"
      return ngt("clients.sessions_left", count: contract[:remaining_bookings]) unless contract[:remaining_bookings].nil?
      # new Date(expires_at).toLocaleDateString(undefined, { day: "numeric",
      # month: "short" }) — in the page's language here (B-03).
      return ngt("clients.until", date: ng_intl_date(contract[:expires_at], :day_month_short)) if contract[:expires_at]

      ngt("common.active")
    end

    # Which of those phrases is a problem (ClientsListComponent#contractTone).
    def clients_contract_tone(client)
      contract = client[:current_contract]
      return "neutral" unless contract
      return "danger" if contract[:payment_status] == "unpaid" || contract[:status] == "expired"
      return "warning" if !contract[:remaining_bookings].nil? && contract[:remaining_bookings] <= 1

      "neutral"
    end

    # A row's left strip (ClientsListComponent#rowColor).
    def clients_row_color(client)
      return "var(--color-muted)" unless client[:active]

      contract = client[:current_contract]
      return "var(--color-warning)" unless contract
      return "var(--color-danger)" if contract[:status] == "expired"
      return "var(--color-info)" if contract[:payment_status] == "unpaid"

      "var(--color-success)"
    end

    def clients_sort(filters)
      filters[:sort].presence_in(%w[name joined]) || "name"
    end

    def clients_direction(filters)
      filters[:direction] == "desc" ? "desc" : "asc"
    end

    def clients_aria_sort(filters, column)
      return "none" unless clients_sort(filters) == column

      clients_direction(filters) == "asc" ? "ascending" : "descending"
    end

    def clients_sort_icon(filters, column)
      return "bi-arrow-down-up" unless clients_sort(filters) == column

      clients_direction(filters) == "asc" ? "bi-arrow-up" : "bi-arrow-down"
    end

    # The words the page needs to redraw its chips and buttons the moment a
    # filter changes, before the list comes back — as the component's
    # computed signals do (clients_list_controller.js#renderFilters).
    def clients_filter_labels(catalogue)
      {
        statuses: {
          "active" => ngt("common.active"), "inactive" => ngt("common.inactive"),
          "contract_active" => ngt("clients.filter_contract_active"), "contract_expired" => ngt("clients.filter_contract_expired"),
          "no_contract" => ngt("clients.filter_no_contract")
        },
        genders: { "male" => ngt("clients.gender_male"), "female" => ngt("clients.gender_female") },
        plans: catalogue[:plans].to_h { |p| [ p[:id], p[:name] ] },
        activities: catalogue[:activities].to_h { |a| [ a[:id], a[:name] ] },
        member_since: ngt("clients.member_since"),
        reset: ngt("common.reset")
      }
    end

    # ClientsListComponent#filterChips: one chip per filter set, in its order,
    # each naming the filter its × clears.
    def clients_filter_chips(filters, catalogue)
      chips = []
      chips << { label: "« #{filters[:search]} »", clear: "search" } if filters[:search].present?

      if filters[:status].present?
        label = {
          "active" => "common.active", "inactive" => "common.inactive",
          "contract_active" => "clients.filter_contract_active", "contract_expired" => "clients.filter_contract_expired",
          "no_contract" => "clients.filter_no_contract"
        }[filters[:status]]
        chips << { label: ngt(label), clear: "status" } if label
      end

      plan = catalogue[:plans].find { |p| p[:id] == filters[:contract_type_id] }
      chips << { label: plan[:name], clear: "contract_type_id" } if plan

      activity = catalogue[:activities].find { |a| a[:id] == filters[:activity_id] }
      chips << { label: activity[:name], clear: "activity_id" } if activity

      if filters[:gender].present?
        key = { "male" => "clients.gender_male", "female" => "clients.gender_female" }[filters[:gender]]
        chips << { label: key ? ngt(key) : filters[:gender], clear: "gender" }
      end

      # One chip for the range, however many of its two ends are set.
      if filters[:joined_from].present? || filters[:joined_to].present?
        from = filters[:joined_from].presence || "…"
        to = filters[:joined_to].presence || "…"
        chips << { label: "#{ngt("clients.member_since")} #{from} → #{to}", clear: "joined" }
      end

      chips
    end

    # AdminBookingsComponent#filterChips: the search, the status, the day.
    def bookings_chips(filters)
      chips = []
      chips << { label: "« #{filters[:q]} »", clear: "q" } if filters[:q].present?
      status = Web::Admin::BookingsController::STATUSES.find { |value, _, _| value == filters[:status].to_s && value.present? }
      chips << { label: ngt(status[1]), clear: "status" } if status
      chips << { label: filters[:date], clear: "date" } if filters[:date].present?
      chips
    end

    def bookings_chip_count(filters) = bookings_chips(filters).size
  end
end
