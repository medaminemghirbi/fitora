module Web
  module Admin
    # The salle's subscriptions: the desk's work lists (Contracts::ListQuery)
    # and everything it does to one — sell, renew, collect, edit, pause,
    # resume, cancel — through Contracts::Actions and Payments::Actions, the
    # rules /api/v1/contracts and /api/v1/payments apply, behind the same
    # capabilities. The dialogs are the subscriptions controller's, shared
    # with the member's file; a refusal answers in the page's language.
    class ContractsController < BaseController
      PER_PAGE = 20

      # The lists, as the tabs show them: [status, label, tone, shown when
      # empty]. The work comes first; the lists that are usually empty only
      # show while they hold something (or are the one open).
      LISTS = [
        [ "", "contracts.list_all", "neutral", true ],
        [ "active", "contracts.list_active", "success", true ],
        [ "expiring", "contracts.list_expiring", "warning", true ],
        [ "expired", "contracts.list_expired", "danger", true ],
        [ "unpaid", "contracts.list_unpaid", "danger", true ],
        [ "upcoming", "contracts.list_upcoming", "info", false ],
        [ "paused", "contracts.list_paused", "info", false ],
        [ "cancelled", "contracts.list_cancelled", "neutral", false ]
      ].freeze

      before_action -> { require_capability(:contracts) }, only: :index
      before_action :refuse_without_contracts, except: :index
      before_action :refuse_collect_without_payments, only: %i[create renew collect]
      before_action :set_contract, except: %i[index create members]

      rescue_from ApplicationRecord::Refused, with: ->(refusal) { render json: { error: refusal_message(refusal) }, status: :unprocessable_content }
      rescue_from Contracts::Actions::NotFound, with: ->(missing) { render json: { error: missing.message }, status: :not_found }
      rescue_from ActiveRecord::RecordInvalid, with: ->(invalid) { render json: { error: invalid.record.errors.full_messages.first }, status: :unprocessable_content }
      rescue_from Date::Error, with: -> { render json: { error: page_words("contracts.errors.invalid_date") }, status: :unprocessable_content }

      helper_method :currency

      def index
        list = Contracts::ListQuery.new(current_company, params.permit(*Contracts::ListQuery::FILTERS).to_h, revenue: capability?(:revenue))
        @filters = list.params
        @page = [ params[:page].to_i, 1 ].max
        scope = list.scope
        @contracts = scope.limit(PER_PAGE).offset((@page - 1) * PER_PAGE).map { |m| ContractSerializer.new(m).as_json }
        total = scope.count
        @meta = { page: @page, per_page: PER_PAGE, total: total, total_pages: (total.to_f / PER_PAGE).ceil }
        @counts = list.counts
        @plan_counts = list.plan_counts
        @totals = list.totals
        @plans = CatalogueListing.plans(current_company).map { |p| { id: p.id, name: p.name, color: p.color, active: p.active } }
        respond_to do |format|
          format.html
          format.turbo_stream
        end
      end

      # The sale dialog's member search: who they are, and what they already
      # hold, so the dialog can say when a sale would overlap it.
      def members
        clients = Clients::ListQuery.new(current_company, { search: params[:search] }).scope.limit(PER_PAGE).to_a
        held = current_company.contracts.currently_active.where(client_id: clients.map(&:id))
                              .includes(:contract_type, :activity, :pack).group_by(&:client_id)
        render json: {
          members: clients.map { |c| helpers.subscription_member(c, held.fetch(c.id, [])) }
        }
      end

      # "Vendre un abonnement": the offer picked, from the day picked, paid
      # now or later.
      def create
        client = current_company.clients.find_by(id: params[:client_id])
        return render(json: { error: page_words("contracts.errors.member_not_found") }, status: :not_found) if client.nil?

        Contracts::Actions.sell(client, company: current_company, by: current_user,
                                        params: sale_params.merge(payment_method: Contracts::Actions.payment_method(params)))
        head :created
      end

      # "Modifier": the dates, and the discount while unpaid.
      def update
        Contracts::Actions.update(@contract, company: current_company, by: current_user, params: params.permit(:starts_on, :expires_on, :discount))
        head :no_content
      end

      def renew
        Contracts::Actions.renew(@contract, company: current_company, by: current_user, params: sale_params)
        head :no_content
      end

      def pause
        Contracts::Actions.pause(@contract, company: current_company, by: current_user)
        head :no_content
      end

      def resume
        Contracts::Actions.resume(@contract, company: current_company, by: current_user)
        head :no_content
      end

      # "Résilier".
      def cancel
        Contracts::Actions.cancel(@contract, company: current_company, by: current_user)
        head :no_content
      end

      # "Encaisser": the whole amount, by the method the desk picked.
      def collect
        Payments::Actions.record(
          @contract.client, company: current_company, by: current_user,
          params: { payment_method: Contracts::Actions.payment_method(params), contract_id: @contract.id }
        )
        head :no_content
      end

      # The documents, fetched by the page and saved as contrat-<ref>.pdf /
      # facture-<ref>.pdf.
      def agreement
        send_data Receipts::ContractAgreementPdf.call(contract: @contract), type: "application/pdf", disposition: "attachment",
                  filename: "contrat-#{@contract.invoice_ref}.pdf"
      end

      def receipt
        send_data Receipts::ContractPdf.call(contract: @contract), type: "application/pdf", disposition: "attachment",
                  filename: "facture-#{@contract.invoice_ref}.pdf"
      end

      private

      def sale_params
        params.permit(:contract_type_id, :activity_id, :pack_id, :starts_on, :discount, :collect_payment, :payment_method)
      end

      def refuse_without_contracts
        render json: { error: page_words("contracts.errors.not_allowed") }, status: :forbidden unless capability?(:contracts)
      end

      # Taking money is `payments`, whichever dialog asks for it.
      def refuse_collect_without_payments
        collecting = action_name == "collect" || ActiveModel::Type::Boolean.new.cast(params[:collect_payment])
        render json: { error: page_words("contracts.errors.not_allowed") }, status: :forbidden if collecting && !may_collect?
      end

      def set_contract
        @contract = current_company.contracts.find_by(id: params[:id])
        render json: { error: page_words("contracts.errors.not_found") }, status: :not_found if @contract.nil?
      end

      def currency
        bootstrap.dig(:branding, :currency) || "TND"
      end
    end
  end
end
