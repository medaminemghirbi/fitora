module Api
  module V1
    class AttendanceController < BaseController
      before_action :require_company!
      before_action :require_attendance_access!, only: [ :index, :create ]

      # GET /api/v1/attendance?session_id=
      def index
        session = access.sessions.find_by(id: params[:session_id])
        return render_not_found if session.nil?

        render json: { session: SessionSerializer.new(session).as_json, bookings: access.roster(session).map { |b| AttendanceBookingSerializer.new(b).as_json } }
      end

      # POST /api/v1/attendance
      def create
        booking = access.booking(params[:booking_id])
        return render json: { error: "Booking not found" }, status: :not_found if booking.nil?
        return render_forbidden unless access.can_mark?(booking.session)

        render json: { attendance: AttendanceBookingSerializer.new(access.mark!(booking, params[:status])).as_json }
      end

      private

      # Who may see and mark what: AttendanceAccess.
      def access
        @access ||= AttendanceAccess.new(user: current_user, staff_member: current_staff_member, company: current_company)
      end

      def require_attendance_access!
        render_forbidden unless access.allowed?
      end
    end
  end
end
