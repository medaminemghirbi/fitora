module Web
  module Superadmin
    # How Fitora itself is doing (SuperadminOverviewComponent): PlatformMetrics,
    # round-tripped through JSON so the page reads what the Angular page reads.
    class OverviewController < BaseController
      def show
        @metrics = JSON.parse(PlatformMetrics.call.to_json).deep_symbolize_keys
      end
    end
  end
end
