module Web
  module Superadmin
    # The gyms (SuperadminCompaniesComponent) and one gym's account
    # (SuperadminCompanyDetailComponent): what GET /api/v1/superadmin/companies
    # and …/:id answer, and the writes SuperadminActions makes — the plan, the
    # access, the billing period, the currency and language, invoices, and
    # stepping inside the account (the impersonation, in the session).
    class CompaniesController < BaseController
      before_action :set_company, except: :index

      helper_method :list_locals

      # GET /superadmin/companies?q=&closed=1&page= — ?fragment=1 for the
      # page without the shell, as the search, the closed filter and the
      # pages redraw it.
      def index
        @query = params[:q].to_s
        @closed = ActiveModel::Type::Boolean.new.cast(params[:closed]) || false
        companies = Company.includes(admin: [ :companies, { subscription: :invoices } ]).search(@query.presence)
        closed = companies.joins(admin: :subscription).where(subscriptions: { active: false })
        rows, @meta = page_meta((@closed ? closed : companies).reorder(:name))
        @companies = JSON.parse(rows.map { |c| SuperadminCompanySerializer.new(c).as_json }.to_json).map(&:deep_symbolize_keys)
        @closed_count = closed.count
        render :index, layout: false if params[:fragment].present?
      end

      # GET /superadmin/companies/:id — ?tab=gym for the gym's tab, kept in
      # the URL (M-05).
      def show
        @data = JSON.parse({
          company: SuperadminCompanySerializer.new(@company).as_json,
          currency_options: CurrencyCatalog.options,
          locale_options: Company::LOCALES,
          invoices: (@company.subscription&.invoices&.paid || Invoice.none).newest_first.map { |i| InvoiceSerializer.new(i).as_json }
        }.to_json).deep_symbolize_keys
        @tab = params[:tab] == "gym" ? "gym" : "billing"
      end

      def update_subscription
        attrs = params.permit(:active, :billing_period, :plan).to_h.symbolize_keys
        attrs[:active] = ActiveModel::Type::Boolean.new.cast(attrs[:active]) if attrs.key?(:active)
        attrs[:billing_period] = attrs[:billing_period].presence if attrs.key?(:billing_period)
        attrs[:plan] = attrs[:plan].presence if attrs.key?(:plan)
        subscription = SuperadminActions.update_subscription(@company, attrs, by: current_user)
        return render_refusal(I18n.with_locale(:en) { subscription.errors.full_messages }) if subscription.errors.any?

        # The page's toast, shown as it reloads (#toggleAccess, #changePlan,
        # #changeBillingPeriod).
        flash[:success] = helpers.ngt(
          if attrs.key?(:active) then subscription.active? ? "superadmin.access_restored" : "superadmin.access_suspended"
          elsif attrs.key?(:plan) then "superadmin.plan_changed"
          else "common.saved"
          end
        )
        head :no_content
      end

      def update_settings
        attrs = params.require(:company).permit(:currency, :locale)
        return render_refusal(I18n.with_locale(:en) { @company.errors.full_messages }) unless SuperadminActions.update_settings(@company, attrs, by: current_user)

        flash[:success] = helpers.ngt("common.saved")
        head :no_content
      end

      # Stepping inside the gym's admin account: the session becomes the
      # admin's for an hour, the superadmin's own kept to come back to
      # (AuthService#startImpersonation), and the admin's dashboard opens.
      def impersonate
        admin = SuperadminActions.impersonate(@company, by: current_user)
        return render_refusal("This company has no admin account") if admin.nil?

        start_impersonation(admin, company_name: @company.name)
        render json: { next: served_path("/admin/#{admin.current_company&.id || @company.id}/dashboard") }
      end

      def create_invoice
        invoice = SuperadminActions.issue_invoice(@company, by: current_user, notes: params[:notes])
        flash[:success] = helpers.ngt("superadmin.invoice_issued", number: invoice.number)
        head :created
      rescue ApplicationRecord::Refused => e
        render_refusal(e.message)
      end

      def destroy_invoice
        SuperadminActions.void_invoice(@company, params[:invoice_id], by: current_user)
        head :no_content
      rescue ActiveRecord::RecordNotFound
        render_refusal("Resource not found", status: :not_found)
      end

      private

      def set_company
        @company = Company.find_by(id: params[:id])
        return if @company

        request.format.html? ? render(:missing) : render_refusal("Resource not found", status: :not_found)
      end

      def list_locals
        { companies: @companies, meta: @meta, query: @query }
      end
    end
  end
end
