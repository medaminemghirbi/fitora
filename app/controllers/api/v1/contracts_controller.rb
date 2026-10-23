module Api
  module V1
    class ContractsController < BaseController
      before_action :require_company!
      before_action -> { require_capability!(:contracts) }
      before_action :set_contract, only: [ :show, :update, :renew, :cancel, :pause, :resume, :destroy, :receipt, :agreement ]

      # GET /api/v1/contracts — the company's contracts, filterable by
      # status, payment and/or contract_type_id.
      #
      # status=expiring is not one of Contract's four states: it is "active,
      # and running out within the month", which is what the dashboard sends
      # people here to act on.
      def index
        # The rules are Contracts::ListQuery's, shared with the web UI's
        # contracts page.
        list = Contracts::ListQuery.new(current_company, params, revenue: capability?(:revenue))
        contracts = list.scope

        render json: {
          contracts: paginate(contracts).map { |m| ContractSerializer.new(m).as_json },
          meta: pagination_meta(contracts),
          counts: list.counts,
          plan_counts: list.plan_counts,
          totals: list.totals
        }
      end

      # GET /api/v1/contracts/:id
      def show
        render json: { contract: ContractSerializer.new(@contract).as_json }
      end

      # POST /api/v1/contracts — staff gives a client a contract
      def create
        client = current_company.clients.find_by(id: params[:client_id])
        return render(json: { error: "Client not found" }, status: :not_found) if client.nil?

        contract = Contracts::Actions.sell(client, company: current_company, by: current_user, params: params)
        render json: {
          contract: ContractSerializer.new(contract).as_json,
          payment: PaymentSerializer.new(contract.payments.first).as_json
        }, status: :created
      rescue Contracts::Actions::NotFound => e
        render json: { error: e.message }, status: :not_found
      end

      # PATCH /api/v1/contracts/:id — edit this term (dates, discount)
      def update
        Contracts::Actions.update(@contract, company: current_company, by: current_user, params: params)
        render json: { contract: ContractSerializer.new(@contract.reload).as_json }
      end

      # POST /api/v1/contracts/:id/renew — sells the next term, a new
      # contract linked to this one. Same formule unless contract_type_id
      # (and activity_id or pack_id) name another: renewing is when a member
      # moves to a different formule.
      def renew
        renewal = Contracts::Actions.renew(@contract, company: current_company, by: current_user, params: params)
        render json: { contract: ContractSerializer.new(renewal).as_json }, status: :created
      rescue Contracts::Actions::NotFound => e
        render json: { error: e.message }, status: :not_found
      end

      # POST /api/v1/contracts/:id/cancel
      def cancel
        Contracts::Actions.cancel(@contract, company: current_company, by: current_user)
        render json: { contract: ContractSerializer.new(@contract.reload).as_json }
      end

      # POST /api/v1/contracts/:id/pause — membership on hold (Contract#pause!)
      def pause
        Contracts::Actions.pause(@contract, company: current_company, by: current_user)
        render json: { contract: ContractSerializer.new(@contract.reload).as_json }
      end

      # POST /api/v1/contracts/:id/resume — end the hold, give the time back
      def resume
        Contracts::Actions.resume(@contract, company: current_company, by: current_user)
        render json: { contract: ContractSerializer.new(@contract.reload).as_json }
      end

      # DELETE /api/v1/contracts/:id — only once cancelled, so this is
      # never how history disappears by accident: cancel (soft, reversible
      # by re-subscribing) is the everyday action; destroy is a deliberate
      # second step for actually clearing clutter out of a client's history.
      def destroy
        unless @contract.cancelled?
          return render json: { error: "Only cancelled contracts can be deleted" }, status: :unprocessable_content
        end

        metadata = { client: @contract.client.full_name, plan: @contract.contract_type.name }
        @contract.destroy!
        AuditLog.record!(company: current_company, user: current_user, action: "contract.deleted", auditable: @contract, metadata: metadata)

        head :no_content
      end

      # GET /api/v1/contracts/:id/receipt — available to anyone who can
      # already see this contract (require_capability!(:contracts)).
      def receipt
        pdf_data = Receipts::ContractPdf.call(contract: @contract)

        send_data pdf_data,
                   filename: "facture-#{@contract.client.full_name.parameterize}-#{@contract.invoice_ref.downcase}.pdf",
                   type: "application/pdf",
                   disposition: "attachment"
      end

      # GET /api/v1/contracts/:id/agreement — the abonnement contract itself,
      # signed by the gym with its default signature (Settings), for the
      # member to sign in turn.
      def agreement
        pdf_data = Receipts::ContractAgreementPdf.call(contract: @contract)

        send_data pdf_data,
                  filename: "contrat-#{@contract.client.full_name.parameterize}-#{@contract.invoice_ref.downcase}.pdf",
                  type: "application/pdf",
                  disposition: "attachment"
      end

      private

      # Who is buying, which plan, for which activity — each this gym's own,
      # or a 404 naming which one was not found.
      def set_contract
        @contract = current_company.contracts.find(params[:id])
      end
    end
  end
end
