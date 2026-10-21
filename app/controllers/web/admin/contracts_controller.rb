module Web
  module Admin
    # The salle's contracts (ContractsComponent): listed by
    # Contracts::ListQuery; renewed, paused and resumed through
    # Contracts::Actions; settled in cash through Payments::Actions — the
    # same rules /api/v1/contracts and /api/v1/payments apply, with the same
    # capability checks and the same refusals.
    class ContractsController < BaseController
      PER_PAGE = 20

      before_action -> { require_capability(:contracts) }, only: :index
      before_action :refuse_without_contracts, except: :index
      before_action :set_contract, except: :index

      # Four colours across the whole app: green in order, orange worth
      # watching, red needs doing, grey no longer applies (statusOptions).
      STATUSES = [
        [ "", "clients.filter_all", "all", "var(--color-primary)" ],
        [ "active", "contract.status_active", "active", "var(--color-success)" ],
        [ "expiring", "contract.status_expiring", "expiring", "var(--color-warning)" ],
        [ "expired", "contract.status_expired", "expired", "var(--color-danger)" ],
        [ "pending", "contract.status_pending", "pending", "var(--color-info)" ],
        [ "paused", "contract.status_paused", "paused", "var(--color-info)" ],
        [ "cancelled", "contract.status_cancelled", "cancelled", "var(--color-muted)" ]
      ].freeze
      helper_method :contract_statuses, :currency

      def index
        list = Contracts::ListQuery.new(current_company, list_params, revenue: capability?(:revenue))
        @filters = list.params
        @page = [ params[:page].to_i, 1 ].max
        scope = list.scope
        @contracts = scope.limit(PER_PAGE).offset((@page - 1) * PER_PAGE).map { |m| ContractSerializer.new(m).as_json }
        total = scope.count
        @meta = { page: @page, per_page: PER_PAGE, total: total, total_pages: (total.to_f / PER_PAGE).ceil }
        @counts = list.counts
        @plan_counts = list.plan_counts
        @totals = list.totals
        # Every plan, as ContractTypesService#list returns them: the tabs and
        # the formules a renewal can move onto.
        @plans = CatalogueListing.plans(current_company).map { |p| ContractTypeSerializer.new(p).as_json }
        respond_to do |format|
          format.html
          format.turbo_stream
        end
      end

      def renew
        Contracts::Actions.renew(@contract, company: current_company, by: current_user, params: params)
        head :no_content
      rescue Contracts::Actions::NotFound => e
        render json: { error: e.message }, status: :not_found
      rescue ApplicationRecord::Refused => e
        render json: { error: e.message }, status: :unprocessable_content
      end

      def pause
        Contracts::Actions.pause(@contract, company: current_company, by: current_user)
        head :no_content
      rescue ApplicationRecord::Refused => e
        render json: { error: e.message }, status: :unprocessable_content
      end

      def resume
        Contracts::Actions.resume(@contract, company: current_company, by: current_user)
        head :no_content
      rescue ApplicationRecord::Refused => e
        render json: { error: e.message }, status: :unprocessable_content
      end

      # The row's "Encaisser": the whole amount, in cash — what the Angular
      # page sends to POST /api/v1/payments, which asks `payments`.
      def collect
        return render(json: { error: "You are not allowed to perform this action" }, status: :forbidden) unless capability?(:payments)

        Payments::Actions.record(
          @contract.client, company: current_company, by: current_user,
          params: { payment_method: "cash", contract_id: @contract.id }
        )
        head :no_content
      rescue ApplicationRecord::Refused => e
        render json: { error: e.message }, status: :unprocessable_content
      rescue ActiveRecord::RecordInvalid => e
        render json: { error: e.record.errors.full_messages.first }, status: :unprocessable_content
      end

      # The documents, fetched by the page and saved under the Angular names
      # (contrat-<ref>.pdf / facture-<ref>.pdf).
      def agreement
        send_data Receipts::ContractAgreementPdf.call(contract: @contract), type: "application/pdf", disposition: "attachment",
                  filename: "contrat-#{@contract.invoice_ref}.pdf"
      end

      def receipt
        send_data Receipts::ContractPdf.call(contract: @contract), type: "application/pdf", disposition: "attachment",
                  filename: "facture-#{@contract.invoice_ref}.pdf"
      end

      private

      # The Angular page reads ?status= and ?payment= (unpaid or paid only)
      # from the URL; the plan and the search it keeps in the URL as the
      # other migrated lists do (MIGRATION_AUDIT M-05).
      def list_params
        filters = params.permit(*Contracts::ListQuery::FILTERS).to_h
        filters.delete("payment") unless %w[unpaid paid].include?(filters["payment"])
        filters
      end

      def refuse_without_contracts
        head :forbidden unless capability?(:contracts)
      end

      def set_contract
        @contract = current_company.contracts.find_by(id: params[:id])
        head :not_found if @contract.nil?
      end

      def contract_statuses
        STATUSES
      end

      def currency
        bootstrap.dig(:branding, :currency) || "TND"
      end
    end
  end
end
