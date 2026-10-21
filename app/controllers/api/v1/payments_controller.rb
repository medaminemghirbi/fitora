module Api
  module V1
    class PaymentsController < BaseController
      before_action :require_company!
      before_action -> { require_capability!(:payments) }
      # Money going back out is the admin's call, not the desk's.
      before_action :require_admin!, only: :refund
      before_action :set_payment, only: [ :show, :refund ]

      # GET /api/v1/payments?status=&payment_method=&date=
      def index
        # The rules are Payments::ListQuery's, shared with the web UI's
        # payments page.
        list = Payments::ListQuery.new(current_company, params)
        scope = list.scope

        if params[:format] == "csv"
          return render_forbidden unless current_user.admin?

          send_data payments_csv(scope), filename: "payments-#{Date.current}.csv"
        else
          render json: {
            payments: paginate(scope).map { |p| PaymentSerializer.new(p).as_json },
            meta: pagination_meta(scope),
            counts: list.counts,
            method_counts: list.method_counts,
            # Taking money at the desk is `payments`; reading what the gym
            # has taken in is `revenue`. Without it the strip is simply absent.
            **(capability?(:revenue) ? { totals: list.totals } : {})
          }
        end
      end

      # GET /api/v1/payments/:id
      def show
        render json: { payment: PaymentSerializer.new(@payment).as_json }
      end

      # POST /api/v1/payments — staff manually records a payment against a
      # client's contract or booking
      def create
        client = current_company.clients.find_by(id: params[:client_id])
        return render json: { error: "Client not found" }, status: :not_found if client.nil?

        payment = Payments::Actions.record(client, company: current_company, by: current_user, params: params)
        render json: { payment: PaymentSerializer.new(payment).as_json }, status: :created
      end

      # POST /api/v1/payments/:id/refund
      def refund
        Payments::Actions.refund(@payment, company: current_company, by: current_user)
        render json: { payment: PaymentSerializer.new(@payment.reload).as_json }
      end

      private

      def set_payment
        @payment = current_company.payments.find_by(id: params[:id])
        render_not_found if @payment.nil?
      end

      def payments_csv(scope)
        CsvSafe.generate do |csv|
          csv << [ "Client", "Amount", "Currency", "Method", "Status", "Paid at" ]
          scope.includes(:client).find_each do |p|
            csv << [ p.client.full_name, p.amount, p.currency, p.payment_method, p.status, p.paid_at ]
          end
        end
      end
    end
  end
end
