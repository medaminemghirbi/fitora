module Web
  module Superadmin
    # The console's own door, /superadmin/connexion: the password, as at
    # /connexion (the same form and checks, Web::SessionsController), then the
    # code of an authenticator app (TwoFactor) — set up here, from a QR code,
    # the first time. /connexion and the API's login refuse a superadmin
    # (SignIn), so the console is never opened by a password alone.
    #
    # Between the two steps nothing is signed in: the session holds who gave
    # the right password, for PENDING_FOR and MAX_TRIES codes, and the secret
    # being set up until a code proves the app has it.
    class SessionsController < Web::SessionsController
      PENDING_KEY = :fitora_superadmin_pending
      PENDING_FOR = 5.minutes
      MAX_TRIES = 5

      before_action :go_home_if_signed_in, only: %i[code verify]
      before_action :require_pending, only: %i[code verify]

      def new
        @error = flash[:alert]
        today_label
      end

      # The password: right, the code step; wrong, the form again, as
      # /connexion answers it.
      def create
        @email = params[:email].to_s
        @invalid = invalid_fields
        return render_form if @invalid.any?

        user = SignIn.superadmin(params[:email], params[:password])
        return render_form(helpers.ngt("auth.invalid_credentials")) if user.nil?

        reset_session # never carry a pre-sign-in session id across the door
        session[PENDING_KEY] = { "id" => user.id, "tv" => user.token_version, "exp" => PENDING_FOR.from_now.to_i, "tries" => 0 }
        session[PENDING_KEY]["secret"] = TwoFactor.new_secret unless user.two_factor_enabled?
        redirect_to web_superadmin_sign_in_code_path
      end

      def code
        render_code
      end

      # The code: the app's, the console opens; not, the step again — and
      # after MAX_TRIES, the password again.
      def verify
        accepted = enrolling? ? @user.enable_two_factor!(@pending["secret"], params[:otp]) : @user.verify_two_factor(params[:otp])
        if accepted
          sign_in(@user)
          return go_home
        end

        session[PENDING_KEY]["tries"] = @pending["tries"].to_i + 1
        return restart(helpers.ngt("auth.too_many_attempts")) if session[PENDING_KEY]["tries"] >= MAX_TRIES

        render_code(helpers.ngt("superadmin.two_factor.invalid_code"), status: :unprocessable_content)
      end

      private

      # Who gave the right password, still: in time, still a superadmin, and
      # their password unchanged since (token_version).
      def require_pending
        @pending = session[PENDING_KEY]
        user = @pending.present? && @pending["exp"].to_i > Time.now.to_i && User.active.superadmin.find_by(id: @pending["id"])
        @user = user if user && user.token_current?(@pending["tv"])
        restart(helpers.ngt("superadmin.two_factor.expired")) if @user.nil?
      end

      def restart(message)
        session.delete(PENDING_KEY)
        redirect_to web_superadmin_sign_in_path, alert: message
      end

      # No app set up yet (or one turned off since the password): this code
      # sets it up.
      def enrolling?
        !@user.two_factor_enabled? && @pending["secret"].present?
      end

      def render_code(error = nil, status: :ok)
        @error = error
        if enrolling?
          uri = TwoFactor.provisioning_uri(@pending["secret"], @user.email)
          @qr_svg = RQRCode::QRCode.new(uri).as_svg(module_size: 4, standalone: true, use_path: true, viewbox: true)
          @secret = @pending["secret"]
        end
        # The page can carry the secret: never kept by a cache or the back
        # button's copy.
        response.headers["Cache-Control"] = "no-store"
        today_label
        render :code, status: status
      end

      # Throttled (config/initializers/rack_attack.rb): the step it was
      # sent from, refused in words — /connexion keeps the API's code for
      # parity with Angular; this page has no Angular to match.
      def rate_limited
        message = helpers.ngt("auth.too_many_attempts")
        return render_form(message, status: :too_many_requests) unless action_name == "verify"

        require_pending
        render_code(message, status: :too_many_requests) unless performed?
      end
    end
  end
end
