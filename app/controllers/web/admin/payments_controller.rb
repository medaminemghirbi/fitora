module Web
  module Admin
    # The salle's receipts (AdminPaymentsComponent): listed by
    # Payments::ListQuery, recorded and refunded through Payments::Actions —
    # the rules /api/v1/payments applies, with its capability checks. The
    # record dialog's two lookups answer what the Angular dialog reads from
    # /api/v1/clients (the search) and /api/v1/clients/:id (what is owed),
    # under the same `clients` capability.
    class PaymentsController < BaseController
      PER_PAGE = 20

      before_action -> { require_capability(:payments) }, only: :index
      before_action :refuse_without_payments, except: :index
      before_action :refuse_without_clients, only: %i[clients payables]

      STATUSES = [
        [ "", "common.all", "var(--color-primary)" ],
        [ "paid", "payments.status_paid", "var(--color-success)" ],
        [ "refunded", "payments.status_refunded", "var(--color-info)" ],
        [ "cancelled", "payments.status_cancelled", "var(--color-muted)" ]
      ].freeze

      # Card is the desk's own terminal (TPE); Fitora takes nothing online.
      METHODS = [
        [ "cash", "payments.method_cash", "var(--color-success)" ],
        [ "card", "payments.method_card", "var(--color-primary)" ],
        [ "bank_transfer", "payments.method_bank_transfer", "var(--color-info)" ],
        [ "other", "payments.method_other", "var(--color-muted)" ]
      ].freeze
      helper_method :payment_statuses, :payment_methods, :currency

      def index
        list = Payments::ListQuery.new(current_company, params.permit(:q, :status, :payment_method).to_h)
        @filters = list.params
        @page = [ params[:page].to_i, 1 ].max
        scope = list.scope
        @payments = scope.limit(PER_PAGE).offset((@page - 1) * PER_PAGE).map { |p| PaymentSerializer.new(p).as_json }
        total = scope.count
        @meta = { page: @page, per_page: PER_PAGE, total: total, total_pages: (total.to_f / PER_PAGE).ceil }
        @counts = list.counts
        @method_counts = list.method_counts
        # Taking money is `payments`; reading what the gym has taken in is
        # `revenue`. Without it the strip is not drawn.
        @totals = capability?(:revenue) ? list.totals : nil
        # ?action=new (the rail's "+") opens the record dialog. Read from the
        # query string: params[:action] is Rails' own.
        @open_record = request.query_parameters["action"] == "new"
        respond_to do |format|
          format.html
          format.turbo_stream
        end
      end

      # The dialog's "Enregistrer": against what was picked, by the method
      # picked (cash unless told otherwise).
      def create
        client = current_company.clients.find_by(id: params[:client_id])
        return render(json: { error: "Client not found" }, status: :not_found) if client.nil?

        Payments::Actions.record(
          client, company: current_company, by: current_user,
          params: params.permit(:amount, :notes, :contract_id, :booking_id).merge(payment_method: Contracts::Actions.payment_method(params))
        )
        head :no_content
      rescue ApplicationRecord::Refused => e
        render json: { error: e.message }, status: :unprocessable_content
      rescue ActiveRecord::RecordInvalid => e
        render json: { error: e.record.errors.full_messages.first || "Validation failed" }, status: :unprocessable_content
      end

      # Money going back out is the admin's call, not the desk's.
      def refund
        return render(json: { error: "You are not allowed to perform this action" }, status: :forbidden) unless current_user.admin?

        payment = current_company.payments.find_by(id: params[:id])
        return render(json: { error: "Resource not found" }, status: :not_found) if payment.nil?

        Payments::Actions.refund(payment, company: current_company, by: current_user)
        head :no_content
      rescue ApplicationRecord::Refused => e
        render json: { error: e.message }, status: :unprocessable_content
      end

      # The client search: the first page GET /api/v1/clients?search= returns.
      def clients
        list = Clients::ListQuery.new(current_company, { search: params[:search] })
        render json: { clients: list.scope.limit(PER_PAGE).map { |c| { id: c.id, full_name: c.full_name, phone: c.phone } } }
      end

      # What the picked client owes, read off what GET /api/v1/clients/:id
      # returns, exactly as the dialog reads it (selectClient): contracts with
      # money due, at their full price; the 20 latest bookings not paid.
      def payables
        client = current_company.clients.find_by(id: params[:client_id])
        return render(json: { error: "Resource not found" }, status: :not_found) if client.nil?

        contracts = client.contracts_for(current_company).for_serializer.order(created_at: :desc)
                          .select { |m| m.amount_due.to_f > 0 }
                          .map { |m| { kind: "contract", id: m.id, label: "#{ngt_label("contracts.title")} — #{m.contract_type.name}", amount_due: m.final_price.to_f } }
        bookings = client.bookings_for(current_company).includes(session: %i[activity coach]).order(created_at: :desc).limit(20)
                         .select { |b| b.payment_status != "paid" && b.amount.to_f > 0 }
                         .map { |b| { kind: "booking", id: b.id, label: "#{ngt_label("bookings.title")} — #{b.session.activity.name}", amount_due: b.amount.to_f } }
        render json: { client: { id: client.id, full_name: client.full_name }, payables: contracts + bookings }
      end

      private

      def refuse_without_payments
        render(json: { error: "You are not allowed to perform this action" }, status: :forbidden) unless capability?(:payments)
      end

      def refuse_without_clients
        render(json: { error: "You are not allowed to perform this action" }, status: :forbidden) unless capability?(:clients)
      end

      def ngt_label(key)
        helpers.ngt(key)
      end

      def payment_statuses
        STATUSES
      end

      def payment_methods
        METHODS
      end

      def currency
        bootstrap.dig(:branding, :currency) || "TND"
      end
    end
  end
end
