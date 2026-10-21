module Web
  module Member
    # The member's own file and account (MemberProfileComponent): the
    # subscription they train on and their attendance at the gym shown (GET
    # /api/v1/me/profile), their name and phone (PATCH /me/profile), their
    # password (Web::PasswordEndpoints), leaving Fitora (DELETE /me/account);
    # and which gym the app shows (MemberShellComponent#switchGym).
    class ProfileController < BaseController
      include Web::PasswordEndpoints

      def show
        @profile = gym && JSON.parse(MemberApp.profile(current_client, gym, member_companies).to_json).deep_symbolize_keys
      end

      def update
        current_client.update!(params.require(:client).permit(:first_name, :last_name, :phone))
        render json: { client: MemberApp.identity(current_client) }
      rescue ActiveRecord::RecordInvalid => e
        render_refusal(I18n.with_locale(:en) { e.record.errors.full_messages })
      end

      # Leaving Fitora: confirmed by password; their gyms keep their books,
      # nothing on them names this person any more (Client#anonymise!), and
      # every session ends — then the sign-in page, with the toast.
      def destroy
        unless current_client.authenticate(params[:password].to_s)
          return render json: { error: "password_invalid", errors: [ "Password is incorrect" ] }, status: :unprocessable_content
        end

        current_client.anonymise!
        sign_out
        flash[:success] = helpers.ngt("account.deleted")
        render json: { next: "/connexion" }
      end

      # The gym the app shows: one of theirs, remembered; then the same page
      # in it.
      def switch_gym
        cookies.permanent[GYM_COOKIE] = { value: params[:id], same_site: :lax } if member_companies.any? { |c| c.id == params[:id] }
        redirect_back fallback_location: web_member_home_path, status: :see_other
      end
    end
  end
end
