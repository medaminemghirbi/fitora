module Web
  module Superadmin
    # Fitora's own console (/superadmin/…, SuperadminShellComponent):
    # authGuard, then roleGuard("superadmin"). Not salle-scoped
    # (MIGRATION_AUDIT §8.1): it is the one cross-tenant namespace, and reads
    # aggregates and accounts, never a gym's own records — the way into
    # those is impersonation, which is audited.
    class BaseController < Web::BaseController
      include Pagy::Method

      # A table redrawn in its frame (Web::DataTable) needs only the frame:
      # turbo-rails' bare layout, not the console around it.
      layout -> { turbo_frame_request? ? "turbo_rails/frame" : "web/superadmin" }

      before_action :require_superadmin_session!

      private

      # One page of a console table: Pagy's arithmetic over the rows the
      # table's search, filters and sort leave (Web::DataTable#apply). A page
      # past the last is the last, not an empty table under a total.
      def paginate(table, scope)
        rows = table.apply(scope)
        pagy, records = pagy(:offset, rows, limit: table.limit)
        pagy, records = pagy(:offset, rows, limit: table.limit, page: pagy.last, count: pagy.count) if pagy.page > pagy.last
        [ pagy, records ]
      end

      def require_superadmin_session!
        return render(json: { error: "Unauthorized" }, status: :unauthorized) if !signed_in? && request.format.json?
        return sign_in_first unless signed_in?

        go_home unless current_user&.superadmin?
      end

      # The console is no gym's: its dates are written in the platform's own
      # time zone, which the Angular console takes from the browser (M-06).
      def in_gym_time_zone(&action)
        Time.use_zone("Africa/Tunis", &action)
      end

      # The API's words for a refusal, which the page shows in a toast.
      def render_refusal(messages, status: :unprocessable_content)
        messages = Array(messages)
        render json: { error: messages.first || "Validation failed", errors: messages }, status: status
      end
    end
  end
end
