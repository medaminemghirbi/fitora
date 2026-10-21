module Web
  module Superadmin
    # The superadmin's bell (Web::BellEndpoints): no inbox page — a
    # system_update opens the editable release notes it is about.
    class NotificationsController < BaseController
      include Web::BellEndpoints

      private

      def notification_recipient = current_user
    end
  end
end
