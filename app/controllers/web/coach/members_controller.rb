module Web
  module Coach
    # The coach's members (CoachMembersComponent): CoachMembers, as
    # GET /api/v1/coach/members?q= pages it (its first page of 20).
    # ?fragment=1 is the list alone, as the search redraws it.
    class MembersController < BaseController
      PER_PAGE = 20

      def index
        @query = params[:q].to_s
        list = CoachMembers.new(company: current_company, staff_member: current_staff_member)
        scope = list.scope(@query.strip.presence)
        @members = JSON.parse(list.rows(scope.order(:first_name, :last_name).limit(PER_PAGE)).to_json).map(&:deep_symbolize_keys)
        @total = scope.count
        render partial: "web/coach/members/list", locals: { members: @members, total: @total, query: @query } if params[:fragment].present?
      end
    end
  end
end
