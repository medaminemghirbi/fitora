module Web
  module Admin
    # What the gym sells (CatalogueComponent): the price grid, the
    # activities, the formules and the packs, one tab each (?tab=). Every
    # tab is rendered here, searched and paged here; each write goes through
    # the rules /api/v1/activities, /api/v1/contract_types and /api/v1/packs
    # apply (CatalogueEditor), behind the same capabilities, and answers with
    # the API's refusal message.
    class CatalogueController < BaseController
      include Web::CatalogueData

      TABS = %w[tarifs activites formules packs].freeze
      # DEFAULT_PAGE_SIZE (shared/utils/client-list.ts).
      PER_PAGE = 25

      before_action -> { require_capability(:contract_types) }, only: :show
      before_action -> { refuse_without(:activities) }, only: %i[create_activity update_activity deactivate_activity adopt]
      before_action -> { refuse_without(:contract_types) }, only: %i[create_plan update_plan create_pack update_pack deactivate_pack]
      before_action :refuse_without_packs, only: %i[create_pack update_pack deactivate_pack]

      # The API's messages are English whatever the page's language (K-04).
      rescue_from ActiveRecord::RecordInvalid, with: ->(invalid) { render_errors(invalid.record) }
      rescue_from ApplicationRecord::Refused, with: ->(refusal) { refuse(refusal.message) }
      rescue_from ActiveRecord::RecordNotFound, with: -> { render json: { error: "Resource not found" }, status: :not_found }

      helper_method :tab

      # GET …/catalogue?tab=&q=&page= — the page; with ?fragment=1, only the
      # tabs and the tab's panel, which the catalogue controller merges in
      # after a search, a page or a save (keeping the search box and any
      # open dialog where they are).
      def show
        return render(:fragment, layout: false) if params[:fragment].present?

        @open = request.query_parameters["action"] == "new" ? tab : nil
      end

      # ---- activities (/api/v1/activities) --------------------------------

      def create_activity
        activity = current_company.activities.new(activity_params)
        return render_errors(activity) unless activity.save

        render json: { activity: ActivitySerializer.new(activity).as_json }, status: :created
      end

      def update_activity
        activity = current_company.activities.find(params[:id])
        return render_errors(activity) unless activity.update(activity_params)

        render json: { activity: ActivitySerializer.new(activity).as_json }
      end

      # Soft: contracts and sessions keep pointing at it.
      def deactivate_activity
        activity = current_company.activities.find(params[:id])
        activity.update!(active: false)
        render json: { activity: ActivitySerializer.new(activity).as_json }
      end

      def adopt
        created = current_company.adopt_activities!(template_ids: params[:activity_template_ids])
        render json: { activities: created.map { |a| ActivitySerializer.new(a).as_json } }, status: :created
      end

      # ---- formules (/api/v1/contract_types) --------------------------------

      def create_plan
        plan = current_company.contract_types.new(plan_params)
        return render_errors(plan) unless plan.save

        price(plan)
        render json: { plan: ContractTypeSerializer.new(plan.reload).as_json }, status: :created
      end

      def update_plan
        plan = current_company.contract_types.find(params[:id])
        return render_errors(plan) unless plan.update(plan_params)

        price(plan)
        render json: { plan: ContractTypeSerializer.new(plan.reload).as_json }
      end

      # ---- packs (/api/v1/packs) --------------------------------------------

      def create_pack
        pack = CatalogueEditor.save_pack(current_company.packs.new, current_company, pack_params, activity_ids: activity_ids)
        render json: { pack: PackSerializer.new(pack).as_json }, status: :created
      end

      def update_pack
        pack = current_company.packs.find(params[:id])
        pack = CatalogueEditor.save_pack(pack, current_company, pack_params, activity_ids: activity_ids)
        render json: { pack: PackSerializer.new(pack).as_json }
      end

      def deactivate_pack
        pack = current_company.packs.find(params[:id])
        pack.update!(active: false)
        render json: { pack: PackSerializer.new(pack).as_json }
      end

      private

      # asTab(): an unknown tab is the grid; packs only for a gym that has them.
      def tab
        requested = TABS.include?(params[:tab]) ? params[:tab] : "tarifs"
        requested == "packs" && !packs_enabled? ? "tarifs" : requested
      end

      def price(plan)
        CatalogueEditor.price_plan(plan, current_company, activity_prices: rows(:activity_prices, :activity_id), pack_prices: rows(:pack_prices, :pack_id))
      end

      # A list the request sends, or nil when it sends none (left alone).
      def rows(key, id_key)
        return nil unless params.key?(key)

        Array(params[key]).map { |row| row.permit(id_key, :price).to_h.with_indifferent_access }
      end

      def activity_ids
        params.key?(:activity_ids) ? Array(params[:activity_ids]) : nil
      end

      def activity_params
        params.require(:activity).permit(:name, :emoji, :description, :session_format, :duration, :capacity, :active)
      end

      def plan_params
        params.fetch(:contract_type, {}).permit(
          :name, :description, :billing_period, :validity_days, :session_count,
          :unlimited_bookings, :booking_limit, :priority_booking, :active, :color
        )
      end

      def pack_params
        params.require(:pack).permit(:name, :description, :active)
      end

      def refuse_without(capability)
        render json: { error: "You are not allowed to perform this action" }, status: :forbidden unless capability?(capability)
      end

      # 404 like the API: absent, not forbidden.
      def refuse_without_packs
        render json: { error: "Packs are not enabled for this gym" }, status: :not_found unless packs_enabled?
      end

      def render_errors(record)
        messages = I18n.with_locale(:en) { record.errors.full_messages }
        render json: { error: messages.first || "Validation failed", errors: messages }, status: :unprocessable_content
      end

      def refuse(message)
        render json: { error: message, errors: [ message ] }, status: :unprocessable_content
      end
    end
  end
end
