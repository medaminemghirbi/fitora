module Web
  module Superadmin
    # The release notes: every update, searched by version, title or
    # description, with who published it; one on its own page with its
    # screenshots and recordings; and publishing one (ReleaseNotes.publish,
    # as POST /api/v1/superadmin/app_updates does).
    class UpdatesController < BaseController
      TABLE = Web::DataTable::Definition.new(
        search: :version_or_title_or_description_cont,
        sorts: { published: "published_at", version: "version", title: "title" },
        default: %w[published desc]
      )

      def index
        @table = TABLE.table(params)
        @pagy, @updates = paginate(@table, AppUpdate.includes(:created_by, :media_attachments))
      end

      def show
        update = AppUpdate.includes(:created_by, media_attachments: :blob).find_by(id: params[:id])
        return redirect_to("/superadmin/updates", status: :see_other) if update.nil?

        @update = JSON.parse(AppUpdateSerializer.new(update).as_json.to_json).deep_symbolize_keys
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
