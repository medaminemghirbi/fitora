module Web
  module Admin
    # Settings: the section in the URL, beside the settings' own menu — and
    # each section's writes, through
    # the rules the API applies to the same thing (/company, /roles,
    # /mobile_app, /auth/password, /auth/logout), behind the
    # same guards, answered with the API's messages (K-04).
    class SettingsController < BaseController
      include Web::PasswordEndpoints
      include Web::SettingsPage

      before_action :settings_access!, only: :show
      before_action :refuse_unless_admin, only: %i[update_company create_role update_role destroy_role regenerate_key]

      rescue_from ActiveRecord::RecordNotFound, with: -> { render json: { error: "Resource not found" }, status: :not_found }
      rescue_from ActionController::ParameterMissing, with: ->(missing) { render json: { error: missing.message }, status: :bad_request }

      helper_method :section

      # GET …/settings(/:section) — an unknown or missing section is the
      # first one, the URL replaced (the shell's router.navigate with
      # replaceUrl).
      def show
        return redirect_to(admin_page_path(sections.flat.first.target)) if section.nil?
        return redirect_to(admin_page_path(section.target)) if section.page

        @company = CompanySerializer.new(current_company).as_json if %w[company legal branding contracts planning booking].include?(section.path)
        case section.path
        when "roles" then @roles = roles_json
        when "mobile-app" then @keys = MobileAppKeys.as_json(current_company)
        end
        # The matrix alone, as load() redraws it after a save.
        render partial: "web/admin/settings/roles", locals: { data: @roles } if params[:fragment].present? && @roles
      end

      # PATCH …/settings/company — the profile, the hours, the booking rules
      # and the branding (multipart, with the logo and the signature), as
      # PATCH /api/v1/company.
      def update_company
        if CompanyProfile.update(current_company, params)
          render json: { company: CompanySerializer.new(current_company).as_json }
        else
          render_errors(current_company)
        end
      end

      # ---- roles (/api/v1/roles) -------------------------------------------------

      def create_role
        role = current_company.roles.new(role_params.merge(builtin: false))
        return render_errors(role) unless role.save

        render json: { role: RoleSerializer.new(role).as_json }, status: :created
      end

      def update_role
        role = current_company.roles.find(params[:id])
        return render(json: { error: "The Admin role cannot be edited." }, status: :unprocessable_content) if role.key == "admin"
        return render_errors(role) unless role.update(role_params)

        render json: { role: RoleSerializer.new(role).as_json }
      end

      def destroy_role
        role = current_company.roles.find(params[:id])
        unless role.deletable?
          reason = role.builtin? ? "A built-in role cannot be deleted." : "Staff accounts still use this role."
          return render json: { error: reason }, status: :unprocessable_content
        end

        role.destroy
        head :no_content
      end

      # ---- the mobile app's keys (/api/v1/mobile_app) -------------------------------

      def regenerate_key
        audience = params[:audience].to_s
        return render_errors([ "Unknown audience" ]) unless MobileAppKeys::AUDIENCES.include?(audience)

        MobileAppKeys.regenerate!(current_company, audience: audience, by: current_user)
        render json: MobileAppKeys.as_json(current_company)
      end

      private

      def section
        @section ||= sections.find(params[:section].to_s)
      end

      def current_settings_path
        section&.path
      end

      # The admin, or a login that may manage something here (activities,
      # plans, the plateau); anyone else goes home.
      def settings_access!
        go_home unless current_user.admin? || capability?(:activities) || capability?(:contract_types) || capability?(:spaces)
      end

      def roles_json
        {
          roles: current_company.roles.ordered.includes(:staff_members).map { |r| RoleSerializer.new(r).as_json },
          permission_catalog: Permission::CATALOG
        }
      end

      def role_params
        params.require(:role).permit(:name, permissions: [])
      end

      # The session's claims follow the account's new token_version: the
      # API answers a password change with a fresh token for the device that
      # made it.
      def refuse
        render json: { error: "You are not allowed to perform this action" }, status: :forbidden
      end

      def refuse_unless_admin
        refuse unless current_user.admin?
      end

      def render_errors(record_or_messages)
        messages = record_or_messages.respond_to?(:errors) ? I18n.with_locale(:en) { record_or_messages.errors.full_messages } : Array(record_or_messages)
        render json: { error: messages.first || "Validation failed", errors: messages }, status: :unprocessable_content
      end
    end
  end
end
