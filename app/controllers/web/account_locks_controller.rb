module Web
  # The only page a locked gym sees (AccountLockedComponent): no shell, no
  # navigation — what it owes and its invoices are the only way out.
  class AccountLocksController < BaseController
    before_action -> { sign_in_first unless signed_in? }

    def show
      subscription = bootstrap&.dig(:subscription)
      @admin = current_user&.admin?
      @reason = (subscription&.dig(:lock_reason) || "suspended").to_s
      @trial_over = @reason == "unpaid" && subscription&.dig(:trial)
      @copy_key = @trial_over ? "trial_over" : @reason
      render layout: "web/auth"
    end
  end
end
