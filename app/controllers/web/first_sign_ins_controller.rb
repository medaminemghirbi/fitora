module Web
  # The first sign-in of an account a superadmin opened: the generated password,
  # which went by e-mail, replaced by one the admin chooses, and Fitora's terms
  # accepted. Each is asked for only while it is missing (User#first_sign_in_pending?).
  #
  # The session carries on: having just typed the generated password is the
  # proof the form would otherwise ask for.
  class FirstSignInsController < BaseController
    layout "web/auth"

    before_action :require_pending

    def show; end

    # PATCH /premiere-connexion — the form's checks, again; then home.
    def update
      return render(:show, status: :unprocessable_content) unless form_valid?

      current_user.terms_accepted_at ||= Time.current
      current_user.password = params[:password] if current_user.must_change_password?
      unless current_user.save
        # Real backend text, as the reset form shows it (K-04).
        @password_error = I18n.with_locale(:en) { current_user.errors.full_messages.first }
        current_user.restore_attributes
        return render(:show, status: :unprocessable_content)
      end

      keep_session_after_password_change
      go_home
    end

    private

    # Only the admin themselves, and only while it is owed: a superadmin helping
    # inside the account never chooses their password.
    def require_pending
      return sign_in_first unless current_user
      return go_home if email_confirmation_required?

      go_home unless first_sign_in_required?
    end

    def form_valid?
      @terms_missing = current_user.terms_accepted_at.nil? && params[:accept_terms] != "1"
      password_valid? && !@terms_missing
    end

    def password_valid?
      return true unless current_user.must_change_password?

      password = params[:password].to_s
      @password_error =
        if password.length < 8 then helpers.ngt("auth.password_min_length")
        elsif password != params[:password_confirmation].to_s then helpers.ngt("auth.passwords_must_match")
        elsif current_user.authenticate(password) then helpers.ngt("auth.first_sign_in_same_password")
        end
      @password_error.nil?
    end

    # A new password moves token_version on, which ends every session; this one
    # follows it (as Web::PasswordEndpoints#update_password does).
    def keep_session_after_password_change
      claims = session[Web::Authentication::SESSION_KEY]
      session[Web::Authentication::SESSION_KEY] = claims.merge("tv" => current_user.token_version, "exp" => session_lifetime(current_user).from_now.to_i)
    end
  end
end
