module Web
  # ChangePasswordComponent's two requests, for whoever is signed in (the
  # admin's settings, the member's profile) — as PATCH /api/v1/auth/password
  # and POST /api/v1/auth/logout { all_devices: true } answer them.
  module PasswordEndpoints
    # PATCH …/password: the new password ends every other session; this one
    # carries on. Helping inside someone's account never extends to it.
    def update_password
      return render(json: { error: "You are not allowed to perform this action" }, status: :forbidden) if current_impersonator

      account = current_user || current_client
      unless account.authenticate(params[:current_password].to_s)
        return render json: { error: "current_password_invalid", errors: [ "Current password is incorrect" ] }, status: :unprocessable_content
      end
      if params[:password].blank?
        return render json: { error: "Password can't be blank", errors: [ "Password can't be blank" ] }, status: :unprocessable_content
      end
      unless account.update(password: params[:password])
        messages = I18n.with_locale(:en) { account.errors.full_messages }
        return render json: { error: messages.first || "Validation failed", errors: messages }, status: :unprocessable_content
      end

      claims = session[Web::Authentication::SESSION_KEY]
      session[Web::Authentication::SESSION_KEY] = claims.merge("tv" => account.reload.token_version, "exp" => session_lifetime(account).from_now.to_i)
      head :no_content
    end

    # POST …/sign-out-everywhere: every session ends, this one too.
    def sign_out_everywhere
      (current_user || current_client).revoke_all_tokens!
      sign_out
      render json: { next: web_sign_in_path }
    end
  end
end
