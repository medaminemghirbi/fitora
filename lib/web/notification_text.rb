module Web
  # notification-text.ts: a notification's title and body, composed from its
  # kind and data in the page's language — one composer per kind, a generic
  # title for a kind this build does not know — and the label of its
  # detail page's button.
  module NotificationText
    def self.t(key, params = {}) = Web::Translations.translate(key, params, locale: I18n.locale)

    # formatDate / formatDateTime: Intl, in ngx-translate's current language.
    def self.date(iso) = iso.present? ? Web::DateFormat.intl(Time.zone.parse(iso.to_s), :notification_date) : ""
    def self.datetime(iso) = iso.present? ? Web::DateFormat.intl(Time.zone.parse(iso.to_s), :notification_datetime) : ""

    COMPOSERS = {
      "contract_expiring" => ->(d) {
        { title: t("notifications.contract_expiring.title"),
          body: t("notifications.contract_expiring.body", name: d["client_name"] || "—", type: d["contract_type"] || "—", date: date(d["expires_at"])) }
      },
      "employee_birthday" => ->(d) {
        { title: t("notifications.employee_birthday.title"), body: t("notifications.employee_birthday.body", name: d["name"] || "—") }
      },
      "system_update" => ->(d) {
        { title: t("notifications.system_update.title", version: d["version"] || ""), body: d["title"] || "" }
      },
      "invoice_issued" => ->(d) {
        { title: t("notifications.invoice_issued.title", number: d["number"] || "—"),
          body: t("notifications.invoice_issued.body", amount: d["amount"] || "—", currency: d["currency"] || "") }
      },
      "plan_changed" => ->(d) {
        { title: t("notifications.plan_changed.title", plan: d["plan"] ? t("subscription.plan_#{d['plan']}") : "—"),
          body: t("notifications.plan_changed.body", number: d["number"] || "—", amount: d["amount"] || "—", currency: d["currency"] || "") }
      },
      "access_suspended" => ->(_d) {
        { title: t("notifications.access_suspended.title"), body: t("notifications.access_suspended.body") }
      },
      "access_restored" => ->(_d) {
        { title: t("notifications.access_restored.title"), body: t("notifications.access_restored.body") }
      },
      "session_cancelled" => ->(d) {
        { title: t("notifications.session_cancelled.title"),
          body: t("notifications.session_cancelled.body", activity: d["activity_name"] || "—", date: datetime(d["starts_at"]), gym: d["gym_name"] || "") }
      },
      "waitlist_promoted" => ->(d) {
        { title: t("notifications.waitlist_promoted.title"),
          body: t("notifications.waitlist_promoted.body", activity: d["activity_name"] || "—", date: datetime(d["starts_at"]), gym: d["gym_name"] || "") }
      },
      "session_reminder" => ->(d) {
        { title: t("notifications.session_reminder.title"),
          body: t("notifications.session_reminder.body", activity: d["activity_name"] || "—", date: datetime(d["starts_at"]), gym: d["gym_name"] || "") }
      },
      "subscription_expiring" => ->(d) {
        { title: t("notifications.subscription_expiring.title"),
          body: t("notifications.subscription_expiring.body", plan: d["plan_name"] || "—", date: date(d["expires_at"]), gym: d["gym_name"] || "") }
      }
    }.freeze

    CTA_KEYS = {
      "contract_expiring" => "notifications.open_contract", "employee_birthday" => "notifications.open_employee",
      "system_update" => "notifications.open_system_update", "invoice_issued" => "notifications.open_invoice",
      "plan_changed" => "notifications.open_invoice", "access_suspended" => "notifications.open_invoice",
      "access_restored" => "notifications.open_invoice",
      "session_cancelled" => "notifications.open_bookings", "waitlist_promoted" => "notifications.open_bookings",
      "subscription_expiring" => "notifications.open_profile", "session_reminder" => "notifications.open_bookings"
    }.freeze

    # The emoji badge of NotificationArtComponent.
    EMOJI = {
      "contract_expiring" => "📋", "employee_birthday" => "🎂", "system_update" => "🚀", "invoice_issued" => "🧾",
      "plan_changed" => "🧾", "access_suspended" => "🔒", "access_restored" => "🔓",
      "session_cancelled" => "🚫", "waitlist_promoted" => "🎟️", "subscription_expiring" => "⏳", "session_reminder" => "⏰"
    }.freeze

    # `notification`: NotificationSerializer's hash.
    def self.for(notification)
      composer = COMPOSERS[notification[:kind].to_s]
      return { title: t("notifications.title"), body: "" } if composer.nil?

      composer.call((notification[:data] || {}).to_h.stringify_keys)
    end

    def self.cta_key(notification)
      CTA_KEYS.fetch(notification[:kind].to_s, "notifications.open_generic")
    end

    # TimeAgoPipe: "à l'instant", "3 min", "2 h", "5 j", then a short date.
    def self.time_ago(value, now: Time.current)
      return "" if value.blank?

      time = value.is_a?(String) ? Time.zone.parse(value) : value.in_time_zone
      secs = ((now - time) * 1).round
      return t("time.now") if secs < 45
      return t("time.minutes", n: [ 1, (secs / 60.0).round ].max) if secs < 3600
      return t("time.hours", n: (secs / 3600.0).round) if secs < 86_400
      return t("time.days", n: (secs / 86_400.0).round) if secs < 7 * 86_400

      Web::DateFormat.intl(time, :time_ago_date)
    end
  end
end
