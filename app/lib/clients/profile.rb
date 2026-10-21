module Clients
  # One member's file in a salle, for GET/PATCH/DELETE /api/v1/clients/:id,
  # POST /api/v1/clients/:id/invite and the web UI's member page (moved
  # unchanged from Api::V1::ClientsController).
  module Profile
    INVITE_COOLDOWN = 60.seconds

    # Why an edit or an invitation was refused: `code` is what the API
    # sends as `error`, `message` the words, `errors` the list.
    class Refusal < StandardError
      attr_reader :code, :errors

      def initialize(message, code: nil, errors: [ message ])
        super(message)
        @code = code || message
        @errors = errors
      end
    end

    # What GET /api/v1/clients/:id answers.
    def self.payload(client, company)
      {
        client: ClientSerializer.new(client, detailed: true, company: company).as_json,
        contracts: client.contracts_for(company).for_serializer.order(created_at: :desc).map { |m| ContractSerializer.new(m).as_json },
        bookings: client.bookings_for(company).includes(session: [ :activity, :coach ]).order(created_at: :desc).limit(20).map { |b| BookingSerializer.new(b).as_json },
        payments: client.payments_for(company).recent.limit(20).map { |p| PaymentSerializer.new(p).as_json }
      }
    end

    # The person (identity fields, locked once their identity is their own
    # beyond this gym) and their membership here, in one transaction;
    # audited. Raises Refusal for a locked identity, RecordInvalid otherwise.
    def self.update(client, company:, by:, person:, membership:)
      if client.identity_shared_beyond?(company) && (locked = locked_identity_changes(client, person)).any?
        raise Refusal.new(
          "This member's #{locked.map { |f| f.humanize.downcase }.to_sentence} belong to their own Fitora account, so the gym can't change them.",
          code: "identity_locked", errors: locked.map { |field| "#{field.humanize} is managed by the member" }
        )
      end

      ActiveRecord::Base.transaction do
        client.membership_for(company).update!(membership) if membership.any?
        client.update!(person)
      end

      AuditLog.record!(
        company: company, user: by, action: "client.updated",
        auditable: client, metadata: { name: client.full_name }
      )
      client
    end

    # Switches the member's own app on: an emailed link to choose a
    # password. Raises Refusal with the API's codes.
    def self.invite(client, company:, by:)
      raise Refusal.new("This member has no email address to invite.") if client.email.blank?
      raise Refusal.new("This member already has access to the app.", code: "already_enabled") if client.login_enabled?
      if client.invitation_sent_at && client.invitation_sent_at > INVITE_COOLDOWN.ago
        raise Refusal.new("An invitation was just sent. Try again in a minute.", code: "invitation_recently_sent")
      end

      raw = client.generate_invitation_token!
      AccountMailer.member_invitation(client, company, raw).deliver_later
      AuditLog.record!(
        company: company, user: by, action: "client.invited",
        auditable: client, metadata: { name: client.full_name }
      )
      client
    end

    # Takes them off this gym — see Client#remove_from!. Audited.
    def self.remove(client, company:, by:)
      name = client.full_name
      anonymised = client.remove_from!(company)
      AuditLog.record!(
        company: company, user: by, action: "client.removed",
        auditable: client, metadata: { name: name, anonymised: anonymised }
      )
      anonymised
    end

    # The identity fields this edit would change on a person the gym no
    # longer owns. Filling a blank is not a change; neither is sending the
    # value back as it already is.
    def self.locked_identity_changes(client, changes)
      changes.select do |field, value|
        current = client.public_send(field)
        current.present? && normalize_identity(field, value) != normalize_identity(field, current)
      end.keys
    end
    private_class_method :locked_identity_changes

    def self.normalize_identity(field, value)
      normalized = value.to_s.strip
      field.to_s == "email" ? normalized.downcase : normalized
    end
    private_class_method :normalize_identity
  end
end
