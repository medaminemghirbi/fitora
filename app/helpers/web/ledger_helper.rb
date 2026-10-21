module Web
  # The contracts and payments pages' small decisions, as their Angular
  # components make them.
  module LedgerHelper
    # ContractsComponent#filterChips: the search, the status, the payment
    # filter (always labelled "unpaid", as the component labels it), the plan.
    def contracts_chips(filters, plans)
      chips = []
      chips << { label: "« #{filters[:q]} »", clear: "q" } if filters[:q].present?
      status = Web::Admin::ContractsController::STATUSES.find { |value, *| value.present? && value == filters[:status].to_s }
      chips << { label: ngt(status[1]), clear: "status" } if status
      chips << { label: ngt("contracts.filter_unpaid"), clear: "payment" } if filters[:payment].present?
      plan = plans.find { |p| p[:id] == filters[:contract_type_id].to_s }
      chips << { label: plan[:name], clear: "contract_type_id" } if plan
      chips
    end

    # ContractsComponent#hasFilters: the status, the plan or the search —
    # not the payment filter (K-06).
    def contracts_filtered?(filters)
      filters[:status].present? || filters[:contract_type_id].present? || filters[:q].present?
    end

    # ContractsComponent#rowColor: what needs attention shows.
    def contract_row_color(contract)
      return "var(--color-info)" if contract[:paused]
      return "var(--color-danger)" if contract[:status] == "expired"
      return "var(--color-muted)" if contract[:status] == "cancelled"
      return "var(--color-info)" if contract[:payment_status] == "unpaid"

      "var(--color-success)"
    end

    # ContractsComponent#isQueuedRenewal: a renewal sold early that has not
    # started yet.
    def contract_queued_renewal?(contract)
      contract[:renewed_from_id].present? && contract[:starts_at].present? && contract[:starts_at] > Time.current
    end

    # What a contract was sold for, as a SellableItem key — nil when all-access.
    def contract_item_key(contract)
      return "pack:#{contract.dig(:pack, :id)}" if contract[:pack]
      return "activity:#{contract.dig(:activity, :id)}" if contract[:activity]

      nil
    end

    # AdminPaymentsComponent#filterChips: the search, the status, the method.
    def payments_chips(filters)
      chips = []
      chips << { label: "« #{filters[:q]} »", clear: "q" } if filters[:q].present?
      status = Web::Admin::PaymentsController::STATUSES.find { |value, *| value.present? && value == filters[:status].to_s }
      chips << { label: ngt(status[1]), clear: "status" } if status
      method = Web::Admin::PaymentsController::METHODS.find { |value, *| value == filters[:payment_method].to_s }
      chips << { label: ngt(method[1]), clear: "payment_method" } if method
      chips
    end

    # AdminPaymentsComponent#rowColor: collected, refunded, or cancelled.
    def payment_row_color(payment)
      return "var(--color-info)" if payment[:status] == "refunded"
      return "var(--color-muted)" if payment[:status] == "cancelled"

      "var(--color-success)"
    end
  end
end
