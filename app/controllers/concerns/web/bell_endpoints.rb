module Web
  # The bell's requests in a shell with no inbox page (the member's, the
  # superadmin's): a page of its panel, one notification read, all of them
  # read — the API's pages of ten and its read marks
  # (Api::V1::NotificationsController, Api::V1::Me::NotificationsController),
  # for whoever `notification_recipient` is.
  module BellEndpoints
    extend ActiveSupport::Concern

    included do
      helper_method :notification_text
    end

    # GET …/notifications?page=N — the panel's rows.
    def index
      page = [ params[:page].to_i, 1 ].max
      scope = notification_recipient.notifications.recent
      per_page = Api::V1::NotificationsController::PER_PAGE
      notifications = scope.limit(per_page).offset((page - 1) * per_page).map { |n| NotificationSerializer.new(n).as_json }
      render partial: "web/shell/notification_rows", locals: { notifications: notifications, has_more: scope.count > page * per_page }
    end

    # PATCH …/notifications/:id/read
    def read
      notification_recipient.notifications.find(params[:id]).mark_read!
      render json: { unread_count: notification_recipient.notifications.unread.count }
    end

    # POST …/notifications/read_all
    def read_all
      Notification.read_all!(notification_recipient)
      render json: { unread_count: 0 }
    end

    private

    def notification_text(item)
      Web::NotificationText.for(item)
    end
  end
end
