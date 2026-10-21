module Web
  module Admin
    # The shell banner's "send the link again" (POST /api/v1/email_verifications
    # for the Angular app); the same EmailVerificationResend decides.
    class EmailVerificationsController < BaseController
      def create
        case EmailVerificationResend.call(current_user)
        when :sent then head :no_content
        when :no_email, :already_verified then head :unprocessable_content
        else head :too_many_requests
        end
      end
    end
  end
end
