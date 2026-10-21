module Web
  module Member
    # The member's bell (Web::BellEndpoints): a member has no inbox page, so
    # each notification opens what it is about.
    class NotificationsController < BaseController
      include Web::BellEndpoints

      private

      def notification_recipient = current_client
    end
  end
end
