module Web
  module Admin
    # Settings (SettingsShellComponent): the section in the URL, under the
    # tab row and the "Outils Pro" menu — and each section's writes, through
    # the rules the API applies to the same thing (/company, /roles,
    # /mobile_app, /data_exchange, /auth/password, /auth/logout), behind the
    # same guards, answered with the API's messages (K-04).
    class SettingsController < BaseController
      include Web::PasswordEndpoints

      before_action :settings_access!, only: :show
      before_action :refuse_unless_admin, only: %i[update_company create_role update_role destroy_role regenerate_key]
      before_action :refuse_without_pro, only: %i[create_role update_role destroy_role regenerate_key data_template export_data import_data show_import]
      before_action :set_strategy, only: %i[data_template export_data import_data]
      # Exporting all of an entity is a bulk copy of the gym's data: the admin's.
      # A block, not `before_action :refuse_unless_admin` again: Rails keeps one
      # callback per method name, so a second one replaces the first and left
      # the writes above open to every staff login.
      before_action -> { refuse_unless_admin }, only: :export_data

      rescue_from ActiveRecord::RecordNotFound, with: -> { render json: { error: "Resource not found" }, status: :not_found }
      rescue_from ActionController::ParameterMissing, with: ->(missing) { render json: { error: missing.message }, status: :bad_request }

      helper_method :sections, :section

      # GET …/settings(/:section) — an unknown or missing section is the
      # first one, the URL replaced (the shell's router.navigate with
      # replaceUrl).
      def show
        return redirect_to(admin_page_path("settings/#{sections.flat.first.path}")) if section.nil?

        @company = CompanySerializer.new(current_company).as_json if %w[company branding contracts planning booking].include?(section.path)
        case section.path
        when "roles" then @roles = roles_json if pro_access?
        when "mobile-app" then @keys = MobileAppKeys.as_json(current_company) if pro_access?
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

      # ---- import / export (/api/v1/data_exchange) ---------------------------------
      # The files are named as DataExchangeComponent names its downloads.

      def data_template
        send_data @strategy.template_csv, filename: "fitora-#{params[:entity]}-modele.csv", type: "text/csv"
      end

      def export_data
        send_data @strategy.export_csv(current_company), filename: "fitora-#{params[:entity]}-export.csv", type: "text/csv"
      end

      def import_data
        import = current_company.data_imports.new(entity: params[:entity], user: current_user)
        import.file.attach(params[:file]) if params[:file].present?
        return render_errors(import) unless import.save

        DataImportJob.perform_later(import.id)
        render json: import_json(import), status: :accepted
      end

      def show_import
        import = current_company.data_imports.find(params[:id])
        return refuse unless capability?(import.entity)

        render json: import_json(import)
      end

      private

      def sections
        @sections ||= Web::SettingsSections.new(user: current_user, permissions: bootstrap[:permissions])
      end

      def section
        @section ||= sections.find(params[:section].to_s)
      end

      # settingsAccessGuard: the admin, or a login that may manage
      # activities or plans; anyone else goes home.
      def settings_access!
        go_home unless current_user.admin? || capability?(:activities) || capability?(:contract_types)
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

      def set_strategy
        @strategy = DataExchange::REGISTRY[params[:entity]]
        return render(json: { error: "Unknown entity: #{params[:entity]}" }, status: :not_found) unless @strategy

        refuse unless capability?(params[:entity])
      end

      def import_json(import)
        {
          id: import.id, entity: import.entity, status: import.status, finished: import.finished?,
          created: import.created_count, errors: import.row_errors, message: import.message
        }
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

      def refuse_without_pro
        render json: { error: "pro_required", message: "This feature comes with Fitora Pro." }, status: :forbidden unless pro_access?
      end

      def render_errors(record_or_messages)
        messages = record_or_messages.respond_to?(:errors) ? I18n.with_locale(:en) { record_or_messages.errors.full_messages } : Array(record_or_messages)
        render json: { error: messages.first || "Validation failed", errors: messages }, status: :unprocessable_content
      end
    end
  end
end
