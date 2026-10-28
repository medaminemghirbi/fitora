module Web
  # The door's small decisions (Web::Admin::EntriesController) and the two
  # things other pages borrow from it: a member's face — their photo, or
  # their initials — and a WhatsApp reminder written for them.
  module EntriesHelper
    PHOTO_LINK_EXPIRES_IN = 30.minutes

    # The photo's address, signed and short-lived (a member's face is not a
    # public file), or nil when there is none.
    def member_photo_path(membership)
      return nil unless membership&.photo&.attached?

      rails_blob_path(membership.photo, disposition: "inline", expires_in: PHOTO_LINK_EXPIRES_IN)
    end

    # A round face `size` pixels wide: the photo, or the initials on the
    # avatar's colour.
    def member_face(name, membership, size: 40, css_class: nil)
      classes = [ "ent-face", css_class ].compact.join(" ")
      if (src = member_photo_path(membership))
        tag.img(src: src, alt: "", class: classes, width: size, height: size, loading: "lazy", style: "width:#{size}px;height:#{size}px")
      else
        tag.span(ng_initials(name), class: "#{classes} is-initials", style: "#{ng_avatar_style(size)};", "aria-hidden": "true")
      end
    end

    # The banner's first line: what to do.
    def entry_headline(verdict)
      ngt("entries.tone_#{verdict.tone}")
    end

    # Why it is red, in the desk's words — with the date or amount it is
    # about.
    def entry_reason(verdict)
      contract = verdict.contract
      case verdict.reason
      when "expired" then ngt("entries.reason_expired", date: ng_date(contract&.expires_at, "d MMM y"))
      when "not_started" then ngt("entries.reason_not_started", date: ng_date(contract&.starts_at, "d MMM y"))
      when "unpaid" then ngt("entries.reason_unpaid", amount: ng_money(verdict.balance, salle.currency))
      when nil then nil
      else ngt("entries.reason_#{verdict.reason}")
      end
    end

    # What amber has to say, one line each.
    def entry_notices(verdict)
      verdict.notices.map do |notice|
        case notice
        when "already_in" then ngt("entries.notice_already_in", time: ng_date(verdict.last_visit_at, "HH:mm"))
        when "expires_soon" then ngt("entries.notice_expires_soon", count: verdict.contract.days_left)
        else ngt("entries.notice_#{notice}")
        end
      end
    end

    # The day's figures: visits, people, forced ones, and visits per hour
    # (the gym's opening hours, widened to any visit outside them).
    def entry_stats(visits)
      hours = visits.map { |v| v.checked_in_at.in_time_zone.hour }
      opening = salle.settings.hours
      first = [ opening[:start].to_s.to_i, *hours ].min
      last = [ opening[:end].to_s.to_i - 1, *hours ].max
      by_hour = hours.tally
      {
        visits: visits.size,
        members: visits.map(&:client_id).uniq.size,
        forced: visits.count(&:forced?),
        hours: (first..last).map { |hour| [ hour, by_hour.fetch(hour, 0) ] }
      }
    end

    # A wa.me link that opens a chat with the member, the reminder typed in
    # the gym's language: what they owe, an end that has passed or is near,
    # or just a greeting. nil when they have no phone number.
    def member_whatsapp_link(name:, phone:, kind: "hello", plan: nil, date: nil, amount: nil)
      date = Time.zone.parse(date) if date.is_a?(String)
      words = Web::Translations.translate(
        "whatsapp.message_#{kind}",
        { name: name.to_s.split.first, gym: salle.name, plan: plan, amount: amount,
          date: date && Web::DateFormat.angular(date.in_time_zone, "d MMM y", locale: salle.locale) },
        locale: salle.locale
      )
      Whatsapp.link(phone, words, country: salle.country.presence || "TN")
    end

    # The member's card as a QR code, drawn inline (SVG) for their own app.
    def member_card_qr(code)
      RQRCode::QRCode.new(code.to_s, level: :m).as_svg(module_size: 6, standalone: true, use_path: true, viewbox: true).html_safe # rubocop:disable Rails/OutputSafety
    end

    # Which reminder fits: money first, then the end of the subscription.
    def whatsapp_kind(balance:, state:)
      return "unpaid" if balance.to_f.positive?

      case state
      when "expired" then "expired"
      when "expiring" then "expiring"
      else "hello"
      end
    end
  end
end
