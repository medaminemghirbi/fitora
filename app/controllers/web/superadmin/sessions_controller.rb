module Web
  module Superadmin
    # The console's own door, /superadmin/connexion: the password, as at
    # /connexion (the same form and checks, Web::SessionsController), then the
    # code of an authenticator app (TwoFactor). /connexion and the API's login
    # refuse a superadmin (SignIn), so the console is never opened by a
    # password alone.
    #
    # The app is set up on the server (bin/rails superadmin:setup_two_factor),
    # never here: a page that set one up after the password let whoever had
    # the password bind their own app. Without one, the password is refused
    # with the way to get one.
    #
    # Between the two steps nothing is signed in: the session holds who gave
    # the right password, for PENDING_FOR. The codes tried are counted in Redis, per
    # superadmin: MAX_TRIES per TRIES_WINDOW, however many times the password
    # is given again. The session is a cookie, and a cookie that counted them
    # could be sent again from before the first wrong code.
    class SessionsController < Web::SessionsController
      PENDING_KEY = :fitora_superadmin_pending
      PENDING_FOR = 5.minutes
      MAX_TRIES = 5
      TRIES_WINDOW = 15.minutes

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
        return render_form(helpers.ngt("superadmin.two_factor.not_set_up")) unless user.two_factor_enabled?

        reset_session # never carry a pre-sign-in session id across the door
        session[PENDING_KEY] = { "id" => user.id, "tv" => user.token_version, "exp" => PENDING_FOR.from_now.to_i }
        redirect_to web_superadmin_sign_in_code_path
      end

      def code
        render_code
      end

      # The code: the app's, the console opens; not, the step again — and
      # after MAX_TRIES, the password again. Past MAX_TRIES in the window, no
      # code is even checked.
      def verify
        tries = count_try
        return restart(helpers.ngt("auth.too_many_attempts")) if tries > MAX_TRIES

        if @user.verify_two_factor(params[:otp])
          forget_tries
          sign_in(@user)
          return go_home
        end

        return lock_out if tries == MAX_TRIES

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

      # Counted before the code is checked, in one step, so codes sent at
      # once cannot all slip under the limit. The window starts at the first.
      def count_try
        Sidekiq.redis do |redis|
          redis.multi do |transaction|
            transaction.call("INCR", tries_key)
            transaction.call("EXPIRE", tries_key, TRIES_WINDOW.to_i, "NX")
          end
        end.first
      end

      def forget_tries
        Sidekiq.redis { |redis| redis.call("DEL", tries_key) }
      end

      def tries_key
        "superadmin_2fa_tries:#{@user.id}"
      end

      # Whoever got here has this superadmin's password: worth a report, so
      # the password gets changed.
      def lock_out
        Rails.logger.warn("Superadmin #{@user.id}: two-factor locked after #{MAX_TRIES} wrong codes")
        Sentry.capture_message("Superadmin two-factor lockout", level: :warning, extra: { user_id: @user.id })
        restart(helpers.ngt("auth.too_many_attempts"))
      end

      def render_code(error = nil, status: :ok)
        @error = error
        # A step of a sign-in: never kept by a cache or the back button's copy.
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
