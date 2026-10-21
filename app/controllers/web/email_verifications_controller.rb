module Web
  # Where the emailed confirmation link lands (VerifyEmailComponent). The
  # page renders "checking…" and its controller spends the token with a
  # PATCH, as the Angular page does from the browser — so a mail scanner
  # that opens the link, and runs no script, never uses it up.
  class EmailVerificationsController < BaseController
    layout "web/auth"

    def show
      @authenticated = signed_in?
    end

    # PATCH /verify-email { token } → { status:, continue_url: }
    def update
      record = AccountRecovery.verify_email(params[:token].to_s)
      # Confirming spends the token, so a second click on the same link is
      # refused; for someone signed in whose address is in fact confirmed,
      # that is not a failure (failUnlessAlreadyConfirmed).
      account = current_user || current_client
      success = record.present? || (account.present? && account.reload.email_verified?)
      render json: { status: success ? "success" : "error", continue_url: continue_url }
    end

    private

    # VerifyEmailComponent#continueUrl.
    def continue_url
      return "/connexion" unless signed_in?

      user = current_user
      user&.reload
      path = if user&.admin? && user.current_company.nil? && user.email_verified?
        "/admin/setup-company"
      else
        home_path
      end
      served_path(path)
    end

    def rate_limited
      render json: { status: "error", continue_url: "/connexion" }, status: :too_many_requests
    end
  end
end
