module Web
  # "Mot de passe oublié" (ForgotPasswordComponent) and choosing the new one
  # from the emailed link (ResetPasswordComponent).
  class PasswordResetsController < BaseController
    include Web::NewPasswordForm

    layout "web/auth"

    before_action :go_home_if_signed_in, only: %i[new create]

    def new; end

    def create
      @email = params[:email].to_s
      @email_invalid = @email.empty? || !@email.match?(SessionsController::EMAIL_FORMAT)
      return render(:new, status: :unprocessable_content) if @email_invalid

      # The same answer whether or not the address has an account.
      AccountRecovery.request_password_reset(@email)
      @sent = true
      render :new
    end

    def edit
      new_password_form(:reset)
    end

    def update
      choose_password(:reset) { |token, password| AccountRecovery.reset_password(token, password) }
    end

    private

    def go_home_if_signed_in
      go_home if signed_in?
    end

    def rate_limited
      if action_name == "create"
        @email = params[:email].to_s
        @error = helpers.ngt("auth.too_many_attempts")
        render :new, status: :too_many_requests
      else
        new_password_form(:reset, error: "rate_limited", status: :too_many_requests)
      end
    end
  end
end
