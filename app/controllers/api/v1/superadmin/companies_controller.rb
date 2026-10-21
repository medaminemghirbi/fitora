module Api
  module V1
    module Superadmin
      class CompaniesController < BaseController
        before_action :require_superadmin!
        before_action :set_company, only: [ :show, :update_subscription, :update_settings, :impersonate, :invoices, :create_invoice, :destroy_invoice ]

        # GET /api/v1/superadmin/companies?q=&closed=1
        #
        # `closed` narrows to the gyms whose access is shut. The count comes
        # back either way, so the list says how many without a screen of its
        # own — nobody should have to open a gym's page to find out. Access
        # is the account's, so every salle of a closed account is closed.
        def index
          companies = Company.includes(admin: [ :companies, { subscription: :invoices } ]).search(params[:q])
          closed = companies.joins(admin: :subscription).where(subscriptions: { active: false })

          only_closed = ActiveModel::Type::Boolean.new.cast(params[:closed])
          scope = (only_closed ? closed : companies).reorder(:name)

          render json: {
            companies: paginate(scope).map { |o| SuperadminCompanySerializer.new(o).as_json },
            meta: pagination_meta(scope),
            closed_count: closed.count
          }
        end

        # GET /api/v1/superadmin/companies/:id
        def show
          render json: {
            company: SuperadminCompanySerializer.new(@company).as_json,
            currency_options: CurrencyCatalog.options,
            locale_options: Company::LOCALES
          }
        end

        # PATCH /api/v1/superadmin/companies/:id/subscription — the ACCOUNT's
        # subscription, reached through any one of its salles
        # (SuperadminActions.update_subscription).
        def update_subscription
          attrs = {}
          attrs[:active] = ActiveModel::Type::Boolean.new.cast(params[:active]) if params.key?(:active)
          attrs[:billing_period] = params[:billing_period].presence if params.key?(:billing_period)
          attrs[:plan] = params[:plan].presence if params.key?(:plan)
          subscription = SuperadminActions.update_subscription(@company, attrs, by: current_user)

          if subscription.errors.empty?
            render json: { company: SuperadminCompanySerializer.new(@company.reload).as_json }
          else
            render_errors(subscription)
          end
        end

        # PATCH /api/v1/superadmin/companies/:id/settings — tenant-wide display
        # settings a Fitora superadmin controls on the company's behalf: the app
        # language and the billing/display currency. { company: { currency:,
        # locale: } }.
        def update_settings
          if SuperadminActions.update_settings(@company, company_settings_params, by: current_user)
            render json: { company: SuperadminCompanySerializer.new(@company).as_json }
          else
            render_errors(@company)
          end
        end

        # POST /api/v1/superadmin/companies/:id/impersonate — issues a real
        # login session for the company's admin, marked with this
        # superadmin's id so it's traceable, and reuses the entire admin-facing
        # app as-is instead of duplicating every page for superadmin use.
        def impersonate
          admin = SuperadminActions.impersonate(@company, by: current_user)
          return render json: { error: "This company has no admin account" }, status: :unprocessable_content if admin.nil?

          render json: { token: JwtService.for_user(admin, impersonator: current_user), user: UserSerializer.new(admin).as_json }
        end

        # GET /api/v1/superadmin/companies/:id/invoices — the account's.
        def invoices
          # What was paid; the bill still to pay is subscription.due_invoice.
          scope = @company.subscription&.invoices&.paid || Invoice.none
          render json: {
            invoices: scope.newest_first.map { |i| InvoiceSerializer.new(i).as_json }
          }
        end

        # POST /api/v1/superadmin/companies/:id/invoices — the money arrived
        # (SuperadminActions.issue_invoice).
        def create_invoice
          invoice = SuperadminActions.issue_invoice(@company, by: current_user, notes: params[:notes])
          render json: {
            invoice: InvoiceSerializer.new(invoice).as_json,
            company: SuperadminCompanySerializer.new(@company.reload).as_json
          }, status: :created
        end

        # DELETE /api/v1/superadmin/companies/:id/invoices/:invoice_id — an
        # invoice issued in error (SuperadminActions.void_invoice).
        def destroy_invoice
          SuperadminActions.void_invoice(@company, params[:invoice_id], by: current_user)
          render json: { company: SuperadminCompanySerializer.new(@company.reload).as_json }
        end

        private

        def set_company
          @company = Company.find(params[:id])
        end

        def company_settings_params
          params.require(:company).permit(:currency, :locale)
        end
      end
    end
  end
end
