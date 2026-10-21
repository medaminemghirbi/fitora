module Api
  module V1
    # Forgot-password — unauthenticated by design, same as PairingController.
    # Never for a platform superadmin (role: :superadmin) — Fitora operators aren't
    # self-service here, same line as everywhere else that special-cases them.
    class PasswordResetsController < ApplicationController
      # POST /api/v1/password_resets — { email: }. Always the same response
      # whether or not the email matches an account, so this can't be used
      # to enumerate registered emails.
      def create
        AccountRecovery.request_password_reset(params[:email])
        head :no_content
      end

      # PATCH /api/v1/password_resets/:token — { password: }
      def update
        record = AccountRecovery.reset_password(params[:token], params[:password])
        return render(json: { error: "invalid_or_expired_token" }, status: :unprocessable_content) if record == :invalid_token

        record.errors.empty? ? head(:no_content) : render_errors(record)
      end
    end
  end
end
