module Web
  # A member's file: their face, and a WhatsApp reminder written for them.
  module MemberFileHelper
    PHOTO_LINK_EXPIRES_IN = 30.minutes

    # The photo's address, signed and short-lived (a member's face is not a
    # public file), or nil when there is none.
    def member_photo_path(membership)
      return nil unless membership&.photo&.attached?

      rails_blob_path(membership.photo, disposition: "inline", expires_in: PHOTO_LINK_EXPIRES_IN)
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
