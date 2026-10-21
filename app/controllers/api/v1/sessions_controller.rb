module Api
  module V1
    class SessionsController < BaseController
      before_action :require_company!
      before_action :require_staff!, only: [ :index, :show, :schedule_pdf ]
      # The printable week is a Pro tool (paid Pro only, locked on the trial).
      before_action :require_pro!, only: [ :schedule_pdf ]
      before_action :require_session_management!, only: [ :create, :update, :cancel ]
      before_action :set_session, only: [ :show, :update, :cancel ]

      # GET /api/v1/sessions?activity_id=&coach_id=&date=&status=
      # GET /api/v1/sessions?from=&to=&... — range query, used by the calendar
      def index
        scope = base_scope
        scope = scope.where(activity_id: params[:activity_id]) if params[:activity_id].present?
        scope = scope.where(coach_id: params[:coach_id]) if params[:coach_id].present?
        scope = scope.where(status: params[:status]) if params[:status].present?
        scope = scope.for_date(Date.parse(params[:date])) if params[:date].present?
        scope = scope.includes(:activity, :company, :coach, :space).order(:starts_at)

        # The calendar asks for a bounded date range and needs every session
        # in it, not a paginated slice — pagination only applies to the
        # unbounded list view.
        if params[:from].present? && params[:to].present?
          scope = scope.where(starts_at: Date.parse(params[:from]).beginning_of_day..Date.parse(params[:to]).end_of_day)
          render json: { sessions: serialize_sessions(scope.to_a) }
        else
          render json: {
            sessions: serialize_sessions(paginate(scope).to_a),
            meta: pagination_meta(scope)
          }
        end
      end

      # GET /api/v1/sessions/:id
      def show
        render json: { session: SessionSerializer.new(@session).as_json }
      end

      # GET /api/v1/sessions/schedule_pdf?from=
      # Prints the week containing `from` (defaults to today), one page per
      # coach. `base_scope` already keeps a coach login to their own sessions.
      def schedule_pdf
        pdf, week_start = planner.weekly_pdf(params[:from])
        send_data pdf, filename: "planning-#{week_start.strftime('%Y-%m-%d')}.pdf", type: "application/pdf", disposition: "inline"
      end

      def create
        booking = params.require(:session).permit(:client_id, :drop_in, :trial)
        session = planner.create(session_params, client_id: booking[:client_id],
                                                 drop_in: ActiveModel::Type::Boolean.new.cast(booking[:drop_in]) || false,
                                                 trial: ActiveModel::Type::Boolean.new.cast(booking[:trial]) || false)
        render json: { session: SessionSerializer.new(session).as_json }, status: :created
      rescue Sessions::Planner::NotFound => e
        render json: { error: e.message }, status: :not_found
      end

      def update
        if @session.update(session_params)
          render json: { session: SessionSerializer.new(@session).as_json }
        else
          render_errors(@session)
        end
      end

      # POST /api/v1/sessions/:id/cancel
      def cancel
        cancelled = planner.cancel(@session, by: current_user)
        render json: { session: SessionSerializer.new(@session).as_json, bookings_cancelled: cancelled }
      end

      private

      def planner
        @planner ||= Sessions::Planner.new(company: current_company, staff_member: current_staff_member)
      end

      def serialize_sessions(sessions)
        Sessions::Planner.serialize(sessions)
      end

      # Coach-role staff only ever see/touch their own sessions; everyone
      # else with the `sessions` capability sees the whole company.
      def base_scope
        planner.scope
      end

      # Creating/editing/cancelling sessions is an operational (admin/superadmin/
      # manager) task — coaches can view their schedule but not restructure it.
      def require_session_management!
        return if current_user.admin?
        return if current_staff_member&.active? && current_staff_member.can?(:sessions) && !current_staff_member.coach?

        render_forbidden
      end

      def set_session
        @session = base_scope.find(params[:id])
      end

      def session_params
        params.require(:session).permit(:activity_id, :coach_id, :space_id, :starts_at, :ends_at, :capacity, :price, :status)
      end
    end
  end
end
