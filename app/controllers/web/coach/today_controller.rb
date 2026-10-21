module Web
  module Coach
    # "Aujourd'hui" (CoachTodayComponent): the coach's own sessions of a day —
    # as GET /api/v1/sessions?date= answers a coach, first page — the one on
    # now or next, and the roster of the one picked (Coach::AttendanceController).
    # ?date= keeps the day across a reload (M-05); ?fragment=1 is the day
    # alone, as the page redraws it when the day changes.
    class TodayController < BaseController
      def show
        @date = day
        sessions = Sessions::Planner.new(company: current_company, staff_member: current_staff_member).day(@date)
        @sessions = JSON.parse(Sessions::Planner.serialize(sessions).to_json).map(&:deep_symbolize_keys)
        render partial: "web/coach/today/day", locals: { sessions: @sessions, date: @date } if params[:fragment].present?
      end

      private

      # The day asked for, else today in the gym.
      def day
        Date.iso8601(params[:date].to_s)
      rescue Date::Error
        Date.current
      end
    end
  end
end
