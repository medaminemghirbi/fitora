module Web
  # A member choosing their password from their gym's invitation: the reset
  # form with its own words (ResetPasswordComponent, mode "invitation").
  class InvitationsController < BaseController
    include Web::NewPasswordForm

    layout "web/auth"

    def edit
      new_password_form(:invitation)
    end

    def update
      choose_password(:invitation) { |token, password| AccountRecovery.accept_invitation(token, password) }
    end

    private

    def rate_limited
      new_password_form(:invitation, error: "rate_limited", status: :too_many_requests)
    end
  end
end
