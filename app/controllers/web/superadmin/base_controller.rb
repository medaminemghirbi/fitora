module Web
  module Superadmin
    # Fitora's own console (/superadmin/…, SuperadminShellComponent):
    # authGuard, then roleGuard("superadmin"). Not salle-scoped
    # (MIGRATION_AUDIT §8.1): it is the one cross-tenant namespace, and reads
    # aggregates and accounts, never a gym's own records — the way into
    # those is impersonation, which is audited.
    class BaseController < Web::BaseController
      layout "web/superadmin"

      before_action :require_superadmin_session!

      private

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

      # Api::V1::BaseController#paginate / #pagination_meta: ?page= from 1,
      # 20 a page.
      def page_meta(scope, per_page: 20)
        page = [ params[:page].to_i, 1 ].max
        total = scope.count
        [ scope.limit(per_page).offset((page - 1) * per_page), { page: page, per_page: per_page, total: total, total_pages: (total.to_f / per_page).ceil } ]
      end
    end
  end
end
