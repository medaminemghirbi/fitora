module Api
  module V1
    class BookingsController < BaseController
      before_action :require_company!
      before_action -> { require_capability!(:bookings) }, only: :index
      before_action :set_booking, only: [ :show, :cancel, :remind ]

      # GET /api/v1/bookings — filterable list of the company's bookings (coaches
      # narrowed to their own sessions)
      def index
        # status and date come from the list's filter rail; the rules are
        # Bookings::ListQuery's, shared with the web UI's bookings page.
        list = Bookings::ListQuery.new(current_company, params, staff_member: current_staff_member)
        scope = list.scope

        if params[:format] == "csv"
          return render_forbidden unless current_user.admin?

          send_data bookings_csv(scope), filename: "bookings-#{Date.current}.csv"
        else
          render json: {
            bookings: paginate(scope).map { |b| BookingSerializer.new(b).as_json },
            meta: pagination_meta(scope),
            counts: list.counts
          }
        end
      end

      # GET /api/v1/bookings/:id
      def show
        return render_forbidden unless BookingPolicy.new(current_user, @booking).show?

        render json: { booking: BookingSerializer.new(@booking).as_json }
      end

      # POST /api/v1/bookings — staff books a client into a session
      def create
        return render_forbidden unless capability?(:bookings)

        client = current_company.clients.find_by(id: params[:client_id])
        return render json: { error: "Client not found" }, status: :not_found if client.nil?

        session = current_company.sessions.find_by(id: params[:session_id])
        return render json: { error: "Session not found" }, status: :not_found if session.nil?
        return render_forbidden unless BookingPolicy.new(current_user, Booking.new(session_id: session.id)).create?

        booking = session.book!(client, drop_in: truthy?(params[:drop_in]), trial: truthy?(params[:trial]))
        render json: { booking: BookingSerializer.new(booking).as_json }, status: :created
      end

      # POST /api/v1/bookings/:id/cancel
      def cancel
        return render_forbidden unless BookingPolicy.new(current_user, @booking).cancel?

        Bookings::Actions.cancel(@booking, by: current_user)
        render json: { booking: BookingSerializer.new(@booking.reload).as_json }
      end

      # POST /api/v1/bookings/:id/remind — "Remind client" button, sends an
      # SMS (Booking#send_reminder!).
      def remind
        return render_forbidden unless BookingPolicy.new(current_user, @booking).remind?

        Bookings::Actions.remind(@booking, by: current_user)
        render json: { status: "sent" }
      end

      private

      def truthy?(value)
        ActiveModel::Type::Boolean.new.cast(value) || false
      end

      # Company only — never narrowed to "this coach's own sessions" the way
      # org_scope is. set_booking uses this, not org_scope: a coach hitting
      # another coach's booking is a BookingPolicy#show? 403 (a role check),
      # not a 404 — only a booking truly outside the company should 404.
      def company_scope
        Booking.joins(:session).where(sessions: { company_id: current_company.id })
      end

      def bookings_csv(scope)
        CsvSafe.generate do |csv|
          csv << [ "Client", "Activity", "Session start", "Status", "Amount", "Payment status" ]
          scope.includes(:client, session: :activity).find_each do |b|
            csv << [ b.client.full_name, b.session.activity.name, b.session.starts_at, b.status, b.amount, b.payment_status ]
          end
        end
      end

      def set_booking
        @booking = company_scope.find(params[:id])
      end
    end
  end
end
