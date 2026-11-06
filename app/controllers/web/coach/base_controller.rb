module Web
  module Coach
    # A coach's own shell (/coach/<salle>/…, CoachShellComponent): authGuard,
    # then staffRoleGuard("coach") in the salle the URL names
    # (Web::SalleShell) — whoever coaches there, whatever their role is
    # called.
    class BaseController < Web::BaseController
      include Web::SalleShell

      layout "web/coach"

      before_action :require_staff_session!
      before_action :enter_salle!
      before_action :coach_area!

      helper_method :coach_path

      private

      def coach_area!
        go_home unless current_user.staff? && current_staff_member&.coach?
      end

      def coach_path(page, query = {})
        path = "/coach/#{salle.id}/#{page}"
        query.compact_blank.empty? ? path : "#{path}?#{query.compact_blank.to_query}"
      end
    end
  end
end
