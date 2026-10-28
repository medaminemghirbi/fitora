# A member coming through the door — the gym's own record of who trained
# there and when, with or without a class booked.
#
# The desk scans the member's card (or picks them by name) and reads the
# verdict first (Visit.verdict_for): green, come in; amber, come in but
# something needs saying; red, not like this. A red verdict can still be
# overridden — a member who renews tomorrow, a forgotten payment — and the
# visit then says it was forced, and why, for the owner to read later.
class Visit < ApplicationRecord
  belongs_to :company
  belongs_to :client
  belongs_to :contract, optional: true
  belongs_to :checked_in_by, class_name: "User", optional: true

  # Why a verdict is red, most serious first; the first that applies wins.
  REFUSALS = %w[inactive no_subscription expired not_started paused no_sessions_left unpaid].freeze
  # What an amber verdict says, beside letting the member in.
  NOTICES = %w[already_in expires_soon last_session].freeze

  validates :checked_in_at, presence: true
  validates :reason, inclusion: { in: REFUSALS }, allow_nil: true

  # A scanner that reads a card twice, or a desk that clicks twice, is one
  # visit, not two.
  REPEAT_WINDOW = 2.minutes
  # How close to its end a subscription is worth mentioning at the door.
  EXPIRES_SOON_DAYS = 3

  scope :newest_first, -> { order(checked_in_at: :desc) }
  scope :on_day, ->(date) { where(checked_in_at: date.in_time_zone.all_day) }

  # What the desk is told about this member, now, in this gym.
  #
  # tone     "green", "amber" or "red"
  # reason   the refusal (REFUSALS), nil unless red
  # notices  what amber has to say (NOTICES)
  # contract the subscription the visit counts against — the one running,
  #          or, when none is, the one the refusal is about
  # balance  what the member owes this gym
  # last_visit_at  their previous visit here
  Verdict = Data.define(:tone, :reason, :notices, :contract, :balance, :last_visit_at) do
    def refused?
      tone == "red"
    end
  end

  def self.verdict_for(client, company)
    membership = client.membership_for(company)
    contracts = client.contracts_for(company).includes(:contract_type)
    running = contracts.running.order(Client::CURRENT_CONTRACT_ORDER).first
    balance = client.outstanding_balance(company).to_d
    last_visit_at = where(company: company, client: client).maximum(:checked_in_at)

    reason, contract = refusal(membership, contracts, running, balance)
    notices = reason ? [] : notices_for(running, last_visit_at)
    tone = if reason then "red" elsif notices.any? then "amber" else "green" end
    Verdict.new(tone: tone, reason: reason, notices: notices, contract: contract || running,
                balance: balance, last_visit_at: last_visit_at)
  end

  # Lets the member in and returns the visit. A red verdict is refused
  # unless `force`, and the visit then records it. A counted subscription
  # (a "carte 10 séances") gives up one session for the visit — unless a
  # class booked today already took it. A second scan within REPEAT_WINDOW
  # returns the visit the first one made.
  def self.admit!(client:, company:, by:, force: false, at: Time.current)
    verdict = verdict_for(client, company)
    if verdict.refused? && !force
      raise Refused.new("Entry refused: #{verdict.reason.humanize.downcase}.", key: "entries.errors.#{verdict.reason}")
    end

    transaction do
      # One member at a time: two scans in flight queue here, and the second
      # finds the first one's visit.
      Membership.where(company: company, client: client).lock.first
      repeat = where(company: company, client: client, checked_in_at: (at - REPEAT_WINDOW)..at).first
      next repeat if repeat

      contract = verdict.contract
      # Only the subscription running now gives a session — never the
      # lapsed or paused one a forced entry is about.
      consume = contract.present? && verdict.reason.in?([ nil, "unpaid" ]) &&
                takes_a_session?(contract.lock!, client: client, on: at.to_date)
      contract.consume_booking! if consume

      visit = create!(company: company, client: client, contract: contract, checked_in_by: by, checked_in_at: at,
                      forced: verdict.refused?, reason: verdict.reason, consumed_session: consume)
      if visit.forced?
        AuditLog.record!(company: company, user: by, action: "visit.forced", auditable: visit,
                         metadata: { name: client.full_name, reason: verdict.reason })
      end
      visit
    end
  end

  # A visit recorded by mistake (the wrong member picked): gone, and the
  # session it took given back.
  def undo!
    transaction do
      contract&.restore_booking! if consumed_session?
      destroy!
    end
  end

  # [reason, the contract it is about] — or nil when the member may come in.
  def self.refusal(membership, contracts, running, balance)
    return [ "inactive", nil ] if membership.nil? || !membership.active?

    if running.nil?
      paused = contracts.in_force.where.not(paused_at: nil).order(Client::CURRENT_CONTRACT_ORDER).first
      return [ "paused", paused ] if paused

      upcoming = contracts.upcoming.order(:starts_at).first
      return [ "not_started", upcoming ] if upcoming

      lapsed = contracts.where.not(status: :cancelled).where.not(expires_at: nil).order(expires_at: :desc).first
      return [ "expired", lapsed ] if lapsed

      return [ "no_subscription", nil ]
    end

    left = sessions_left(running)
    return [ "no_sessions_left", running ] if left && left <= 0
    return [ "unpaid", running ] if balance.positive?

    nil
  end
  private_class_method :refusal

  def self.notices_for(running, last_visit_at)
    notices = []
    notices << "already_in" if last_visit_at && last_visit_at >= Time.current.beginning_of_day
    notices << "expires_soon" if running.days_left && running.days_left <= EXPIRES_SOON_DAYS
    notices << "last_session" if sessions_left(running) == 1
    notices
  end
  private_class_method :notices_for

  # Sessions left on a counted subscription; nil when it counts none.
  def self.sessions_left(contract)
    return nil if contract.contract_type.unlimited_bookings? || contract.remaining_bookings.nil?

    contract.remaining_bookings
  end
  private_class_method :sessions_left

  def self.takes_a_session?(contract, client:, on:)
    return false unless sessions_left(contract).to_i.positive?

    booked = client.bookings.joins(:session).where(contract: contract, status: %i[confirmed completed])
                   .where(sessions: { starts_at: on.in_time_zone.all_day })
    !booked.exists?
  end
  private_class_method :takes_a_session?
end
