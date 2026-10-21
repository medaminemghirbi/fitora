module Web
  module Admin
    # First-time setup as a flow (OnboardingComponent): the steps, and the
    # one being asked for with its tool inline — the catalogue's activities
    # and formules tools, the rooms tool — or a link to the page that does
    # it. The admin's alone (roleGuard("admin")); progress is written by
    # OnboardingProgress, as /api/v1/onboarding writes it.
    class OnboardingController < BaseController
      include Web::CatalogueData

      before_action :require_admin, only: :show
      before_action :refuse_unless_admin, except: :show
      before_action :load_step, only: %i[complete skip]

      helper_method :onboarding, :embedded_spaces

      def show; end

      # The company step: the one nothing in the database can confirm.
      def complete
        OnboardingProgress.complete!(current_company, @step)
        head :no_content
      end

      def skip
        OnboardingProgress.skip!(current_company, @step)
        head :no_content
      rescue OnboardingProgress::NotSkippable => e
        render json: { error: e.message }, status: :unprocessable_content
      end

      def dismiss
        OnboardingProgress.dismiss!(current_company)
        head :no_content
      end

      private

      def onboarding
        @onboarding ||= current_company.onboarding_state.as_json
      end

      # The rooms tool's data, as the rooms page reads it.
      def embedded_spaces
        @embedded_spaces ||= {
          spaces: current_company.spaces.search(nil).ordered.includes(:activities).map { |s| SpaceSerializer.new(s).as_json },
          activities: CatalogueListing.activities(current_company).select(&:active).map { |a| ActivitySerializer.new(a).as_json }
        }
      end

      def load_step
        @step = OnboardingStep.find(params[:step])
        render json: { error: "Unknown step" }, status: :unprocessable_content if @step.nil?
      end

      def refuse_unless_admin
        render json: { error: "You are not allowed to perform this action" }, status: :forbidden unless current_user.admin?
      end
    end
  end
end
