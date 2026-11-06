module Web
  module Superadmin
    # How Fitora itself is doing (PlatformMetrics, round-tripped through JSON
    # so the page reads what the API answers), and what is waiting on a
    # superadmin: open tickets, accounts not activated yet.
    class OverviewController < BaseController
      def show
        @metrics = JSON.parse(PlatformMetrics.call.to_json).deep_symbolize_keys
        @open_tickets = SupportTicket.open.count
        @latest_update = AppUpdate.recent.first
      end
    end
  end
end
