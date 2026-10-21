module Web
  module Superadmin
    # The release notes (SuperadminUpdatesComponent): every update, with who
    # published it, and publishing one with its screenshots and recordings
    # (ReleaseNotes.publish, as POST /api/v1/superadmin/app_updates does).
    class UpdatesController < BaseController
      def index
        @updates = JSON.parse(AppUpdate.includes(:created_by, media_attachments: :blob).recent.map { |u| AppUpdateSerializer.new(u).as_json }.to_json).map(&:deep_symbolize_keys)
      end

      def create
        update = ReleaseNotes.publish(params.require(:app_update).permit(:version, :title, :description), media: params[:media], by: current_user)
        return render_refusal(I18n.with_locale(:en) { update.errors.full_messages }) unless update.persisted?

        flash[:success] = helpers.ngt("superadmin.updates.published")
        head :created
      end
    end
  end
end
