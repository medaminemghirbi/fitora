module Api
  module V1
    module Admin
      class DashboardController < BaseController
        before_action -> { require_capability!(:reports) }
        before_action :require_company!

        # GET /api/v1/admin/dashboard
        def show
          stats = Dashboard::Statistics.call(company: current_company, revenue: capability?(:revenue))

          render json: {
            company: CompanySerializer.new(current_company).as_json.except(:signature_url),
            stats: stats
          }
        end
      end
    end
  end
end
