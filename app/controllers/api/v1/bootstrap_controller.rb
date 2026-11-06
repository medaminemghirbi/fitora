module Api
  module V1
    # One call the web/mobile clients make right after login (and on a hard
    # reload) to hydrate everything the shell needs: the user, their company,
    # branding and the resolved permission list. Replaces separate /auth/me +
    # /branding round-trips. The payload itself is SessionBootstrap, which the
    # server-rendered web UI reads too.
    class BootstrapController < BaseController
      # An unconfirmed address or an unfinished first sign-in does not stop it:
      # the shell hydrates, finds out, and routes to the right screen. Every
      # feature endpoint stays shut by the two checks themselves.
      skip_before_action :require_confirmed_email!
      skip_before_action :require_first_sign_in!

      def show
        render json: SessionBootstrap.new(current_user, current_company).as_json
      end
    end
  end
end
