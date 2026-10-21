module Web
  # The web UI's sign-in: an encrypted session cookie carrying what the API's
  # JWT carries, checked the way ApplicationController#authenticate_request!
  # checks a token (MIGRATION_AUDIT §9.1):
  #
  # - the account must still exist and be active;
  # - its token_version must not have moved on — "sign out everywhere" and a
  #   password change end web sessions and JWTs alike;
  # - the session expires 7 days after sign-in (1 hour when impersonating),
  #   like JwtService::EXPIRATION, whatever the cookie itself says;
  # - an impersonation whose superadmin is gone, or no longer a superadmin,
  #   is over.
  module Authentication
    extend ActiveSupport::Concern

    SESSION_KEY = :fitora
    STASH_KEY = :fitora_impersonator

    included do
      helper_method :current_user, :current_client, :current_impersonator, :signed_in?, :impersonated_company_name
    end

    private

    def current_user
      load_session_account
      @current_user
    end

    def current_client
      load_session_account
      @current_client
    end

    def current_impersonator
      load_session_account
      @current_impersonator
    end

    def signed_in?
      current_user.present? || current_client.present?
    end

    # `expires_at`: a session carried over from an Angular token keeps that
    # token's own end (Web::HandoffsController#exchange), never a fresh 7 days.
    def sign_in(account, impersonator: nil, expires_at: nil)
      reset_session # never carry a pre-sign-in session id across the door
      lifetime = impersonator ? JwtService::IMPERSONATION_EXPIRATION : JwtService::EXPIRATION
      session[SESSION_KEY] = {
        "kind" => account.is_a?(Client) ? "client" : "user",
        "id" => account.id,
        "tv" => account.token_version,
        "exp" => (expires_at || lifetime.from_now).to_i
      }
      session[SESSION_KEY]["imp"] = impersonator.id if impersonator
      @session_loaded = false
    end

    def sign_out
      reset_session
      # The shell's banner choices belong to the session that made them.
      cookies.delete(:fitora_email_banner)
      @session_loaded = false
    end

    # A superadmin working inside a gym's admin account (AuthService
    # #startImpersonation): the admin's session for an hour, marked with
    # who is really there, with the superadmin's own session kept aside to
    # come back to — as the Angular app stashes the superadmin's token.
    def start_impersonation(admin, company_name:)
      own = session[SESSION_KEY].dup
      sign_in(admin, impersonator: current_impersonator || current_user)
      session[STASH_KEY] = own.merge("company_name" => company_name)
    end

    # AuthService#exitImpersonation: back to the superadmin's own session,
    # if it still stands; signed out otherwise.
    def exit_impersonation
      own = session[STASH_KEY]
      sign_out
      return if own.blank?

      # Checked like any session on its next read (#load_session_account).
      session[SESSION_KEY] = own.except("company_name")
      @session_loaded = false
    end

    # The impersonated gym's name, for the shell's banner.
    def impersonated_company_name
      current_impersonator && session.dig(STASH_KEY, "company_name")
    end

    def load_session_account
      return if @session_loaded

      @session_loaded = true
      @current_user = @current_client = @current_impersonator = nil
      claims = session[SESSION_KEY]
      return if claims.blank?

      found = Web::SessionAccount.resolve(claims)
      return sign_out if found.account.nil?

      @current_user, @current_client, @current_impersonator = found.user, found.client, found.impersonator
      Current.impersonator = @current_impersonator if @current_impersonator
    end
  end
end
