module Web
  module Admin
    # The gym's rooms (SpacesComponent): only for a gym that turned rooms on
    # (featureGuard), and only for whoever may manage them (capabilityGuard).
    # Saved and removed by RoomEditor, as /api/v1/spaces does it.
    class SpacesController < BaseController
      before_action :require_spaces_feature
      before_action -> { require_capability(:spaces) }
      before_action :set_space, only: %i[update destroy]

      def index
        @spaces = current_company.spaces.search(nil).ordered.includes(:activities).map { |s| SpaceSerializer.new(s).as_json }
        @activities = CatalogueListing.activities(current_company).select(&:active).map { |a| ActivitySerializer.new(a).as_json }
        # The tool alone, as the onboarding page embeds it, for it to reload
        # itself after a save (SpacesComponent#load) without the page.
        return unless params[:fragment].present?

        render partial: "web/admin/spaces/tool", locals: { spaces: @spaces, activities: @activities, embedded: true }
      end

      # POST / PATCH from the page's form (JSON): ok, or the API's message.
      def create
        save(current_company.spaces.new)
      end

      def update
        save(@space)
      end

      def destroy
        RoomEditor.remove(@space)
        flash[:success] = helpers.ngt("common.saved")
        head :no_content
      end

      private

      def save(space)
        attributes = params.require(:space).permit(:name, :kind, :capacity).to_h
        if RoomEditor.save(space, attributes, activity_ids: Array(params[:space][:activity_ids]))
          flash[:success] = helpers.ngt("common.saved")
          head :no_content
        else
          render json: { error: I18n.with_locale(:en) { space.errors.full_messages.first } }, status: :unprocessable_content
        end
      end

      def set_space
        @space = current_company.spaces.find(params[:id])
      end

      # featureGuard("spaces"): a gym without rooms has no rooms page.
      def require_spaces_feature
        go_home unless current_company.feature?(:spaces)
      end
    end
  end
end
