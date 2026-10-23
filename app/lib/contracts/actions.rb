module Contracts
  # Renewing, pausing and resuming a contract, each with its audit trail, and
  # the formule a sale or a renewal names — for /api/v1/contracts and the
  # web UI alike (moved unchanged from Api::V1::ContractsController).
  module Actions
    # Why a formule could not be read: which of the three was not found.
    class NotFound < StandardError; end

    # [plan, activity, pack] from contract_type_id + activity_id / pack_id,
    # each this gym's own; NotFound names the one that is not.
    def self.formule(company, params)
      plan = company.contract_types.active.find_by(id: params[:contract_type_id])
      raise NotFound, "Contract plan not found" if plan.nil?

      # A pack is sold in place of an activity — one or the other.
      if params[:pack_id].present?
        pack = company.packs.active.find_by(id: params[:pack_id])
        raise NotFound, "Pack not found" if pack.nil?

        return [ plan, nil, pack ]
      end

      activity = company.activities.find_by(id: params[:activity_id])
      raise NotFound, "Activity not found" if activity.nil?

      [ plan, activity, nil ]
    end

    # The formule a renewal moves onto: the one named in the request, or —
    # when none is — the one the renewed contract is already on.
    def self.renewal_formule(contract, company, params)
      return [ contract.contract_type, contract.activity, contract.pack ] if params[:contract_type_id].blank?

      formule(company, params)
    end

    # A new contract for this client: the formule the request names, from
    # the day it names (today by default), collected now when asked; audited.
    def self.sell(client, company:, by:, params:)
      plan, activity, pack = formule(company, params)
      contract = Contract.sell!(
        client: client, contract_type: plan, activity: activity, pack: pack, created_by: by,
        starts_on: params[:starts_on].present? ? Date.parse(params[:starts_on]) : Date.current,
        discount: params[:discount].presence || 0,
        collect_payment: params[:collect_payment], payment_method: params[:payment_method]
      )
      AuditLog.record!(
        company: company, user: by, action: "contract.created",
        auditable: contract, metadata: { client: client.full_name, plan: plan.name }
      )
      contract
    end

    # Sells the next term, a new contract linked to this one — with the
    # discount the request names (Contract#renew! decides when it names
    # none), and collected at once when it asks, as a sale can be.
    def self.renew(contract, company:, by:, params:)
      plan, activity, pack = renewal_formule(contract, company, params)
      Contract.transaction do
        renewal = contract.renew!(contract_type: plan, activity: activity, pack: pack, created_by: by,
                                  discount: params[:discount].presence)
        AuditLog.record!(
          company: company, user: by, action: "contract.renewed",
          auditable: renewal, metadata: { client: contract.client.full_name, plan: plan.name, renewed_from: contract.id }
        )
        if ActiveModel::Type::Boolean.new.cast(params[:collect_payment])
          Payments::Actions.record(renewal.client, company: company, by: by,
                                                   params: { contract_id: renewal.id, payment_method: payment_method(params) })
        end
        renewal
      end
    end

    # Its dates, or its discount while unpaid (Contract#update_term!).
    def self.update(contract, company:, by:, params:)
      contract.update_term!(starts_on: params[:starts_on], expires_on: params[:expires_on], discount: params[:discount])
      audit(contract, company, by, "contract.updated")
    end

    # Ended on purpose: nothing books against it any more, and whatever it
    # still owed is forgiven. Payments already taken stay where they are.
    def self.cancel(contract, company:, by:)
      contract.cancel!
      audit(contract, company, by, "contract.cancelled")
    end

    # A method the gym takes money by (Payment::SELECTABLE_METHODS), cash
    # unless the request names another.
    def self.payment_method(params)
      method = params[:payment_method].to_s
      Payment::SELECTABLE_METHODS.include?(method) ? method : "cash"
    end

    # Membership on hold (Contract#pause!).
    def self.pause(contract, company:, by:)
      contract.pause!
      audit(contract, company, by, "contract.paused")
    end

    # End the hold, give the time back.
    def self.resume(contract, company:, by:)
      contract.resume!
      audit(contract, company, by, "contract.resumed")
    end

    def self.audit(contract, company, by, action)
      AuditLog.record!(
        company: company, user: by, action: action,
        auditable: contract, metadata: { client: contract.client.full_name, plan: contract.contract_type.name }
      )
      contract
    end
    private_class_method :audit
  end
end
