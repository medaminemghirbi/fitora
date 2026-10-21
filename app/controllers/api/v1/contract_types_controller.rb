module Api
  module V1
    class ContractTypesController < BaseController
      before_action :require_company!
      # Reading the plan list is part of signing a member up (:contracts);
      # editing the catalogue — prices, session counts — is configuration.
      before_action -> { require_capability!(:contracts) }, only: [ :index, :show ]
      before_action -> { require_capability!(:contract_types) }, only: [ :create, :update ]
      before_action :set_plan, only: [ :show, :update ]

      # GET /api/v1/contract_types
      def index
        render json: { plans: CatalogueListing.plans(current_company).map { |p| ContractTypeSerializer.new(p).as_json } }
      end

      # GET /api/v1/contract_types/:id
      def show
        render json: { plan: ContractTypeSerializer.new(@plan).as_json }
      end

      # POST /api/v1/contract_types
      def create
        plan = current_company.contract_types.new(plan_params)

        if plan.save
          sync_associations(plan)
          render json: { plan: ContractTypeSerializer.new(plan).as_json }, status: :created
        else
          render_errors(plan)
        end
      end

      # PATCH /api/v1/contract_types/:id
      def update
        if @plan.update(plan_params)
          sync_associations(@plan)
          render json: { plan: ContractTypeSerializer.new(@plan).as_json }
        else
          render_errors(@plan)
        end
      end

      private

      def set_plan
        @plan = current_company.contract_types.find(params[:id])
      end

      # The pricing grid (CatalogueEditor, shared with the web UI's
      # catalogue): a list that is absent is left alone.
      def sync_associations(plan)
        CatalogueEditor.price_plan(
          plan, current_company,
          activity_prices: params.key?(:activity_prices) ? Array(params[:activity_prices]) : nil,
          pack_prices: params.key?(:pack_prices) ? Array(params[:pack_prices]) : nil
        )
      end

      # Optional, so the pricing grid can send a formule's prices alone. A
      # create without it still fails, on the name.
      def plan_params
        params.fetch(:contract_type, {}).permit(
          :name, :description, :billing_period, :validity_days, :session_count,
          :unlimited_bookings, :booking_limit, :priority_booking, :active, :color
        )
      end
    end
  end
end
