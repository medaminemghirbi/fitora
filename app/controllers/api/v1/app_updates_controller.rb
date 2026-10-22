module Api
  module V1
    # The admin's read-only view of the platform changelog — same data as
    # Superadmin::AppUpdatesController, minus the ability to publish. Reached from
    # the "system_update" notification's deep link (/admin/updates).
    class AppUpdatesController < BaseController
      before_action :require_admin!

      # GET /api/v1/app_updates
      def index
        updates = AppUpdate.includes(:created_by, media_attachments: :blob).recent.limit(AppUpdate::LIST_LIMIT)
        render json: { app_updates: updates.map { |u| AppUpdateSerializer.new(u).as_json } }
      end
    end
  end
end
