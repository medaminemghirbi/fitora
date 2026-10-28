module Web
  # A gym opening its own account (RegisterComponent): three fields, then the
  # address is confirmed (/confirmation-email), then the gym is named.
  class RegistrationsController < BaseController
    layout "web/auth"

    before_action :go_home_if_signed_in

    def new
      # The landing page's closing form hands over a first name and an e-mail.
      @values = { first_name: params[:first_name].to_s, email: params[:email].to_s }
    end

    def create
      @values = registration_params.to_h.symbolize_keys
      return render_form if form_invalid?

      user = AccountRecovery.register(@values.merge(locale: locale_code, terms_accepted_at: Time.current))
      # The API's English message, as the Angular page shows it (K-04).
      return render_form(I18n.with_locale(:en) { user.errors.full_messages.first }) unless user.persisted?

      sign_in(user)
      redirect_to "/confirmation-email", status: :see_other
    end

    private

    def go_home_if_signed_in
      go_home if signed_in?
    end

    def registration_params
      params.permit(:first_name, :last_name, :email, :password)
    end

    # The Angular form's validators: all required, the e-mail well-formed,
    # the password 8 characters or more — and Fitora's terms accepted. The
    # e-mail and the terms have a message.
    def form_invalid?
      v = @values
      @email_invalid = v[:email].blank? || !v[:email].match?(SessionsController::EMAIL_FORMAT)
      @terms_missing = params[:accept_terms] != "1"
      @email_invalid || @terms_missing || v[:first_name].blank? || v[:last_name].blank? || v[:password].to_s.length < 8
    end

    def render_form(error = nil, status: :unprocessable_content)
      @error = error
      render :new, status: status
    end

    def rate_limited
      @values = registration_params.to_h.symbolize_keys
      render_form("rate_limited", status: :too_many_requests)
    end
  end
end
