module Web
  # ClientProfileComponent's computed values, for the server-rendered file.
  module ClientProfileHelper
    BOOKING_KINDS = { "completed" => "attended", "no_show" => "missed", "cancelled" => "cancelled", "confirmed" => "booked" }.freeze
    # How much of what happened shows before "see all", and of what is coming.
    TIMELINE_SHOWN = 6
    UPCOMING_SHOWN = 3

    # Where this member stands, in one sentence: what the desk must know first,
    # and the one thing to do about it. Money before dates: what is owed is
    # owed whatever the subscription's state.
    def profile_verdict(client, term, owed)
      covers = term && subscription_label(term)
      ends = term&.dig(:expires_at) && ngt("clients.until", date: ng_date(term[:expires_at], "d MMM y"))
      line = [ covers, ends ].compact.join(" · ")

      return { tone: "off", icon: "bi-person-slash", title: ngt("clients.verdict_inactive"), detail: line } unless client[:active]
      return { tone: "warn", icon: "bi-cash-coin", title: ngt("contracts.due_amount", amount: ng_money(owed, salle.currency)), detail: line, action: :collect } if owed.positive?
      return { tone: "off", icon: "bi-info-circle", title: ngt("clients.verdict_none"), detail: ngt("clients.verdict_none_detail"), action: :sell } if term.nil?

      noted = [ covers, subscription_period_note(term) ].compact.join(" · ")
      case term[:state]
      when "expired" then { tone: "bad", icon: "bi-exclamation-circle", title: subscription_state_label(term), detail: noted }
      when "expiring" then { tone: "warn", icon: "bi-hourglass-split", title: subscription_state_label(term), detail: line }
      when "paused" then { tone: "info", icon: "bi-pause-circle", title: subscription_state_label(term), detail: noted }
      when "upcoming" then { tone: "info", icon: "bi-calendar-event", title: subscription_state_label(term), detail: noted }
      # The subscription is named just below: here, only that all is well.
      else { tone: "ok", icon: "bi-check-circle-fill", title: ngt("clients.verdict_ok"), detail: [ [ ngt("contracts.state_active"), ends ].compact.join(" "), ngt("clients.verdict_paid") ].join(" · ") }
      end
    end

    # A class today to mark them present at (client-profile#checkIn looks for
    # the same booking).
    def profile_booked_today?(profile)
      profile[:bookings].any? { |b| b[:status] == "confirmed" && b.dig(:session, :starts_at).to_s.start_with?(Date.current.iso8601) }
    end

    # The classes they are booked on and that have not begun, soonest first.
    def profile_upcoming(profile)
      profile[:bookings].select { |b| profile_ahead?(b) }.sort_by { |b| b.dig(:session, :starts_at).in_time_zone }
    end

    def profile_ahead?(booking)
      booking[:status] == "confirmed" && booking.dig(:session, :starts_at).in_time_zone.future?
    end

    # In words, what the form offers; anything typed before it did, as it was.
    def profile_gender(gender)
      { "male" => ngt("clients.gender_male"), "female" => ngt("clients.gender_female") }.fetch(gender, gender)
    end

    # The last class they were present at, nil when there is none.
    def profile_last_attended(profile)
      profile[:bookings].select { |b| b[:status] == "completed" }.max_by { |b| b.dig(:session, :starts_at).in_time_zone }
    end

    # What happened, unfiltered: the bookings (dated by the session) and the
    # payments (by when the money came), newest first — a stable sort, as
    # Array#sort is in JavaScript, so ties keep sessions before payments. What
    # is still to come is not in it (profile_upcoming).
    def profile_timeline(profile)
      sessions = profile[:bookings].reject { |booking| profile_ahead?(booking) }.map do |booking|
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
        required: ngt("common.required"), email_invalid: ngt("auth.email_invalid"),
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
        saved: ngt("clients.photo_saved"), removed: ngt("clients.photo_removed"), camera_error: ngt("clients.photo_camera_error"),
        error: ngt("common.error_generic")
      }
    end

    # JavaScript's +x printed: "79", "79.5".
    def profile_number(value)
      Web::LineChart.num(value.to_f)
    end
  end
end
