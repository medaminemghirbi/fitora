module Contracts
  # A salle's contracts as the desk works from them: searched by member, plan
  # or reference, narrowed to one work list (status) and one formule, with
  # the counts and the money strip beside them. What GET /api/v1/contracts
  # and the web UI's subscriptions page list.
  class ListQuery
    FILTERS = %i[q status payment contract_type_id].freeze

    # The work lists, each one Contract scope (see Contract#state for the
    # same rules read off one term). `expiring` is "to renew now" — the name
    # the dashboard's link has always used.
    LISTS = {
      "active" => :running,
      "expiring" => :to_renew,
      "expired" => :lapsed,
      "unpaid" => :owing,
      "paused" => :paused_list,
      "upcoming" => :upcoming,
      "cancelled" => :cancelled
    }.freeze

    # revenue: whether the login may read what the subscriptions are worth.
    def initialize(company, params, revenue:)
      @company = company
      @revenue = revenue
      params = params.slice(*FILTERS).permit(*FILTERS) if params.respond_to?(:permit)
      @params = params.to_h.with_indifferent_access.slice(*FILTERS)
      # ?payment=unpaid is how the dashboard used to ask for what is owed.
      @params[:status] = "unpaid" if @params[:status].blank? && @params[:payment] == "unpaid"
      @params.delete(:status) unless LISTS.key?(@params[:status].to_s)
    end

    attr_reader :params

    # The list asked for, in the order its work is done: what runs out
    # first, what lapsed last, the oldest debt first.
    def scope
      contracts = searched
      contracts = list(contracts, params[:status]) if params[:status].present?
      contracts = contracts.owing if params[:payment] == "unpaid" && params[:status] != "unpaid"
      contracts = contracts.where(payment_status: :paid) if params[:payment] == "paid"
      contracts = contracts.where(contract_type_id: params[:contract_type_id]) if params[:contract_type_id].present?
      case params[:status]
      when "expiring" then contracts.reorder(:expires_at, :id)
      when "expired" then contracts.reorder(expires_at: :desc, id: :desc)
      when "unpaid", "upcoming" then contracts.reorder(:starts_at, :id)
      else contracts
      end
    end

    # How many each list holds. Everything here follows the search and the
    # formule but ignores the list already picked, so the numbers stay put
    # while the operator moves between them.
    def counts
      base = for_plan(searched).reorder(nil)
      LISTS.keys.index_with { |key| list(base, key).count }.merge("all" => base.count)
    end

    # The formule filter's numbers: what each holds for the current search.
    def plan_counts
      searched.reorder(nil).group(:contract_type_id).count
    end

    # What the running subscriptions were sold for — the frozen prices, never
    # today's catalogue — and what is still owed.
    #
    # The money figures are `revenue`, like the payments strip: whoever only
    # sells subscriptions still sees how many need renewing, which is work
    # to do, but not what they are worth.
    def totals
      base = for_plan(searched).reorder(nil)
      totals = { expiring_soon: base.to_renew.count }
      return totals unless revenue

      running = base.running
      value = running.sum(:final_price)
      count = running.count
      totals.merge(
        portfolio_value: value.to_f,
        average_basket: count.positive? ? (value.to_f / count).round(2) : 0.0,
        unpaid_value: base.owing.sum(:final_price).to_f
      )
    end

    private

    attr_reader :company, :revenue

    def list(scope, key)
      name = LISTS.fetch(key)
      return scope.where(status: :cancelled) if name == :cancelled
      # On hold — still `active`, so not a state of its own, but the one list
      # a studio checks to bring people back.
      return scope.active.where.not(paused_at: nil) if name == :paused_list

      scope.public_send(name)
    end

    def for_plan(scope)
      params[:contract_type_id].present? ? scope.where(contract_type_id: params[:contract_type_id]) : scope
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
               .where("clients.first_name ILIKE :t OR clients.last_name ILIKE :t " \
                      "OR (clients.first_name || ' ' || clients.last_name) ILIKE :t OR contract_types.name ILIKE :t " \
                      "OR contracts.invoice_ref ILIKE :t OR clients.phone ILIKE :t", t: t)
        end
      end
    end
  end
end
