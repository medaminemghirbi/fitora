module Web
  # The crossings between a Rails shell and an Angular one while some shells
  # are still Angular's (MIGRATION_AUDIT §9.3). No shell is ever mixed, so a
  # crossing is always a full page load from one shell to another — after
  # sign-in, a coach sent to their day, a superadmin impersonating a gym,
  # signing out — and these carry the session across it:
  #
  # - Rails → Angular (#show): the Angular app's own session storage,
  #   written the way AuthService#setSession writes it, then the Angular
  #   route. The cookie session stays, so coming back needs nothing.
  # - Angular → Rails (#exchange): the Angular token, checked exactly as the
  #   API checks it, becomes the cookie session (Web::BaseController
  #   #sign_in_first renders the page that posts it).
  # - Signing out (#signed_out): the Angular app's keys removed too, so its
  #   guards do not send the person straight back in.
  #
  # Once every shell is served here, none of this is reached.
  class HandoffsController < BaseController
    # The Angular app's keys (auth.service.ts, active-company.ts,
    # member.service.ts, locale.service.ts, theme.service.ts).
    ANGULAR_KEYS = %w[fitora_token fitora_user_v2 fitora_client fitora_impersonator_v2].freeze

    # The Angular app has no CSRF token to send, and ending a session is
    # the one thing a forged request could do here.
    skip_forgery_protection only: :destroy

    # GET /session/handoff?to=
    def show
      to = local_path(params[:to])
      return redirect_to(to) if Web::Routing.served?(to)

      path, salle = Web::Routing.angular(to)
      render layout: false, locals: { path: path, salle: salle, storage: signed_in? ? angular_storage : nil }
    end

    # POST /session/exchange { token, impersonator_token, company_name, locale, theme, member_gym, to }
    def exchange
      claims = JwtService.decode(params[:token].to_s)
      account = account_for(claims)
      return signed_out_page if account.nil?

      impersonator = claims[:impersonator_id] && User.active.superadmin.find_by(id: claims[:impersonator_id])
      return signed_out_page if claims[:impersonator_id] && impersonator.nil?

      sign_in(account, impersonator: impersonator, expires_at: claims[:expires_at])
      keep_stash(impersonator) if impersonator
      remember_locale(params[:locale])
      cookies.permanent[THEME_COOKIE] = { value: params[:theme], same_site: :lax } if %w[light dark].include?(params[:theme])
      cookies.permanent[Web::Member::BaseController::GYM_COOKIE] = { value: params[:member_gym], same_site: :lax } if params[:member_gym].present?
      redirect_to local_path(params[:to]), status: :see_other
    rescue JwtService::DecodeError
      signed_out_page
    end

    # DELETE /session — the Angular app's logout ends the cookie session too.
    def destroy
      sign_out
      head :no_content
    end

    private

    # The account a token names, if it still stands: active, at its current
    # token_version (ApplicationController#authenticate_request!).
    def account_for(claims)
      account = claims[:client_id] ? Client.active.find_by(id: claims[:client_id]) : User.active.find_by(id: claims[:user_id])
      account&.token_current?(claims[:token_version]) ? account : nil
    end

    # The superadmin's own session, from the token the Angular app stashed
    # for them, to come back to at the end of the impersonation.
    def keep_stash(impersonator)
      claims = JwtService.decode(params[:impersonator_token].to_s)
      return unless claims[:user_id] == impersonator.id && impersonator.token_current?(claims[:token_version])

      session[STASH_KEY] = { "kind" => "user", "id" => impersonator.id, "tv" => impersonator.token_version,
                             "exp" => claims[:expires_at].to_i, "company_name" => params[:company_name].to_s }
    rescue JwtService::DecodeError
      nil
    end

    def signed_out_page
      sign_out
      render "web/handoffs/signed_out", layout: false, locals: { to: "/connexion" }
    end

    # What AuthService#setSession leaves in storage for this session, with
    # tokens that end when the cookie session does.
    def angular_storage
      claims = session[SESSION_KEY]
      remaining = [ claims["exp"].to_i - Time.current.to_i, 0 ].max.seconds
      storage = { "fitora_locale" => locale_code, "fitora_theme" => theme }

      if current_client
        token = JwtService.encode(client_id: current_client.id, token_version: current_client.token_version, expires_in: remaining)
        storage.merge!("fitora_token" => token, "fitora_client" => ClientSerializer.new(current_client, reveal: true).as_json.to_json,
                       "fitora_user_v2" => nil, "fitora_impersonator_v2" => nil)
        storage["fitora_member_gym"] = cookies[Web::Member::BaseController::GYM_COOKIE] if cookies[Web::Member::BaseController::GYM_COOKIE].present?
      else
        token = JwtService.encode(current_user.id, impersonator_id: current_impersonator&.id,
                                                   token_version: current_user.token_version, expires_in: remaining)
        storage.merge!("fitora_token" => token, "fitora_user_v2" => UserSerializer.new(current_user).as_json.to_json,
                       "fitora_client" => nil, "fitora_impersonator_v2" => impersonator_stash)
      end
      storage
    end

    def impersonator_stash
      own = session[STASH_KEY]
      return nil if current_impersonator.nil? || own.blank?

      remaining = [ own["exp"].to_i - Time.current.to_i, 0 ].max.seconds
      token = JwtService.encode(current_impersonator.id, token_version: current_impersonator.token_version, expires_in: remaining)
      { token: token, user: UserSerializer.new(current_impersonator).as_json, companyName: own["company_name"] }.to_json
    end

    # Only a path on this site: never an open redirect.
    def local_path(path)
      path = path.to_s
      path.start_with?("/") && !path.start_with?("//") ? path : "/connexion"
    end
  end
end
