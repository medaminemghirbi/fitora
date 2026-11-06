module Web
  module Admin
    # "Mes salles" (SallesComponent) and moving the session onto another
    # salle (the navbar's switcher and this page), as /api/v1/companies does
    # both.
    class SallesController < BaseController
      include Web::SettingsPage
      settings_section "salles"

      before_action :require_admin, only: :network
      before_action :refuse_unless_admin, only: %i[create update_moderators]

      # GET …/salles — the page. With ?fragment=1, the cards and the moderator
      # lists only.
      def network
        @network = SalleNetwork.for(current_user, current_company)
        render partial: "web/admin/salles/network", locals: { network: @network } if params[:fragment].present?
      end

      # POST …/salles (JSON) — another salle on the same account, in the
      # active one's currency; it becomes the active one and opens on its
      # getting-started guide.
      def create
        company = Company.open!(admin: current_user, attributes: params.require(:company).permit(:name, :city, :phone, :timezone, :currency))
        render json: { next: "/admin/#{company.id}/onboarding" }, status: :created
      rescue ActiveRecord::RecordInvalid => e
        render json: { error: I18n.with_locale(:en) { e.record.errors.full_messages.first } || "Validation failed" }, status: :unprocessable_content
      rescue ApplicationRecord::Refused => e
        render json: { error: e.message }, status: :unprocessable_content
      end

      # PUT …/salles/:id/moderators — exactly who works at that salle
      # (Company#post_moderators!); answers with the redrawn network.
      def update_moderators
        company = current_user.companies.find_by(id: params[:id])
        return render(json: { error: "Resource not found" }, status: :not_found) if company.nil?

        company.post_moderators!(params[:user_ids], by: current_user)
        render partial: "web/admin/salles/network", formats: [ :html ], locals: { network: SalleNetwork.for(current_user, current_company) }
      rescue ApplicationRecord::Refused => e
        render json: { error: e.message }, status: :unprocessable_content
      end

      def switch
        target = salle_for(current_user, params[:id])
        return go_home if target.nil?

        current_user.switch_active_company!(target)
        # NavbarComponent#reloadToHome: an admin opens the new salle's
        # dashboard; a staff login's home depends on its role there.
        @current_company = nil
        @current_staff_member = nil
        current_user.active_company_id = target.id
        destination = current_user.admin? ? "/admin/#{target.id}/dashboard" : home_path
        # The salles page asks with fetch (to show "Bascule…" meanwhile),
        # then loads the destination itself.
        return render(json: { next: destination }) if request.format.json?

        redirect_to(destination, status: :see_other)
      end

      private

      def refuse_unless_admin
        render json: { error: "You are not allowed to perform this action" }, status: :forbidden unless current_user.admin?
      end
    end
  end
end
