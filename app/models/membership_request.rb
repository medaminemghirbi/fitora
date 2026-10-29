# A gym asking to add someone Fitora already knows: the email it typed
# belongs to a member of another gym, or to someone with their own login.
#
# The person is one record across every gym (Client), so joining them used
# to show the new gym the name and phone another gym had recorded — anyone
# with a trial account could look up a stranger by email. Now nothing is
# joined until the person says yes from the link emailed to that address
# (Web::MembershipRequestsController). Until then the gym holds only what it
# typed itself (#person, #membership), and the person is in none of its
# lists, cannot be booked, sold a plan or sent anything.
#
# One per gym and person. The link lasts EXPIRY; asking again re-sends it,
# at most once per RESEND_AFTER, and a gym sends at most DAILY_LIMIT a day.
class MembershipRequest < ApplicationRecord
  EXPIRY = 7.days
  RESEND_AFTER = 1.day
  DAILY_LIMIT = 50

  PERSON_FIELDS = %w[first_name last_name phone].freeze
  MEMBERSHIP_FIELDS = [ "notes", *Membership::PROFILE_FIELDS ].freeze

  belongs_to :company
  belongs_to :client
  belongs_to :requested_by, class_name: "User", optional: true

  def self.find_by_token(raw_token)
    return nil if raw_token.blank?

    request = find_by(token_digest: Digest::SHA256.hexdigest(raw_token.to_s))
    request if request && !request.expired?
  end

  # Asks `client` to join `company`, with what the gym typed, and emails
  # them unless a link went out less than RESEND_AFTER ago. Returns the
  # request. Raises Refused past the gym's DAILY_LIMIT.
  def self.ask!(company:, client:, by:, person:, membership:)
    request = find_or_initialize_by(company: company, client: client)
    request.assign_attributes(
      requested_by: by,
      person: person.to_h.stringify_keys.slice(*PERSON_FIELDS),
      membership: membership.to_h.stringify_keys.slice(*MEMBERSHIP_FIELDS).compact_blank
    )
    raw = nil
    if request.new_record? || request.sent_at < RESEND_AFTER.ago
      if where(company: company, sent_at: 1.day.ago..).count >= DAILY_LIMIT
        raise Refused.new("Too many requests to join sent today. Try again tomorrow.", key: "clients.errors.too_many_join_requests")
      end

      raw = SecureRandom.urlsafe_base64(32)
      request.token_digest = Digest::SHA256.hexdigest(raw)
      request.sent_at = Time.current
    end
    request.save!

    AccountMailer.membership_request(request, raw).deliver_later if raw
    request
  end

  def expired?
    sent_at < EXPIRY.ago
  end

  def expires_at
    sent_at + EXPIRY
  end

  # The person said yes: they join the gym, with what it wrote for its
  # membership, and what they left blank of their own details is filled in
  # from what it typed (as when a gym fills in a blank later). The link is
  # spent with the request. Returns the membership.
  def accept!
    transaction do
      blanks = person.select { |key, value| value.present? && client.public_send(key).blank? }
      client.update!(blanks) if blanks.any?
      joined = client.join!(company)
      joined.update!(membership) if membership.any?
      AuditLog.record!(
        company: company, user: requested_by, action: "client.joined",
        auditable: client, metadata: { name: client.full_name, accepted_request: true }
      )
      destroy!
      joined
    end
  end
end
