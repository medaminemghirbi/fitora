module Web
  module Desk
    # The desk's salle switcher (DeskShellComponent#switchSalle): the choice
    # recorded as POST /api/v1/companies/:id/switch records it (Pro only,
    # one of this login's own salles), then a full load of home there.
    class SallesController < BaseController
      def switch
        return render(json: { error: "pro_required", message: "This feature comes with Fitora Pro." }, status: :forbidden) unless pro_access?

        target = salle_for(current_user, params[:id])
        return render(json: { error: "Resource not found" }, status: :not_found) if target.nil?

        current_user.switch_active_company!(target)
        current_user.active_company_id = target.id
        @current_company = @current_staff_member = nil
        render json: { next: served_path(home_path) }
      end
    end
  end
end
