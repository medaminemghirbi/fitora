module Web
  module Admin
    # The members page (ClientsListComponent) and its new-member wizard.
    #
    # The list is Clients::ListQuery and the sale Clients::Enrolment — the
    # very objects GET and POST /api/v1/clients use — and every row is what
    # ClientSerializer says about it (masked e-mail and all), so the page
    # cannot show a member differently from the Angular one.
    class ClientsController < BaseController
      before_action -> { require_capability(:clients) }

      PER_PAGE = 20 # Api::V1::BaseController#page_params' default

      # GET /admin/<salle>/clients[.csv]?search=&status=&…&page=
      #
      # As HTML, the whole page. As a Turbo Stream (what the page asks for
      # when a filter changes), only the regions that depend on the results,
      # so the search box keeps its focus as it does in Angular.
      def index
        @list = Clients::ListQuery.new(current_company, params)

        respond_to do |format|
          format.html { load_page }
          format.turbo_stream { load_page }
          format.csv { export }
        end
      end

      # POST /admin/<salle>/clients — the wizard's last step.
      def create
        # Selling a plan is the `contracts` capability's, as on the API.
        return render_wizard_error(helpers.ngt("common.error_generic")) if subscription_params.present? && !capability?(:contracts)

        result = Clients::Enrolment.call(
          company: current_company, user: current_user,
          person: person_params, membership: membership_params, subscription: subscription_params
        )
        flash[:success] = helpers.ngt("clients.created")
        redirect_to admin_page_path("clients/#{result.client.id}"), status: :see_other
      rescue ApplicationRecord::Refused => refusal
        render_wizard_error(refusal_message(refusal))
      rescue ActiveRecord::RecordInvalid => invalid
        # The API's English messages, as the Angular wizard shows them (K-04).
        render_wizard_error(I18n.with_locale(:en) { invalid.record.errors.full_messages.first })
      end

      private

      def load_page
        @page = [ params[:page].to_i, 1 ].max
        scope = @list.scope
        rows = scope.limit(PER_PAGE).offset((@page - 1) * PER_PAGE).to_a
        visits = @list.last_visits_for(rows)
        context = ClientSerializer.page_context(rows, current_company)
        @clients = rows.map do |c|
          ClientSerializer.new(
            c, company: current_company, last_visit_at: visits[c.id],
            membership: context[:memberships][c.id], current_contract: context[:current_contracts][c.id]
          ).as_json
        end
        total = scope.count
        @meta = { page: @page, per_page: PER_PAGE, total: total, total_pages: (total.to_f / PER_PAGE).ceil }
        @counts = @list.counts
        @filters = @list.params
        @catalogue = catalogue
      end

      # The whole member file leaving the building: admin only — and named as
      # the Angular app names the download.
      def export
        return go_home unless current_user.admin?

        send_data @list.csv, filename: "adherents-#{Date.current.iso8601}.csv", type: "text/csv"
      end

      # The wizard's and the filters' lists: the active activities and plans,
      # as the Angular page keeps them (`.filter(a => a.active)`).
      def catalogue
        {
          activities: CatalogueListing.activities(current_company).select(&:active).map { |a| ActivitySerializer.new(a).as_json },
          plans: CatalogueListing.plans(current_company).select(&:active).map { |p| ContractTypeSerializer.new(p).as_json },
          currency_symbol: Web::Currency.symbol(bootstrap.dig(:branding, :currency) || "TND")
        }
      end

      def render_wizard_error(message)
        render turbo_stream: turbo_stream.replace("cl-wizard-error", partial: "web/admin/clients/wizard_error", locals: { message: message }),
               status: :unprocessable_content
      end

      def subscription_params
        return {} if params[:subscription].blank?

        params.require(:subscription).permit(
          :contract_type_id, :activity_id, :pack_id, :starts_on, :discount,
          :collect_payment, :payment_method
        ).to_h
      end

      def client_params
        params.require(:client).permit(
          :first_name, :last_name, :email, :phone, :date_of_birth, :gender,
          :emergency_contact_name, :emergency_contact_phone, :notes
        )
      end

      def membership_params
        client_params.slice(:notes, *Membership::PROFILE_FIELDS).to_h.symbolize_keys
      end

      def person_params
        client_params.slice(*Client::IDENTITY_FIELDS)
      end
    end
  end
end
