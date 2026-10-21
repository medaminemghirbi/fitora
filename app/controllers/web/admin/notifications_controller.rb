module Web
  module Admin
    # The admin's notifications: the inbox (NotificationsInboxComponent), one
    # notification (NotificationDetailComponent), and the bell's panel
    # (NotificationBellComponent) — the API's pages of ten, the same records,
    # marked read the same way (Api::V1::NotificationsController).
    class NotificationsController < BaseController
      PER_PAGE = Api::V1::NotificationsController::PER_PAGE

      before_action :require_admin
      before_action :set_notification, only: %i[show read]

      helper_method :notification_text

      # GET …/notifications — the first page; ?page=N&fragment=inbox|panel
      # for the rows of a later page (load more), or the bell's first page.
      def index
        @page = [ params[:page].to_i, 1 ].max
        scope = current_user.notifications.recent
        @notifications = scope.limit(PER_PAGE).offset((@page - 1) * PER_PAGE).map { |n| NotificationSerializer.new(n).as_json }
        @has_more = scope.count > @page * PER_PAGE
        @unread_count = current_user.notifications.unread.count

        case params[:fragment]
        when "inbox" then render partial: "web/admin/notifications/items", locals: { notifications: @notifications, has_more: @has_more }
        when "panel" then render partial: "web/shell/notification_rows", locals: { notifications: @notifications, has_more: @has_more }
        end
      end

      # GET …/notifications/:id — read on opening, as the Angular page marks it.
      def show
        @notification.mark_read!
        @item = NotificationSerializer.new(@notification).as_json
      end

      # PATCH …/notifications/:id/read
      def read
        @notification.mark_read!
        render json: { unread_count: current_user.notifications.unread.count }
      end

      # POST …/notifications/read_all
      def read_all
        Notification.read_all!(current_user)
        render json: { unread_count: 0 }
      end

      private

      def set_notification
        @notification = current_user.notifications.find(params[:id])
      end

      def notification_text(item)
        Web::NotificationText.for(item)
      end
    end
  end
end
