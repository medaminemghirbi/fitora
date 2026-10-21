module Web
  # The check-in panel's two requests, in whichever shell the panel sits (the
  # admin's dashboard and calendar, the desk, the coach's day): the roster of
  # a session, and one mark — as /api/v1/attendance answers them
  # (AttendanceAccess). Each shell routes them under its own salle-scoped
  # path, so a page never calls into another shell.
  module AttendanceEndpoints
    extend ActiveSupport::Concern

    included do
      before_action -> { render(json: { error: "You are not allowed to perform this action" }, status: :forbidden) unless attendance_access.allowed? }
    end

    # GET …/attendance/:session_id — the panel's content.
    def show
      session = attendance_access.sessions.find_by(id: params[:session_id])
      return head(:not_found) if session.nil?

      bookings = JSON.parse(attendance_access.roster(session).map { |b| AttendanceBookingSerializer.new(b).as_json }.to_json).map(&:deep_symbolize_keys)
      # The calendar's detail draws its own rows; the check-in panel and the
      # coach's day take them drawn.
      return render(json: { bookings: bookings }) if request.format.json?

      render partial: roster_partial, formats: [ :html ], locals: { bookings: bookings }
    end

    # POST …/attendance { booking_id, status }
    def create
      booking = attendance_access.booking(params[:booking_id])
      return render(json: { error: "Booking not found" }, status: :not_found) if booking.nil?
      return render(json: { error: "You are not allowed to perform this action" }, status: :forbidden) unless attendance_access.can_mark?(booking.session)

      attendance = AttendanceBookingSerializer.new(attendance_access.mark!(booking, params[:status])).as_json
      return render(json: { attendance: attendance }) unless marked_partial && request.format.html?

      render partial: marked_partial, formats: [ :html ], locals: { booking: JSON.parse(attendance.to_json).deep_symbolize_keys }
    rescue ActiveRecord::RecordInvalid => e
      messages = I18n.with_locale(:en) { e.record.errors.full_messages }
      render json: { error: messages.first || "Validation failed", errors: messages }, status: :unprocessable_content
    end

    private

    # How a shell draws the roster, and a row once marked (nil: the mark's
    # JSON, which the check-in panel reads).
    def roster_partial = "web/shared/checkin_roster"
    def marked_partial = nil

    def attendance_access
      @attendance_access ||= AttendanceAccess.new(user: current_user, staff_member: current_staff_member, company: current_company)
    end
  end
end
