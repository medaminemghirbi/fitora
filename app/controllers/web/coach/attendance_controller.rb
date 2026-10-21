module Web
  module Coach
    # The coach's roster and marks (CoachTodayComponent#selectSession /
    # #mark) — see Web::AttendanceEndpoints. The coach's day draws its own
    # rows: a table with a button per status, not the check-in panel.
    class AttendanceController < BaseController
      include Web::AttendanceEndpoints

      private

      def roster_partial = "web/coach/today/roster"
      def marked_partial = "web/coach/today/row"
    end
  end
end
