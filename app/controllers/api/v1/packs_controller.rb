module Api
  module V1
    class PacksController < BaseController
      before_action :require_company!
      # Same split as the formules: reading the packs is part of signing a
      # member up (:contracts); building them is configuration.
      before_action -> { require_capability!(:contracts) }, only: [ :index ]
      before_action -> { require_capability!(:contract_types) }, only: [ :create, :update, :destroy ]
      before_action :require_packs_enabled!, only: [ :create, :update, :destroy ]
      before_action :set_pack, only: [ :update, :destroy ]

      # GET /api/v1/packs — empty, not 404, for a company that has packs
      # turned off: the sale form asks on every gym and simply offers none.
      def index
        return render(json: { packs: [] }) unless current_company.feature?(:packs)

        render json: { packs: CatalogueListing.packs(current_company).map { |p| PackSerializer.new(p).as_json } }
      end

      # POST /api/v1/packs
      def create
        pack = current_company.packs.new
        save_pack(pack, status: :created)
      end

      # PATCH /api/v1/packs/:id
      def update
        save_pack(@pack)
      end

      # DELETE /api/v1/packs/:id — soft, like an activity: contracts sold
      # with this pack keep pointing at it.
      def destroy
        @pack.update!(active: false)
        render json: { pack: PackSerializer.new(@pack).as_json }
      end

      private

      def set_pack
        @pack = current_company.packs.find(params[:id])
      end

      # CatalogueEditor.save_pack, shared with the web UI's catalogue.
      def save_pack(pack, status: :ok)
        activity_ids = params.key?(:activity_ids) ? Array(params[:activity_ids]) : nil
        pack = CatalogueEditor.save_pack(pack, current_company, pack_params, activity_ids: activity_ids)
        render json: { pack: PackSerializer.new(pack).as_json }, status: status
      end

      def pack_params
        params.require(:pack).permit(:name, :description, :active)
      end

      # Building packs is something a company opts into (CompanySettings
      # FEATURES[:packs]). 404 like rooms: absent, not forbidden.
      def require_packs_enabled!
        return if current_company.feature?(:packs)

        render json: { error: "Packs are not enabled for this gym" }, status: :not_found
      end
    end
  end
end
