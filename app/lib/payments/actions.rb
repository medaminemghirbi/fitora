module Payments
  # Recording a payment and refunding one, each with its audit trail — for
  # /api/v1/payments and the web UI alike (moved unchanged from
  # Api::V1::PaymentsController). Who may refund is the caller's question.
  module Actions
    # contract_id / booking_id name what is settled — this gym's only: the
    # person may owe other gyms too.
    def self.record(client, company:, by:, params:)
      payment = Payment.collect!(
        client: client, company: company, created_by: by,
        amount: params[:amount], payment_method: params[:payment_method], notes: params[:notes],
        contract: find_payable(company.contracts.where(client_id: client.id), params[:contract_id]),
        booking: find_payable(client.bookings_for(company), params[:booking_id])
      )

      AuditLog.record!(
        company: company, user: by, action: "payment.recorded",
        auditable: payment, metadata: { client: client.full_name, amount: payment.amount, method: payment.payment_method }
      )
      payment
    end

    def self.refund(payment, company:, by:)
      payment.refund!
      AuditLog.record!(
        company: company, user: by, action: "payment.refunded",
        auditable: payment, metadata: { client: payment.client.full_name, amount: payment.amount }
      )
      payment
    end

    def self.find_payable(scope, id)
      return nil if id.blank?

      scope.find_by(id: id)
    end
    private_class_method :find_payable
  end
end
