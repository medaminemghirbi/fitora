module Api
  module V1
    module Superadmin
      # The platform changelog a superadmin edits after each release — version,
      # what's new, screenshots/screen-recordings. Publishing one notifies
      # every other superadmin AND every admin in real time (NotificationChannel)
      # — the team knows the update went out, and every customer sees what's
      # new (Api::V1::AppUpdatesController is their read-only, non-superadmin view).
      class AppUpdatesController < BaseController
        before_action :require_superadmin!

        # GET /api/v1/superadmin/app_updates
        def index
          updates = AppUpdate.includes(:created_by, media_attachments: :blob).recent
          render json: { app_updates: updates.map { |u| AppUpdateSerializer.new(u).as_json } }
        end

        # POST /api/v1/superadmin/app_updates (multipart/form-data — media[] are uploads)
        def create
          update = ReleaseNotes.publish(update_params, media: params[:media], by: current_user)
          if update.persisted?
            render json: { app_update: AppUpdateSerializer.new(update).as_json }, status: :created
          else
            render_errors(update)
          end
        end

        private

        def update_params
          params.require(:app_update).permit(:version, :title, :description)
        end
      end
    end
  end
end
