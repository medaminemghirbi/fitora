module Web
  # Opening the first salle (CompanySetupComponent): who the salle is, then
  # what it teaches, picked from the platform's catalogue or named by hand.
  # Guarded as the Angular route is — authGuard, roleGuard("admin"),
  # emailConfirmedGuard, noCompanyGuard — and opened by Company.open!, as
  # POST /api/v1/companies opens it.
  class CompanySetupsController < BaseController
    layout "web/auth"

    before_action :require_sign_in, only: :show
    before_action :require_admin_without_salle, only: :show
    before_action :refuse_unless_may_open, only: :create

    def show
      @templates = ActivityTemplate.active.catalogue_order.map { |t| ActivityTemplateSerializer.new(t).as_json }
    end

    # POST (JSON) — the salle, then where the page goes once its "getting
    # ready" moment has run: the getting-started guide.
    def create
      company = Company.open!(admin: current_user, attributes: company_params,
                    activity_template_ids: params[:activity_template_ids],
                    custom_activities: params.fetch(:custom_activities, []).map { |entry| entry.permit(:name, :emoji) })
      render json: { next: served_path("/admin/#{company.id}/getting-started") }, status: :created
    rescue ActiveRecord::RecordInvalid => e
      render json: { error: I18n.with_locale(:en) { e.record.errors.full_messages.first } || "Validation failed" }, status: :unprocessable_content
    rescue ApplicationRecord::Refused => e
      render json: { error: e.message }, status: :unprocessable_content
    end

    private

    def require_sign_in
      sign_in_first unless signed_in?
    end

    # roleGuard("admin"), emailConfirmedGuard, noCompanyGuard: anyone else,
    # or an admin who already has a salle, goes home.
    def require_admin_without_salle
      return go_home unless current_user&.admin?
      return go_home if email_confirmation_required?

      go_home if current_user.current_company.present?
    end

    # The API's refusals: not signed in, not an admin, or a second salle on
    # an account that does not include several.
    def refuse_unless_may_open
      return render(json: { error: "Unauthorized" }, status: :unauthorized) unless signed_in? && current_user
      return render(json: { error: "You are not allowed to perform this action" }, status: :forbidden) unless current_user.admin?
      return if current_user.may_open_salle?

      render json: { error: "multi_salle_not_included", message: "Several salles come with Fitora Pro." }, status: :forbidden
    end

    def company_params
      params.require(:company).permit(:name, :description, :phone, :email, :country, :city, :address, :timezone, :currency)
    end
  end
end
