module Api
  module V1
    class AuthController < ApplicationController
      before_action :authenticate_request!, only: [ :me, :logout, :permissions, :change_password, :cable_ticket ]

      # POST /api/v1/auth/login — one door for both kinds of account.
      #
      # A platform account first (admin, staff, Fitora superadmin), then a member
      # whose gym enabled their access. account_type says which came back, so
      # the caller sends them to the right home without asking who they are
      # first. Nobody signs up here: a superadmin opens a gym's account
      # (SuperadminActions.create_company), and a member's access is switched on
      # from their own file by the gym.
      def login
        result = SignIn.call(params[:email], params[:password])

        if result.user
          render json: { token: JwtService.for_user(result.user), account_type: "user", user: UserSerializer.new(result.user).as_json }
        elsif result.client
          render json: { token: JwtService.for_client(result.client), account_type: "client", client: ClientSerializer.new(result.client, reveal: true).as_json }
        elsif result.error == :access_suspended
          render json: { error: "access_suspended", message: "This gym's access to Fitora is suspended. Contact Fitora." }, status: :forbidden
        elsif result.error == :no_gym
          render json: { error: "no_gym", message: "You do not belong to a gym on Fitora." }, status: :forbidden
        else
          render json: { error: "Invalid email or password" }, status: :unauthorized
        end
      end

      # POST /api/v1/auth/logout — { all_devices: true } to sign out everywhere.
      #
      # A plain logout ends this token, a copy of it too: its id is kept as
      # signed out until it would have expired (RevokedSessions). Every
      # device at once moves the account's token_version on, which ends
      # every token issued before it (see TokenVersioned).
      def logout
        RevokedSessions.revoke!(@token_claims[:jti], @token_claims[:expires_at])
        current_account.revoke_all_tokens! if ActiveModel::Type::Boolean.new.cast(params[:all_devices])
        head :no_content
      end

      # PATCH /api/v1/auth/password — { current_password:, password: }
      #
      # For someone already signed in. The new password ends every other
      # session (TokenVersioned); this one gets a fresh token back so the
      # person changing it is not signed out in the same breath.
      def change_password
        # Helping inside someone's account never extends to their password.
        return render_forbidden if current_impersonator

        account = current_account
        unless account.authenticate(params[:current_password].to_s)
          return render json: { error: "current_password_invalid", errors: [ "Current password is incorrect" ] },
                        status: :unprocessable_content
        end

        if params[:password].blank?
          return render json: { error: "Password can't be blank", errors: [ "Password can't be blank" ] },
                        status: :unprocessable_content
        end

        if account.update(password: params[:password])
          token = account.is_a?(Client) ? JwtService.for_client(account) : JwtService.for_user(account)
          render json: { token: token }
        else
          render_errors(account)
        end
      end

      # POST /api/v1/cable_ticket
      #
      # Browsers cannot set headers on a WebSocket handshake, so whatever
      # authenticates /cable rides in its URL — where proxy and access logs
      # keep it. That used to be the 7-day login token. This is a pass that
      # expires in 30 seconds and opens one connection.
      def cable_ticket
        render json: { ticket: JwtService.cable_ticket_for(current_account) }
      end

      # GET /api/v1/auth/me
      def me
        if current_client
          render json: { account_type: "client", client: ClientSerializer.new(current_client, reveal: true).as_json }
        else
          render json: { account_type: "user", user: UserSerializer.new(current_user).as_json }
        end
      end

      # GET /api/v1/me/permissions — the resolved capability list for the
      # signed-in staff login, plus the role it came from. The frontend
      # renders navigation and guards page access from this rather than a
      # hard-coded map. Admins get every permission; a platform superadmin gets
      # none (the /superadmin surface isn't capability-gated).
      def permissions
        # A member's login has no staff role to resolve.
        return render_forbidden unless current_user

        render json: { role: current_user.role_summary, permissions: current_user.permission_keys }
      end

      private

      def current_account
        current_client || current_user
      end
    end
  end
end
