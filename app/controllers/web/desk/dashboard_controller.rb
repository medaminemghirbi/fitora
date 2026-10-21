module Web
  module Desk
    # The desk's home (DeskDashboardComponent): the session on now, what is
    # still to come today, memberships about to lapse, who is new. Read
    # through what /api/v1/admin/dashboard answers, round-tripped through
    # JSON so the page reads the very values the Angular page reads — and
    # refused as that endpoint refuses it (`reports`), which the Angular page
    # shows as its error state with the API's message.
    class DashboardController < BaseController
      def show
        # Api::V1::BaseController#render_forbidden's words.
        return @error = "You are not allowed to perform this action" unless capability?(:reports)

        stats = Dashboard::Statistics.call(company: current_company, revenue: capability?(:revenue))
        @stats = JSON.parse(stats.to_json).deep_symbolize_keys
      end
    end
  end
end
