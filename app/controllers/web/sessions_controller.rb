module Web
  # Sign in and out (ProLoginComponent). The credentials are checked by
  # SignIn, the same object POST /api/v1/auth/login uses.
  class SessionsController < BaseController
    layout "web/auth"

    # guestGuard: someone already signed in has no business here.
    before_action :go_home_if_signed_in, only: %i[new create]

    # Angular's Validators.email, so the form refuses exactly what the
    # Angular form refuses before it is sent.
    EMAIL_FORMAT = %r{\A(?=.{1,254}\z)(?=.{1,64}@)[a-zA-Z0-9!#$%&'*+/=?^_`{|}~-]+(?:\.[a-zA-Z0-9!#$%&'*+/=?^_`{|}~-]+)*@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*\z}

    def new
      today_label
    end

    def create
      @email = params[:email].to_s
      @invalid = invalid_fields
      return render_form if @invalid.any?

      result = SignIn.call(params[:email], params[:password])
      account = result.user || result.client
      return render_form(sign_in_error(result.error)) if account.nil?

      sign_in(account)
      # The salle's own language, as the Angular app applies it from
      # /bootstrap on every sign-in (ConfigurationService#load).
      remember_locale(result.user.current_company&.locale) if result.user
      go_home
    end

    # Signing out lands on the sign-in page — or on the sign-up page, for the
    # "wrong address? start over" of the confirmation screen. Inside an
    # impersonation it ends the impersonation instead, back in the
    # superadmin's console (AuthService#logout → #exitImpersonation).
    def destroy
      if current_impersonator
        exit_impersonation
        return redirect_to("/superadmin/overview", status: :see_other)
      end

      sign_out
      to = params[:to] == "/inscription" ? "/inscription" : web_sign_in_path
      redirect_to to, status: :see_other
    end

    private

    def go_home_if_signed_in
      go_home if signed_in?
    end

    def render_form(error = nil, status: :unprocessable_content)
      @error = error
      @email = params[:email].to_s
      today_label
      render :new, status: status
    end

    # The Angular page shows the API's code as it comes (FE-01, K-05).
    def rate_limited
      render_form("rate_limited", status: :too_many_requests)
    end

    # Both required; the address well-formed — what the Angular form checks.
    def invalid_fields
      fields = []
      fields << :email if @email.empty? || !@email.match?(EMAIL_FORMAT)
      fields << :password if params[:password].to_s.empty?
      fields
    end

    # B-02: the translated message the Angular page meant to show (its
    # fallback), not the API's English. There is no translation for a member
    # whose gym has no member app, so that one stays what Angular shows.
    def sign_in_error(error)
      error == :member_app_not_included ? "member_app_not_included" : helpers.ngt("auth.invalid_credentials")
    end

    # "Mercredi 14 octobre" on the panel's day card. In the platform's own
    # time zone: the server cannot know the browser's (M-06).
    def today_label
      today = Time.current.in_time_zone("Africa/Tunis")
      @today_label = Web::DateFormat.capitalize_first(Web::DateFormat.intl(today, :weekday_day_month_long, locale: locale_code))
    end
  end
end
