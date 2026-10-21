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
  # Raises ApplicationRecord::Refused (plan / pack / activity not found, or a
  # refusal from Contract.sell!) and ActiveRecord::RecordInvalid; nothing is
  # kept when either is raised.
  class Enrolment
    Result = Struct.new(:client, :contract, :payment, keyword_init: true)

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
      plan = company.contract_types.find_by(id: subscription[:contract_type_id])
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
