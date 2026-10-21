module Bookings
  # A salle's bookings, newest first: searched by member or activity, by
  # status, on a day; a coach sees only their own sessions'. What
  # GET /api/v1/bookings and the web UI's bookings page list (moved unchanged
  # from Api::V1::BookingsController).
  class ListQuery
    FILTERS = %i[q status date].freeze

    def initialize(company, params, staff_member: nil)
      @company = company
      @staff_member = staff_member
      params = params.slice(*FILTERS).permit(*FILTERS) if params.respond_to?(:permit)
      @params = params.to_h.with_indifferent_access.slice(*FILTERS)
    end

    attr_reader :params

    def scope
      scope = searched
      scope = scope.where(status: params[:status]) if params[:status].present?
      scope = on_day(scope, params[:date]) if params[:date].present?
      scope
    end

    # Per status for the search and the day (the status itself aside), and "all".
    def counts
      counted = params[:date].present? ? on_day(searched, params[:date]) : searched
      counted.reorder(nil).group(:status).count.merge("all" => counted.reorder(nil).count)
    end

    def company_scope
      Booking.joins(:session).where(sessions: { company_id: company.id })
    end

    private

    attr_reader :company, :staff_member

    def searched
      @searched ||= begin
        scope = org_scope.preload(:client, session: [ :activity, :company, :coach ], contract: :contract_type)
                         .order(created_at: :desc)
        if params[:q].blank?
          scope
        else
          t = "%#{params[:q].strip}%"
          scope.joins(:client).joins(session: :activity)
               .where("clients.first_name ILIKE :t OR clients.last_name ILIKE :t OR activities.name ILIKE :t", t: t)
        end
      end
    end

    def on_day(scope, date)
      day = Date.parse(date)
      scope.joins(:session).where(sessions: { starts_at: day.all_day })
    rescue Date::Error
      scope
    end

    def org_scope
      staff_member&.coach? ? company_scope.where(sessions: { coach_id: staff_member.coach_id }) : company_scope
    end
  end
end
