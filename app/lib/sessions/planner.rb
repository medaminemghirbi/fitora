module Sessions
  # The schedule's writes and its reads by range, for /api/v1/sessions and
  # the web UI's calendar (moved unchanged from Api::V1::SessionsController).
  # `staff_member`: a coach only ever sees their own sessions.
  class Planner
    # Why a session could not be created: what was not found.
    class NotFound < StandardError; end

    # The widest range the calendar reads at once: its month view asks for
    # six weeks. A longer one never comes from it, and would load every
    # session the salle has had into memory.
    MAX_RANGE_DAYS = 62

    def initialize(company:, staff_member:)
      @company = company
      @staff_member = staff_member
    end

    def scope
      sessions = @company.sessions
      @staff_member&.coach? ? sessions.where(coach_id: @staff_member.coach_id) : sessions
    end

    # GET /sessions?from&to (&coach_id&activity_id&status) as the calendar
    # asks for it: every session in the range, serialized with its count.
    def range(from:, to:, coach_id: nil, activity_id: nil, status: nil)
      sessions = scope
      sessions = sessions.where(activity_id: activity_id) if activity_id.present?
      sessions = sessions.where(coach_id: coach_id) if coach_id.present?
      sessions = sessions.where(status: status) if status.present?
      sessions = sessions.includes(:activity, :company, :coach, :space).order(:starts_at)
                         .where(starts_at: Date.parse(from).beginning_of_day..Date.parse(to).end_of_day).to_a
      self.class.serialize(sessions)
    end

    # GET /sessions?date= as the desk and the coach's day ask for it, with no
    # page: the day's sessions in order, the API's first page of 20.
    def day(date, per_page: 20)
      scope.for_date(date).includes(:activity, :company, :coach, :space).order(:starts_at).limit(per_page).to_a
    end

    def self.serialize(sessions)
      counts = SessionSerializer.confirmed_counts(sessions)
      sessions.map { |s| SessionSerializer.new(s, confirmed_count: counts.fetch(s.id, 0)).as_json }
    end

    # A session, its capacity the activity's unless given, booked for the
    # member named (a trial or drop-in when asked) in the same transaction.
    # Raises NotFound, or RecordInvalid / Refused from the models.
    def create(attributes, client_id: nil, drop_in: false, trial: false)
      activity = @company.activities.find_by(id: attributes[:activity_id])
      raise NotFound, "Activity not found" if activity.nil?

      client = client_id.present? ? @company.clients.find_by(id: client_id) : nil
      raise NotFound, "Client not found" if client_id.present? && client.nil?

      attributes = attributes.to_h.symbolize_keys
      attributes[:capacity] = attributes[:capacity].presence || activity.capacity
      attributes.delete(:price) if attributes[:price].blank?
      session = @company.sessions.new(attributes)

      ActiveRecord::Base.transaction do
        session.save!
        session.book!(client, drop_in: drop_in, trial: trial) if client
      end
      session
    end

    # Cancels the session and its bookings; audited. Returns how many
    # bookings it cancelled.
    def cancel(session, by:)
      cancelled = session.cancel!
      AuditLog.record!(
        company: @company, user: by, action: "session.cancelled",
        auditable: session,
        metadata: { activity: session.activity.name, starts_at: session.starts_at, bookings_cancelled: cancelled }
      )
      cancelled
    end

    # The week's timetable as a PDF, from the Monday of `from`'s week.
    def weekly_pdf(from)
      week_start = (from.present? ? Date.parse(from) : Date.current).beginning_of_week(:monday)
      week_end = week_start + 6.days
      sessions = scope.where(starts_at: week_start.beginning_of_day..week_end.end_of_day).includes(:activity, :coach).order(:starts_at)
      [ Schedule::WeeklyPdf.call(company: @company, week_start: week_start, sessions: sessions), week_start ]
    end
  end
end
