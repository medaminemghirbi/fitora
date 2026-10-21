module Web
  module Admin
    # "Nouveautés" (AdminUpdatesComponent): the release notes Fitora
    # publishes, as GET /api/v1/app_updates lists them.
    class UpdatesController < BaseController
      before_action :require_admin

      def index
        @updates = AppUpdate.recent.includes(:created_by, media_attachments: :blob).map { |u| AppUpdateSerializer.new(u).as_json }
      end
    end
  end
end
