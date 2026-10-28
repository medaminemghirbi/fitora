module Web
  module Admin
    # The till (/admin/<salle>/cash): one day's takings — by method, by
    # login, payment by payment — and each login closing its own drawer
    # (CashClosing). Taking money is `payments`; the whole gym's takings are
    # `revenue` too — without it a login sees its own drawer only.
    class CashController < BaseController
      before_action -> { require_capability(:payments) }, only: :show
      before_action :refuse_without_payments, only: :close

      rescue_from ApplicationRecord::Refused, with: ->(refusal) { render json: { error: refusal_message(refusal) }, status: :unprocessable_content }

      helper_method :whole_gym?

      def show
        @date = requested_date
        @till = Payments::Till.new(current_company, date: @date, user: whole_gym? ? nil : current_user)
        @mine = @till.closing_for(current_user)
        @expected = @till.expected_cash(current_user)
      end

      # POST …/cash/closings — "Clôturer ma caisse": what was counted in this
      # login's drawer for the day.
      def close
        closing = CashClosing.close!(company: current_company, user: current_user, date: requested_date,
                                     counted: params[:counted_cash], notes: params[:notes])
        AuditLog.record!(company: current_company, user: current_user, action: "cash.closed", auditable: closing,
                         metadata: { date: closing.business_date.iso8601, expected: closing.expected_cash.to_s,
                                     counted: closing.counted_cash.to_s })
        render json: { expected_cash: closing.expected_cash, counted_cash: closing.counted_cash, difference: closing.difference },
               status: :created
      end

      private

      def whole_gym?
        capability?(:revenue)
      end

      def refuse_without_payments
        render(json: { error: "You are not allowed to perform this action" }, status: :forbidden) unless capability?(:payments)
      end

      # Today, or the day asked for — never one still to come.
      def requested_date
        date = params[:date].present? ? Date.parse(params[:date].to_s) : Date.current
        [ date, Date.current ].min
      rescue Date::Error
        Date.current
      end
    end
  end
end
