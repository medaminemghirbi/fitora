# The platform changelog a superadmin edits after each release — version,
# what's new, screenshots and screen recordings. Publishing one notifies
# every other superadmin AND every admin in real time (NotificationChannel):
# the team knows the update went out, and every customer sees what's new.
# Shared by POST /api/v1/superadmin/app_updates and the web UI's superadmin
# updates page (MIGRATION_AUDIT §3.2); moved here unchanged from
# Api::V1::Superadmin::AppUpdatesController.
module ReleaseNotes
  module_function

  # Returns the update, saved (and announced) or carrying its errors.
  def publish(attributes, media:, by:)
    update = AppUpdate.new(attributes.merge(created_by: by))
    update.media.attach(media) if media.present?
    announce(update, by: by) if update.save
    update
  end

  def announce(update, by:)
    data = { version: update.version, title: update.title, published_by: by.full_name }
    User.superadmin.active.where.not(id: by.id).find_each do |superadmin|
      Notification.push(
        recipient: superadmin, kind: "system_update", data: data, url: "/superadmin/updates",
        dedup_key: "system_update-#{update.id}-#{superadmin.id}", subject: update
      )
    end
    # Every customer sees the release notes too, on their own read-only
    # page — superadmins get the editable /superadmin/updates instead.
    User.admin.active.find_each do |admin|
      Notification.push(
        recipient: admin, kind: "system_update", data: data, url: "/admin/updates",
        dedup_key: "system_update-#{update.id}-#{admin.id}", subject: update
      )
    end
  end
end
