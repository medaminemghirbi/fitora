module Web
  # ClientProfileComponent's computed values, for the server-rendered file.
  module ClientProfileHelper
    TIMELINE_ICONS = { "attended" => "bi-check2", "missed" => "bi-x", "cancelled" => "bi-slash-circle",
                       "booked" => "bi-calendar-check", "paid" => "bi-cash-coin", "refunded" => "bi-arrow-counterclockwise" }.freeze
    BOOKING_KINDS = { "completed" => "attended", "no_show" => "missed", "cancelled" => "cancelled", "confirmed" => "booked" }.freeze

    # #timeline, unfiltered: the bookings (dated by the session) and the
    # payments (by when the money came), newest first — a stable sort, as
    # Array#sort is in JavaScript, so ties keep sessions before payments.
    def profile_timeline(profile)
      sessions = profile[:bookings].map do |booking|
        { id: "b-#{booking[:id]}", at: booking.dig(:session, :starts_at), stream: "sessions",
          kind: BOOKING_KINDS.fetch(booking[:status], "booked"),
          title: "#{booking.dig(:session, :activity_emoji).to_s != '' ? "#{booking.dig(:session, :activity_emoji)} " : ''}#{booking.dig(:session, :activity_name)}",
          detail: profile_covered_by(booking) }
      end
      money = profile[:payments].map do |payment|
        { id: "p-#{payment[:id]}", at: payment[:paid_at] || payment[:created_at], stream: "payments",
          kind: payment[:status] == "refunded" ? "refunded" : "paid",
          title: "#{Web::LineChart.num(payment[:amount].to_f)} #{payment[:currency]}", detail: payment[:product_name] }
      end
      (sessions + money).each_with_index.sort_by { |entry, i| [ -entry[:at].in_time_zone.to_f, i ] }.map(&:first)
    end

    # #coveredBy: what paid for a booking, in words.
    def profile_covered_by(booking)
      covered = booking[:covered_by]
      return nil if covered.nil?
      return covered[:name] if covered[:type] == "contract"

      ngt("bookings.kind_#{covered[:type]}")
    end

    # The words client-profile says (toasts, confirmations, the dialogs').
    def client_profile_labels
      t = ->(key) { Web::Translations.translate(key, {}, locale: I18n.locale) }
      {
        error: ngt("common.error_generic"), save: ngt("common.save"), saved: ngt("common.saved"), saving: ngt("common.saving"), confirm: ngt("common.confirm"),
        present: ngt("coach.attendance_present"), no_session_today: ngt("clients.no_session_today"),
        invite_title: ngt("clients.invite_confirm_title"), invite_body: t.call("clients.invite_confirm_body"), invite_sent: t.call("clients.invite_sent"),
        remove_title: t.call("clients.remove_confirm_title"), remove_body: ngt("clients.remove_confirm_body"), remove: ngt("clients.remove"), removed: t.call("clients.removed"),
        contract_label: ngt("contracts.title"), booking_label: ngt("bookings.title"),
        kind_hints: %w[contract trial drop_in].to_h { |k| [ k, ngt("bookings.kind_#{k}_hint") ] },
        symbols: Web::Currency::SYMBOLS
      }
    end

    # The words member-photo says.
    def member_photo_labels
      {
        title: ngt("clients.photo_title"), take: ngt("clients.photo_take"), capture: ngt("clients.photo_capture"),
        choose: ngt("clients.photo_choose"), remove: ngt("clients.photo_remove"), cancel: ngt("common.cancel"),
        saved: ngt("clients.photo_saved"), removed: ngt("clients.photo_removed"), camera_error: ngt("entries.camera_error"),
        error: ngt("common.error_generic")
      }
    end

    # JavaScript's +x printed: "79", "79.5".
    def profile_number(value)
      Web::LineChart.num(value.to_f)
    end
  end
end
