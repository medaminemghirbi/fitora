module Api
  module V1
    module Superadmin
      # What Fitora itself looks like this month (PlatformMetrics).
      #
      # The superadmin console opened on a list of companies, which answers "who
      # are they" and not "how is the business". This answers the second.
      class MetricsController < BaseController
        before_action :require_superadmin!

        # GET /api/v1/superadmin/metrics
        def show
          render json: PlatformMetrics.call
        end
      end
    end
  end
end
