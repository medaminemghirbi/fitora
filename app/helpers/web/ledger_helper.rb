module Web
  # The payments page's small decisions, as its Angular component makes
  # them (the subscriptions page's are Web::SubscriptionsHelper's).
  module LedgerHelper
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
