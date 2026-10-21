module Web
  module Desk
    # Check-in at the desk (DeskCheckinComponent): today's sessions still on
    # the schedule — as GET /api/v1/sessions?date= returns them, first page —
    # then the roster of the one picked. ?session= picks one, if it is one of
    # today's; a single session is picked by itself.
    class CheckinController < BaseController
      def show
        sessions = Sessions::Planner.new(company: current_company, staff_member: current_staff_member).day(Date.current)
        @sessions = JSON.parse(Sessions::Planner.serialize(sessions).to_json).map(&:deep_symbolize_keys)
                        .select { |s| s[:status] == "scheduled" }
        @selected = @sessions.find { |s| s[:id] == params[:session] } || (@sessions.one? ? @sessions.first : nil)
      end
    end
  end
end
