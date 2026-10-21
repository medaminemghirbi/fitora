module Web
  # The form both emailed links lead to (ResetPasswordComponent): a reset,
  # or a member's invitation — the same form, its own words and endpoint.
  module NewPasswordForm
    extend ActiveSupport::Concern

    COPY = {
      reset: {
        title: "auth.reset_password_title", subtitle: "auth.reset_password_hint", label: "auth.reset_password_submit",
        done_title: "auth.reset_password_done_title", done_body: "auth.reset_password_done_body",
        invalid: "auth.reset_password_invalid_link",
        panel_title_1: "auth.reset_panel_title_1", panel_title_2: "auth.reset_panel_title_2", panel_lead: "auth.reset_panel_lead"
      },
      invitation: {
        title: "auth.invitation_title", subtitle: "auth.invitation_hint", label: "auth.invitation_submit",
        done_title: "auth.invitation_done_title", done_body: "auth.invitation_done_body",
        invalid: "auth.invitation_invalid_link",
        panel_title_1: "auth.invitation_panel_title_1", panel_title_2: "auth.invitation_panel_title_2", panel_lead: "auth.invitation_panel_lead"
      }
    }.freeze

    private

    def new_password_form(mode, error: nil, status: :ok)
      @copy = COPY.fetch(mode)
      @token = params[:token].to_s
      # No token in the link: the form says so before anything is typed.
      @error = error || (@token.empty? ? helpers.ngt(@copy[:invalid]) : nil)
      render "web/password_resets/edit", status: status
    end

    # The form's own checks (8 characters, both the same), then the link's.
    def choose_password(mode)
      @copy = COPY.fetch(mode)
      @token = params[:token].to_s
      password = params[:password].to_s
      if @token.empty? || password.length < 8 || password != params[:password_confirmation].to_s
        @error = helpers.ngt(@copy[:invalid]) if @token.empty?
        return render("web/password_resets/edit", status: :unprocessable_content)
      end

      record = yield(@token, password)
      if record == :invalid_token
        @error = helpers.ngt(@copy[:invalid])
      elsif record.errors.any?
        # Real backend text, shown as the Angular page shows it (K-04).
        @error = I18n.with_locale(:en) { record.errors.full_messages.first }
      else
        @done = true
        return render("web/password_resets/edit")
      end
      render "web/password_resets/edit", status: :unprocessable_content
    end
  end
end
