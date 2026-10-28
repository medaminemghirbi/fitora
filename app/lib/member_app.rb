# What a member's own app shows — their gym's schedule, their bookings,
# their file — from one definition for GET /api/v1/me/* and the web UI's
# member shell (MIGRATION_AUDIT §3.2). Moved here unchanged from
# Api::V1::Me::{Sessions,Bookings,Profiles}Controller.
#
# `company_ids` are always the member's own gyms whose app they can use
# (TenantRules#member_companies): the scoping IS the tenancy check, so a gym
# they have not joined cannot appear.
module MemberApp
  module_function

  # How many bookings each tab lists (upcoming soonest, past latest first).
  BOOKINGS_LIMIT = 50

  # The schedule (GET /me/sessions), through PublicSessionSerializer: how
  # many places are left, never what the gym charges or who else is coming.
  def sessions(client, company_ids, date: nil)
    scope = ::Session.where(company_id: company_ids) # rubocop:disable Fitora/UnscopedTenantQuery
                     .where(status: :scheduled)
                     .upcoming
                     .order(:starts_at)
    scope = scope.for_date(date) if date
    scope = scope.includes(:activity, :coach, :space)

    sessions = scope.map { |s| PublicSessionSerializer.new(s, current_client: client).as_json }
    # A one-to-one slot someone else has taken is not a session this member
    # could ever join — it is another person's appointment, and listing it
    # as "full" would only bury the free slots.
    sessions.reject { |s| s[:individual] && s[:full] && !s[:already_booked] }
  end

  # Their bookings (GET /me/bookings), upcoming soonest first or past latest
  # first.
  def bookings(client, company_ids, upcoming:)
    client.bookings.joins(:session)
          .where(sessions: { company_id: company_ids })
          .where(upcoming ? "sessions.starts_at >= ?" : "sessions.starts_at < ?", Time.current)
          .order("sessions.starts_at #{upcoming ? 'asc' : 'desc'}")
          .limit(BOOKINGS_LIMIT)
          .map { |b| BookingSerializer.new(b).as_json }
  end

  # Their file (GET /me/profile): who they are, which gyms they can open,
  # the subscription they train on at `company`, and whether they have been
  # turning up. Deliberately not ClientSerializer/ContractSerializer — those
  # are the gym's view and carry prices, discounts and payment status.
  def profile(client, company, gyms)
    {
      client: identity(client),
      gyms: gyms.map { |c| { id: c.id, name: c.name } },
      subscription: subscription(client, company),
      attendance: attendance(client, company),
      # The card the gym's door scans, to show from the phone when the
      # plastic one is at home.
      card_code: client.membership_for(company)&.card_code
    }
  end

  def identity(client)
    {
      id: client.id,
      full_name: client.full_name,
      first_name: client.first_name,
      last_name: client.last_name,
      email: client.email,
      phone: client.phone
    }
  end

  def subscription(client, company)
    contract = client.current_contract(company)
    return nil if contract.nil?

    {
      plan_name: contract.contract_type.name,
      activity_name: contract.activity_label,
      activity_emoji: contract.activity&.emoji,
      all_access: contract.all_access?,
      starts_at: contract.starts_at,
      expires_at: contract.expires_at,
      # nil means the plan is unlimited, not that none are left.
      remaining_bookings: contract.remaining_bookings
    }
  end

  def attendance(client, company)
    attended = client.bookings_for(company)
                     .joins(:attendance_record, :session)
                     .where(attendance_records: { status: :present })
                     .order("sessions.starts_at DESC")
                     .limit(20)

    {
      rate: client.attendance_rate(company),
      recent: attended.map do |booking|
        {
          id: booking.id,
          activity_name: booking.session.activity.name,
          activity_emoji: booking.session.activity.emoji,
          starts_at: booking.session.starts_at
        }
      end
    }
  end
end
