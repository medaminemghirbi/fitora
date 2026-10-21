module Api
  module V1
    module Me
      # The schedule of the gym the member belongs to — what their app opens
      # on. Read-only: booking is Me::BookingsController#create.
      #
      # Sessions are serialised through PublicSessionSerializer, which says
      # how many places are left and never what the gym charges or who else
      # is coming.
      class SessionsController < BaseController
        before_action :require_client!
        before_action :require_member_app!
        before_action :require_member_company!

        # GET /api/v1/me/sessions?date=YYYY-MM-DD&company_id=
        def index
          company_ids = member_company ? [ member_company.id ] : member_companies.map(&:id)
          date = Date.parse(params[:date]) if params[:date].present?
          render json: { sessions: MemberApp.sessions(current_client, company_ids, date: date) }
        end
      end
    end
  end
end
