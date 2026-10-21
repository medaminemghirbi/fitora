module Api
  module V1
    module Coach
      # The people a coach actually trains (CoachMembers): everyone with a
      # live booking on one of their own sessions.
      #
      # This is the one thing the coach's day needed that no existing endpoint
      # answered. The schedule and attendance endpoints already narrow to a
      # coach's own sessions (SessionsController#base_scope,
      # AttendanceController#accessible_sessions), so there is deliberately no
      # parallel /coach/sessions here — a second way to ask the same question
      # is a second place for the narrowing to be got wrong.
      class MembersController < BaseController
        before_action :require_company!
        before_action :require_coach!

        # GET /api/v1/coach/members?q=
        def index
          list = CoachMembers.new(company: current_company, staff_member: current_staff_member)
          scope = list.scope(params[:q])

          render json: {
            members: list.rows(paginate(scope.order(:first_name, :last_name))),
            meta: pagination_meta(scope)
          }
        end

        private

        # Not a capability check: this endpoint is only meaningful for someone
        # who has sessions of their own. Anyone else asking gets nothing,
        # because there is nothing there to give them.
        def require_coach!
          render_forbidden unless current_staff_member&.active? && current_staff_member.coach?
        end
      end
    end
  end
end
