module Clients
  # Adds someone to a gym (Client.enrol!), optionally selling them a plan and
  # taking the money in the same transaction — which is what actually happens
  # at a front desk. A member who exists but has no subscription because the
  # plan had no price for that activity is exactly the mess this avoids.
  #
  # POST /api/v1/clients and the web UI's new-member wizard both go through
  # here (MIGRATION_AUDIT §3.2); moved unchanged from
  # Api::V1::ClientsController#create. Whether the caller may sell a plan at
  # all (the `contracts` capability) is the caller's check, made first.
  #
  # An email Fitora already knows, for a person this gym does not train yet
  # (Client#consent_needed_to_join?), adds no one: the person is asked
  # (MembershipRequest) and the Result carries the request instead — no
  # client, and no plan sold. The gym sells it once they have accepted.
  #
  # Raises ApplicationRecord::Refused (plan / pack / activity not found, or a
  # refusal from Contract.sell! or MembershipRequest.ask!) and
  # ActiveRecord::RecordInvalid; nothing is kept when either is raised.
  class Enrolment
    Result = Struct.new(:client, :contract, :payment, :request, keyword_init: true) do
      # The person was asked rather than added.
      def pending?
        !request.nil?
      end
    end

    # `subscription`: contract_type_id, activity_id | pack_id, starts_on,
    # discount, collect_payment, payment_method, payment_notes — or empty.
    def self.call(company:, user:, person:, membership:, subscription: {})
      new(company, user).call(person, membership, subscription.to_h.with_indifferent_access)
    end

    def initialize(company, user)
      @company = company
      @user = user
    end

    def call(person, membership, subscription)
      known = Client.find_by_email(person.to_h.stringify_keys["email"])
      if known&.consent_needed_to_join?(company)
        request = MembershipRequest.ask!(company: company, client: known, by: user, person: person, membership: membership)
        return Result.new(request: request)
      end

      client = contract = nil
      ActiveRecord::Base.transaction do
        client = Client.enrol!(company, person: person, membership: membership)
        contract = sell_plan_to(client, subscription) if subscription.present?
      end

      AuditLog.record!(
        company: company, user: user,
        action: client.previously_new_record? ? "client.created" : "client.joined",
        auditable: client, metadata: { name: client.full_name }
      )
      Result.new(client: client, contract: contract, payment: contract&.payments&.first)
    end

    private

    attr_reader :company, :user

    def sell_plan_to(client, subscription)
      # Only a formule on sale: the one the other ways to sell accept.
      plan = company.contract_types.active.find_by(id: subscription[:contract_type_id])
      raise ApplicationRecord::Refused, "Plan not found" if plan.nil?

      # A pack is sold in place of an activity — one or the other.
      pack = nil
      activity = nil
      if subscription[:pack_id].present?
        pack = company.packs.active.find_by(id: subscription[:pack_id])
        raise ApplicationRecord::Refused, "Pack not found" if pack.nil?
      else
        activity = company.activities.find_by(id: subscription[:activity_id])
        raise ApplicationRecord::Refused, "Activity not found" if activity.nil?
      end

      Contract.sell!(
        client: client, contract_type: plan, activity: activity, pack: pack, created_by: user,
        starts_on: subscription[:starts_on].presence&.to_date || Date.current,
        discount: subscription[:discount].presence || 0,
        collect_payment: subscription[:collect_payment],
        payment_method: subscription[:payment_method],
        payment_notes: subscription[:payment_notes]
      )
    end
  end
end
