# Who may see and mark a session's attendance, and marking it — for
# /api/v1/attendance and every web page with a check-in panel (moved
# unchanged from Api::V1::AttendanceController).
#
# "checkin" (manager, moderator and coach all hold it) is enough to come in;
# a coach only ever touches their own sessions, everyone else with it the
# whole salle's.
class AttendanceAccess
  def initialize(user:, staff_member:, company:)
    @user = user
    @staff_member = staff_member
    @company = company
  end

  def allowed?
    return true if @user.admin?

    @staff_member&.active? && @staff_member.can?(:checkin) || false
  end

  def sessions
    scope = @company.sessions
    @staff_member&.coach? ? scope.where(coach_id: @staff_member.coach_id) : scope
  end

  def can_mark?(session)
    return true if @user.admin?
    return false unless @staff_member&.active? && @staff_member.can?(:checkin)

    @staff_member.coach? ? session.coach_id == @staff_member.coach_id : true
  end

  # The people a session expects, in booking order.
  def roster(session)
    session.bookings.held.includes(:client, :attendance_record).order(:created_at)
  end

  # This salle's booking with that id, or nil.
  def booking(id)
    Booking.joins(:session).where(sessions: { company_id: @company.id }).find_by(id: id)
  end

  def mark!(booking, status)
    AttendanceRecord.mark!(booking: booking, status: status, marked_by: @user)
    booking.reload
  end
end
