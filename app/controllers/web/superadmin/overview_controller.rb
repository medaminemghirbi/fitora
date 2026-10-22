module Web
  module Superadmin
    # How Fitora itself is doing (PlatformMetrics, round-tripped through JSON
    # so the page reads what the API answers), and what is waiting on a
    # superadmin: open tickets, bills not yet paid.
    class OverviewController < BaseController
      def show
        @metrics = JSON.parse(PlatformMetrics.call.to_json).deep_symbolize_keys
        @open_tickets = SupportTicket.open.count
        @due_invoices = Invoice.due.count
      end
    end
  end
end
