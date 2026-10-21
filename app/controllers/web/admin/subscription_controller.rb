module Web
  module Admin
    # The admin's Fitora access (SubscriptionComponent): the plan in force,
    # the period, what the plan carries, and asking for another — a support
    # ticket of kind "upgrade" with a phone number to call back on, as the
    # component sends it. Open to a locked admin (TenantRules: the way out
    # is settling); the request is refused there, as the API refuses it.
    class SubscriptionController < BaseController
      self.lock_area = :subscription

      before_action :require_admin, only: :show
      before_action -> { render(json: { error: "You are not allowed to perform this action" }, status: :forbidden) unless current_user.admin? }, only: :request_plan

      def show
        @view = Web::SubscriptionView.new(SubscriptionStatusSerializer.new(company: current_company, admin: current_user).as_json)
      end

      # POST …/subscription/request (JSON) — as POST /api/v1/support_tickets.
      def request_plan
        ticket = SupportRequest.open(company: current_company, user: current_user,
                                     subject: params[:subject].to_s.strip, message: params[:message].to_s.strip,
                                     kind: "upgrade", contact_phone: params[:contact_phone])
        return head(:created) if ticket.persisted?

        messages = I18n.with_locale(:en) { ticket.errors.full_messages }
        render json: { error: messages.first || "Validation failed", errors: messages }, status: :unprocessable_content
      end
    end
  end
end
