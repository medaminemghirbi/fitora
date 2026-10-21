module Web
  module Desk
    # The front desk (/desk/<salle>/…, DeskShellComponent): the guards the
    # Angular /desk route stacks up (app.routes.ts) — authGuard, then
    # deskAreaGuard in the salle the URL names (Web::SalleShell), since what
    # a staff login may do depends on where it is posted.
    class BaseController < Web::BaseController
      include Web::SalleShell

      layout "web/desk"

      before_action :require_staff_session!
      before_action :enter_salle!
      before_action :desk_area!

      helper_method :desk_path, :desk_salles

      private

      # deskAreaGuard: a locked gym sees one page; the desk is for staff who
      # check people in AND book them — not a coach (who has check-in alone),
      # not the admin (whose shell is a superset of this one).
      def desk_area!
        return redirect_to("/account-locked") if locking_subscription.present?
        return go_home unless current_user.staff? && !current_staff_member&.coach?

        go_home unless capability?(:checkin) && capability?(:bookings)
      end

      def desk_path(page, query = {})
        path = "/desk/#{salle.id}/#{page}"
        query.compact_blank.empty? ? path : "#{path}?#{query.compact_blank.to_query}"
      end

      # DeskShellComponent#salles: the salles this login is posted to, once
      # there is more than one to choose from.
      def desk_salles
        companies = bootstrap.dig(:user, :companies)
        companies.present? && companies.size > 1 ? companies : nil
      end
    end
  end
end
