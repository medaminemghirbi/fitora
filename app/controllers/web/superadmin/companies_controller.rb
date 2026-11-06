module Web
  module Superadmin
    # The gyms (SuperadminCompaniesComponent), one gym's account
    # (SuperadminCompanyDetailComponent), opening a new one, and the writes
    # SuperadminActions makes — the credentials, the access, the currency and
    # language, and stepping inside the account (the impersonation, in the
    # session).
    class CompaniesController < BaseController
      before_action :set_company, except: %i[index new create]

      # The gyms table: by the gym's name and city or its admin's name and
      # e-mail; where the account stands as a filter.
      TABLE = Web::DataTable::Definition.new(
        search: :name_or_city_or_admin_first_name_or_admin_last_name_or_admin_email_cont,
        sorts: { name: "name", admin: %w[admin_last_name admin_first_name], created: "created_at" },
        default: %w[created desc],
        filters: {
          activation: {
            "pending" => { admin_must_change_password_eq: true, admin_access_suspended_at_null: true },
            "active" => { admin_must_change_password_eq: false, admin_access_suspended_at_null: true },
            "suspended" => { admin_access_suspended_at_not_null: true }
          }
        }
      )

      # What a new gym starts on, before anyone changes it.
      NEW_COMPANY_DEFAULTS = { timezone: Company::DEFAULT_TIMEZONE, currency: "TND", locale: "fr" }.freeze

      # GET /superadmin/companies?search=&activation=&sort=&dir=&page=&limit=
      # — the table alone when its frame asks.
      def index
        @table = TABLE.table(params)
        @pagy, @companies = paginate(@table, Company.includes(admin: :companies))
      end

      def new
        @company_values = NEW_COMPANY_DEFAULTS
        @admin_values = {}
        @errors = {}
      end

      # POST /superadmin/companies — the account, then its page, which says
      # whether the credentials left.
      def create
        @company_values = company_params.to_h.symbolize_keys
        @admin_values = admin_params.to_h.symbolize_keys
        @errors = missing_fields
        return render(:new, status: :unprocessable_content) if @errors.any?

        opened = SuperadminActions.create_company(company_params, admin_params, by: current_user)
        flash[opened.credentials_sent ? :success : :warning] =
          helpers.ngt(opened.credentials_sent ? "superadmin.create.created" : "superadmin.create.created_not_sent", email: opened.company.admin.email)
        redirect_to "/superadmin/companies/#{opened.company.id}", status: :see_other
      rescue ActiveRecord::RecordInvalid => e
        @errors = record_errors(e.record)
        render :new, status: :unprocessable_content
      end

      # GET /superadmin/companies/:id — the account on one page.
      def show
        @data = JSON.parse({
          company: SuperadminCompanySerializer.new(@company).as_json,
          currency_options: CurrencyCatalog.options,
          locale_options: Company::LOCALES
        }.to_json).deep_symbolize_keys
      end

      def update_settings
        attrs = params.require(:company).permit(:currency, :locale)
        return render_refusal(I18n.with_locale(:en) { @company.errors.full_messages }) unless SuperadminActions.update_settings(@company, attrs, by: current_user)

        flash[:success] = helpers.ngt("common.saved")
        head :no_content
      end

      # POST /superadmin/companies/:id/credentials — a new password, sent again.
      def send_credentials
        unless SuperadminActions.send_credentials(@company, by: current_user)
          return render_refusal(helpers.ngt("superadmin.credentials.not_sent"), status: :bad_gateway)
        end

        flash[:success] = helpers.ngt("superadmin.credentials.sent", email: @company.admin.email)
        head :no_content
      rescue ApplicationRecord::Refused => e
        render_refusal(e.message)
      end

      # POST /superadmin/companies/:id/suspend, …/restore — the account's access.
      def suspend
        SuperadminActions.suspend_access(@company, by: current_user)
        flash[:success] = helpers.ngt("superadmin.access.suspended", name: @company.name)
        head :no_content
      end

      def restore
        SuperadminActions.restore_access(@company, by: current_user)
        flash[:success] = helpers.ngt("superadmin.access.restored", name: @company.name)
        head :no_content
      end

      # Stepping inside the gym's admin account: the session becomes the
      # admin's for an hour, the superadmin's own kept to come back to
      # (AuthService#startImpersonation), and the admin's dashboard opens.
      def impersonate
        admin = SuperadminActions.impersonate(@company, by: current_user)
        return render_refusal("This company has no admin account") if admin.nil?

        start_impersonation(admin, company_name: @company.name)
        render json: { next: "/admin/#{admin.current_company&.id || @company.id}/dashboard" }
      end

      private

      def set_company
        @company = Company.find_by(id: params[:id])
        return if @company

        request.format.html? ? render(:missing) : render_refusal("Resource not found", status: :not_found)
      end

      def company_params
        params.fetch(:company, {}).permit(:name, :city, :address, :phone, :timezone, :currency, :locale)
      end

      def admin_params
        params.fetch(:admin, {}).permit(:first_name, :last_name, :email, :phone)
      end

      # The form's checks, all at once, before either model is asked.
      def missing_fields
        errors = {}
        errors[:name] = helpers.ngt("common.required") if @company_values[:name].blank?
        %i[first_name last_name].each { |field| errors[field] = helpers.ngt("common.required") if @admin_values[field].blank? }
        email = @admin_values[:email].to_s.strip
        errors[:email] = helpers.ngt(email.empty? ? "common.required" : "auth.email_invalid") unless email.match?(Web::SessionsController::EMAIL_FORMAT)
        errors
      end

      # What a model still refuses: the address already known above all, in the
      # page's language; anything else in the models' words.
      def record_errors(record)
        record.errors.attribute_names.index_with do |attribute|
          next helpers.ngt("clients.email_taken") if attribute == :email && record.errors.of_kind?(:email, :taken)

          I18n.with_locale(:en) { record.errors.full_messages_for(attribute).first }
        end
      end
    end
  end
end
