module Payments
  # A salle's receipts, newest first: searched by member, filtered by status,
  # method and day, with the counts and the cash strip beside them. What
  # GET /api/v1/payments and the web UI's payments page list (moved unchanged
  # from Api::V1::PaymentsController).
  class ListQuery
    FILTERS = %i[q status payment_method date].freeze

    def initialize(company, params)
      @company = company
      params = params.slice(*FILTERS).permit(*FILTERS) if params.respond_to?(:permit)
      @params = params.to_h.with_indifferent_access.slice(*FILTERS)
    end

    attr_reader :params

    def scope
      scope = searched
      scope = scope.where(status: params[:status]) if params[:status].present?
      scope = scope.where(payment_method: params[:payment_method]) if params[:payment_method].present?
      scope = scope.where("created_at >= ?", Date.parse(params[:date]).beginning_of_day) if params[:date].present?
      scope.recent
    end

    # What the filter rail and the stats strip read, all on the searched set
    # so the numbers follow the search box and not the status picked.
    def counts
      searched.group(:status).count.merge("all" => searched.count)
    end

    def method_counts
      searched.group(:payment_method).count
    end

    # Reading what the gym has taken in is `revenue`: the caller asks it.
    def totals
      paid = searched.where(status: :paid)
      {
        collected_this_month: paid.where(paid_at: Time.current.beginning_of_month..).sum(:amount).to_f,
        collected_total: paid.sum(:amount).to_f,
        refunded_value: searched.where(status: :refunded).sum(:amount).to_f,
        cancelled_value: searched.where(status: :cancelled).sum(:amount).to_f,
        average_payment: paid.count.positive? ? (paid.sum(:amount).to_f / paid.count).round(2) : 0.0
      }
    end

    private

    attr_reader :company

    def searched
      @searched ||= begin
        scope = company.payments.includes(:client, :company, :created_by)
                       .preload(contract: :contract_type, booking: { session: :activity })
        if params[:q].blank?
          scope
        else
          t = "%#{params[:q].strip}%"
          scope.joins(:client).where("clients.first_name ILIKE :t OR clients.last_name ILIKE :t", t: t)
        end
      end
    end
  end
end
