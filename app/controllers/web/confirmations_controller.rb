module Web
  # Between signing up and clicking the emailed link (ConfirmEmailComponent):
  # waits for the click — from this tab, another one, or a phone — and moves
  # on by itself. Open only to a signed-in admin whose address is still
  # unconfirmed (emailPendingGuard); anyone else goes home.
  class ConfirmationsController < BaseController
    layout "web/auth"

    before_action :require_pending

    def show
      @email = current_user.email
      @resend_in = current_user.email_verification_resend_in.to_i
    end

    # GET /confirmation-email/status — has the link been clicked yet?
    def status
      render json: { email_verified: current_user.reload.email_verified?, continue_url: continue_url }
    end

    # POST /confirmation-email/resend — the API's answers, for the countdown.
    def resend
      case (outcome = EmailVerificationResend.call(current_user))
      when :sent then head :no_content
      when :no_email, :already_verified then render json: { error: outcome.to_s }, status: :unprocessable_content
      else render json: { error: "too_soon", retry_in: outcome.last }, status: :too_many_requests
      end
    end

    private

    # Status and resend keep answering once the address is confirmed: the
    # page asks, finds out, and moves on.
    def require_pending
      return sign_in_first unless current_user
      return if action_name != "show" || email_confirmation_required?

      go_home
    end

    # ConfirmEmailComponent#continue: naming the gym, or home for an admin
    # who already has one.
    def continue_url
      current_user.current_company.nil? ? "/admin/setup-company" : home_path
    end

    def rate_limited
      render json: { error: "rate_limited" }, status: :too_many_requests
    end
  end
end
