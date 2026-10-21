module Api
  module V1
    # Confirms an email is real. For an admin that is what opens the account
    # (Api::V1::BaseController#require_confirmed_email!); for anyone else it
    # is informational. Never for a platform superadmin (role: :superadmin), same
    # exclusion as PasswordResetsController.
    class EmailVerificationsController < ApplicationController
      before_action :authenticate_request!, only: [ :create ]

      # POST /api/v1/email_verifications — resend, for the signed-in
      # user/client.
      def create
        record = current_client || current_user
        return render_forbidden if record.nil? || (record.is_a?(User) && record.superadmin?)
        case (outcome = EmailVerificationResend.call(record))
        when :sent then head :no_content
        when :no_email, :already_verified then render json: { error: outcome.to_s }, status: :unprocessable_content
        else render json: { error: "too_soon", retry_in: outcome.last }, status: :too_many_requests
        end
      end

      # PATCH /api/v1/email_verifications/:token — unauthenticated: the
      # token itself, from the emailed link, is the proof.
      def update
        return head(:no_content) if AccountRecovery.verify_email(params[:token])

        render json: { error: "invalid_or_expired_token" }, status: :unprocessable_content
      end
    end
  end
end
