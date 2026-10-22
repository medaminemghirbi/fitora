module Web
  module Admin
    # The planning (CalendarComponent): the page around FullCalendar, which
    # reads its sessions from #events, and the calendar's writes — a new
    # session or weekly class, a move, a cancellation, stopping a series, a
    # member added — each through the rule /api/v1/sessions,
    # /api/v1/recurring_schedules or /api/v1/bookings applies (Sessions::Planner),
    # behind the same checks, answered with the API's message (K-04). Any
    # staff login may open it; only one that manages sessions changes it.
    class CalendarController < BaseController
      # The widest view, a month, asks for six weeks. A longer range never
      # comes from the page, and would load every session the salle has had.
      MAX_RANGE_DAYS = 62

      before_action :refuse_unless_managing, only: %i[create move cancel stop_series book]
      before_action -> { refuse unless current_user.admin? || current_user.staff? }, only: %i[events schedule_pdf]
      before_action -> { refuse unless pro_access? }, only: :schedule_pdf
      before_action -> { refuse unless capability?(:clients) }, only: :clients
      before_action :set_session, only: %i[move cancel book]

      rescue_from ActiveRecord::RecordInvalid, with: ->(invalid) { render_messages(I18n.with_locale(:en) { invalid.record.errors.full_messages }) }
      rescue_from ApplicationRecord::Refused, with: ->(refusal) { render_messages([ refusal.message ]) }
      rescue_from Date::Error, with: -> { render json: { error: "invalid date" }, status: :bad_request }

      # The page, and what its filters and "new session" dialog list — each
      # best-effort as the component's own requests are: a login that may
      # not read a list gets an empty one.
      def show
        @coaches = schedule_reference_access?(:coaches) ? current_company.coaches.includes(staff_member: :user).order(:first_name).map { |c| CoachSerializer.new(c).as_json } : []
        @activities = schedule_reference_access?(:activities) ? CatalogueListing.activities(current_company).map { |a| ActivitySerializer.new(a).as_json } : []
        manage = @manage = capability?(:sessions)
        @clients = manage && capability?(:clients) ? client_rows(Clients::ListQuery.new(current_company, {}).scope.limit(100)) : []
        @spaces = manage && current_company.feature?(:spaces) ? current_company.spaces.ordered.select(&:active).map { |s| { id: s.id, name: s.name } } : []
      end

      # GET …/calendar/events?from=&to=&coach_id=&activity_id= — the range
      # FullCalendar shows, as GET /api/v1/sessions?from&to answers it.
      # Each session also carries the words the hover card and the detail
      # print (DatePipe's "HH:mm", "EEEE d MMM" and "medium"), formatted here
      # as everywhere else on the server (Web::DateFormat).
      def events
        # A missing date is a Date::Error too (Date.parse("")), answered 400.
        days = (Date.parse(params[:to].to_s) - Date.parse(params[:from].to_s)).to_i
        return render(json: { error: "invalid range" }, status: :bad_request) unless (0..MAX_RANGE_DAYS).cover?(days)

        sessions = planner.range(from: params[:from], to: params[:to], coach_id: params[:coach_id], activity_id: params[:activity_id])
        render json: { sessions: sessions.map { |s| s.merge(labels: date_labels(s)) } }
      end

      # POST …/calendar/sessions — one session (POST /api/v1/sessions), or,
      # with `weekly`, a weekly class (POST /api/v1/recurring_schedules).
      def create
        return create_weekly if params[:weekly].present?

        attributes = params.require(:session).permit(:activity_id, :coach_id, :space_id, :starts_at, :ends_at, :capacity, :price, :status)
        booking = params.require(:session).permit(:client_id, :drop_in, :trial)
        truthy = ->(v) { ActiveModel::Type::Boolean.new.cast(v) || false }
        session = planner.create(attributes, client_id: booking[:client_id], drop_in: truthy.call(booking[:drop_in]), trial: truthy.call(booking[:trial]))
        render json: { session: SessionSerializer.new(session).as_json }, status: :created
      rescue Sessions::Planner::NotFound => e
        render json: { error: e.message }, status: :not_found
      end

      # PATCH …/calendar/sessions/:id — moved by drag and drop.
      def move
        return render_messages(I18n.with_locale(:en) { @session.errors.full_messages }) unless @session.update(params.require(:session).permit(:starts_at, :ends_at))

        render json: { session: SessionSerializer.new(@session).as_json }
      end

      def cancel
        cancelled = planner.cancel(@session, by: current_user)
        render json: { bookings_cancelled: cancelled }
      end

      # PATCH …/calendar/series/:id — the weekly class stops
      # (RecurringSchedule#stop!).
      def stop_series
        render json: current_company.recurring_schedules.find(params[:id]).stop!
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Resource not found" }, status: :not_found
      end

      # POST …/calendar/sessions/:id/bookings — a member added from the detail.
      def book
        client = current_company.clients.find_by(id: params[:client_id])
        return render(json: { error: "Client not found" }, status: :not_found) if client.nil?
        return refuse unless capability?(:bookings) && BookingPolicy.new(current_user, Booking.new(session_id: @session.id)).create?

        @session.book!(client, drop_in: false, trial: false)
        head :created
      end

      # GET …/calendar/clients?search= — the detail's member search, the
      # first page of GET /api/v1/clients?search=.
      def clients
        render json: { clients: client_rows(Clients::ListQuery.new(current_company, params.permit(:search)).scope.limit(20)) }
      end

      # GET …/calendar/schedule?from= — the week on screen as a PDF (Pro).
      def schedule_pdf
        pdf, week_start = planner.weekly_pdf(params[:from])
        send_data pdf, filename: "planning-#{week_start.strftime('%Y-%m-%d')}.pdf", type: "application/pdf", disposition: "inline"
      end

      private

      def create_weekly
        attributes = params.require(:recurring_schedule).permit(:activity_id, :coach_id, :space_id, :start_time, :recurrence_type, :starts_on, :ends_on, weekdays: [])
        return render(json: { error: "Activity not found" }, status: :not_found) unless current_company.activities.exists?(id: attributes[:activity_id])

        schedule = current_company.recurring_schedules.new(attributes)
        return render_messages(I18n.with_locale(:en) { schedule.errors.full_messages }) unless schedule.save

        render json: schedule.generate_sessions!, status: :created
      end

      def planner
        @planner ||= Sessions::Planner.new(company: current_company, staff_member: current_staff_member)
      end

      def set_session
        @session = planner.scope.find_by(id: params[:id])
        render json: { error: "Resource not found" }, status: :not_found if @session.nil?
      end

      def date_labels(session)
        starts = session[:starts_at].in_time_zone
        ends = session[:ends_at].in_time_zone
        format = ->(time, pattern) { Web::DateFormat.angular(time, pattern, locale: I18n.locale) }
        { start: format.call(starts, "HH:mm"), end: format.call(ends, "HH:mm"), day: format.call(starts, "EEEE d MMM"), medium: format.call(starts, "medium") }
      end

      def client_rows(scope)
        scope.map { |c| { id: c.id, full_name: c.full_name, phone: c.phone } }
      end

      # SessionsController#require_session_management!: the admin, or an
      # active non-coach login that may edit the schedule.
      def refuse_unless_managing
        return if current_user.admin?
        return if current_staff_member&.active? && current_staff_member.can?(:sessions) && !current_staff_member.coach?

        refuse
      end

      def refuse
        render json: { error: "You are not allowed to perform this action" }, status: :forbidden
      end

      def render_messages(messages)
        render json: { error: messages.first || "Validation failed", errors: messages }, status: :unprocessable_content
      end
    end
  end
end
