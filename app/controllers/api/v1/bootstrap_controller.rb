module Api
  module V1
    # One call the web/mobile clients make right after login (and on a hard
    # reload) to hydrate everything the shell needs: the user, their company,
    # branding, the resolved permission list, the enabled modules, and the
    # subscription banner state. Replaces separate /auth/me + /branding +
    # /subscription round-trips. The payload itself is SessionBootstrap,
    # which the server-rendered web UI reads too.
    class BootstrapController < BaseController
      # A locked company can still bootstrap — the client needs the payload to
      # render the "trial expired" screen. Individual feature endpoints stay
      # locked by enforce_trial_lock!.
      skip_before_action :enforce_trial_lock!
      # Nor does an unconfirmed address stop it: the shell hydrates, finds
      # user.email_verified false, and routes to the "check your inbox"
      # screen. Every feature endpoint stays shut by require_confirmed_email!.
      skip_before_action :require_confirmed_email!

      def show
        render json: SessionBootstrap.new(current_user, current_company).as_json
      end
    end
  end
end
