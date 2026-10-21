module Contracts
  # A salle's contracts as the desk works from them: searched by member, plan
  # or reference, filtered by status, payment and plan, with the counts and
  # the portfolio strip beside them. What GET /api/v1/contracts and the web
  # UI's contracts page list (moved unchanged from Api::V1::ContractsController).
  class ListQuery
    FILTERS = %i[q status payment contract_type_id].freeze

    # revenue: whether the login may read what the portfolio is worth.
    def initialize(company, params, revenue:)
      @company = company
      @revenue = revenue
      params = params.slice(*FILTERS).permit(*FILTERS) if params.respond_to?(:permit)
      @params = params.to_h.with_indifferent_access.slice(*FILTERS)
    end

    attr_reader :params

    # status=expiring is not one of Contract's four states: it is "active,
    # and running out within the month", which is what the dashboard sends
    # people here to act on.
    def scope
      contracts = searched
      contracts = apply_status(contracts, params[:status]) if params[:status].present?
      contracts = apply_payment(contracts, params[:payment]) if params[:payment].present?
      contracts = contracts.where(contract_type_id: params[:contract_type_id]) if params[:contract_type_id].present?
      contracts
    end

    # What the filter rail and the stats strip read. Everything here follows
    # the search term but ignores the status/plan already picked, so the
    # numbers stay comparable while the operator clicks around.
    # The four contract states, plus the ones the filter rail offers that
    # are not states at all: everything, owed, running out, on hold.
    def counts
      searched.reorder(nil).group(:status).count
              .then { |by_status| Contract.statuses.keys.index_with { |status| by_status.fetch(status, 0) } }
              .merge(
                "all" => searched.count,
                "unpaid" => unpaid_scope(searched).count,
                "expiring" => expiring_scope(searched).count,
                "paused" => paused_scope(searched).count
              )
    end

    def plan_counts
      searched.reorder(nil).group(:contract_type_id).count
    end

    # The portfolio is what the ACTIVE contracts were sold for — the frozen
    # prices, never today's catalogue.
    #
    # The money figures are `revenue`, like the payments strip: whoever only
    # sells contracts still sees how many are about to expire, which is
    # work to do, but not what the portfolio is worth.
    def totals
      totals = { expiring_soon: expiring_scope(searched).count }
      return totals unless revenue

      active = searched.active
      value = active.sum(:final_price)
      count = active.count
      totals.merge(
        portfolio_value: value.to_f,
        average_basket: count.positive? ? (value.to_f / count).round(2) : 0.0,
        unpaid_value: unpaid_scope(searched).sum(:final_price).to_f
      )
    end

    private

    attr_reader :company, :revenue

    # The list's status filter, and its counts, both read each contract's
    # own state — the list holds no history (see #searched), so that is the
    # term in force or a renewal queued behind it.
    def apply_status(scope, status)
      return expiring_scope(scope) if status == "expiring"
      return paused_scope(scope) if status == "paused"

      scope.where(status: status)
    end

    # The "Non réglés" filter has to return exactly what its count promises,
    # so it goes through the same scope the count is built from.
    def apply_payment(scope, payment)
      return unpaid_scope(scope) if payment == "unpaid"

      scope.active.where(payment_status: payment)
    end

    # "Running out" means the gym's COVER runs out — a contract already
    # renewed is not work, even though the term in force still ends this
    # month.
    def expiring_scope(scope)
      scope.active.not_renewed.where(paused_at: nil, expires_at: Time.current..30.days.from_now)
    end

    # On hold (Contract#pause!) — still `active`, so not a state of its
    # own, but the one list a studio checks to bring people back.
    def paused_scope(scope)
      scope.active.where.not(paused_at: nil)
    end

    # Money owed — on the term in force or on a renewal queued behind it
    # (a renewal is sold unpaid).
    def unpaid_scope(scope)
      scope.active.unpaid
    end

    # The list is what the desk works from, so it leaves out history: a
    # term whose renewal has already started is behind the member, and
    # stays on their profile. What remains is the term in force and any
    # renewal queued behind it, each a row of its own with its own price
    # to collect.
    def searched
      @searched ||= begin
        scope = company.contracts.not_superseded.for_serializer.order(created_at: :desc)
        if params[:q].blank?
          scope
        else
          t = "%#{params[:q].strip}%"
          scope.joins(:client).joins(:contract_type)
               .where("clients.first_name ILIKE :t OR clients.last_name ILIKE :t OR contract_types.name ILIKE :t " \
                      "OR contracts.invoice_ref ILIKE :t", t: t)
        end
      end
    end
  end
end
