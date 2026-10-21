module Api
  module V1
    # A member accepting the invitation their gym sent — unauthenticated by
    # design, like PasswordResetsController: the emailed token is the proof.
    class InvitationsController < ApplicationController
      # PATCH /api/v1/invitations/:token — { password: }
      def update
        client = AccountRecovery.accept_invitation(params[:token], params[:password])
        return render(json: { error: "invalid_or_expired_token" }, status: :unprocessable_content) if client == :invalid_token

        client.errors.empty? ? head(:no_content) : render_errors(client)
      end
    end
  end
end
