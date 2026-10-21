# The people a coach actually trains: everyone with a live booking on one of
# their own sessions — what GET /api/v1/coach/members answers and what the
# web UI's coach shell lists, from one definition (MIGRATION_AUDIT §3.2).
# Moved here unchanged from Api::V1::Coach::MembersController.
#
# A coach sees a member's name, how to reach them, and when they last came or
# next will. Not their subscription, not their balance, not what they have
# paid — none of that is a coach's business, and it is absent from the rows
# rather than merely unused. Their contraindications ARE the coach's
# business: an EMS suit or a reformer is not something to put someone with a
# pacemaker or a recent injury on without knowing.
class CoachMembers
  def initialize(company:, staff_member:)
    @company = company
    @staff_member = staff_member
  end

  # Matching `q`, by name.
  def scope(q)
    members.merge(::Client.search(q))
  end

  # One page of `scope`, as rows.
  def rows(page_scope)
    page = page_scope.to_a
    @health = @company.memberships.where(client_id: page.map(&:id)).pluck(:client_id, :health_notes).to_h
    page.map { |client| serialize(client) }
  end

  private

  # Only this coach's own sessions, and only bookings that still stand — a
  # cancelled booking does not make someone your member.
  def my_sessions
    @company.sessions.where(coach_id: @staff_member.coach_id)
  end

  def members
    @company.clients
            .joins(bookings: :session)
            .where(sessions: { id: my_sessions.select(:id) })
            .where.not(bookings: { status: :cancelled })
            .distinct
  end

  def serialize(client)
    {
      id: client.id,
      full_name: client.full_name,
      phone: client.phone,
      email: EmailMask.call(client.email),
      health_notes: @health[client.id].presence,
      last_seen_at: last_seen_at(client),
      next_session_at: next_session_at(client)
    }
  end

  def last_seen_at(client)
    my_sessions.joins(:bookings)
               .where(bookings: { client_id: client.id })
               .where.not(bookings: { status: :cancelled })
               .where(starts_at: ..Time.current)
               .maximum(:starts_at)
  end

  def next_session_at(client)
    my_sessions.joins(:bookings)
               .where(bookings: { client_id: client.id })
               .where.not(bookings: { status: :cancelled })
               .where(starts_at: Time.current..)
               .minimum(:starts_at)
  end
end
