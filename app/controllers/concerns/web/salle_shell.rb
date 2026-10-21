module Web
  # A shell whose pages belong to one salle (admin, desk, coach): the salle
  # is in the URL (MIGRATION_AUDIT §8), so each browser tab keeps its own.
  #
  # The salle is looked up among this login's own workplaces only, and
  # applied for this request only, in memory, exactly as the API applies the
  # X-Company-Id header (§8.2). One that is not theirs gets the API's
  # company_not_accessible answer as the Angular app takes it: nothing shown,
  # and home in the saved salle.
  module SalleShell
    extend ActiveSupport::Concern

    included do
      helper_method :salle
    end

    private

    # authGuard: no session, sign in. A member's session belongs to the
    # other half of the product: their own home (staff.guard's elsewhereFor).
    def require_staff_session!
      return render(json: { error: "Unauthorized" }, status: :unauthorized) if !signed_in? && request.format.json?
      return sign_in_first unless signed_in?

      go_home if current_client
    end

    def enter_salle!
      company = salle_for(current_user, params[:salle_id])
      return go_home if company.nil?

      current_user.active_company_id = company.id
      @current_company = nil
      @current_staff_member = nil
      @salle = company
    end

    def salle
      @salle
    end

    # The gym's local time is the salle the URL names, which is only known
    # once the session is (Web::BaseController picks the zone first, before
    # #enter_salle! runs).
    def in_gym_time_zone(&action)
      named = signed_in? && current_user && salle_for(current_user, params[:salle_id])
      Time.use_zone((named || current_company)&.time_zone || Time.zone, &action)
    end
  end
end
