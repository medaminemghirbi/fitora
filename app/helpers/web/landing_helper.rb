module Web
  # The landing page's illustrative data and small sums, as LandingComponent
  # has them.
  module LandingHelper
    # Which of the three days' slots are already taken, for the booking mock.
    LANDING_TAKEN_BY_DAY = [ %w[12:30 19:00], %w[09:00 18:00], %w[07:30 20:00] ].freeze
    LANDING_SLOTS = %w[07:30 09:00 12:30 18:00 19:00 20:00].freeze

    # One studio's day, for the hero card. Illustrative.
    LANDING_TODAY = [
      { time: "07:30", name: "EMS", coach: "Amine", room: "Cabine 1", booked: 1, capacity: 1, waitlist: 0 },
      { time: "09:00", name: "Pilates Reformer", coach: "Sarah", room: "Studio", booked: 6, capacity: 6, waitlist: 2 },
      { time: "12:30", name: "Coaching privé", coach: "Yassine", room: "Studio 2", booked: 1, capacity: 1, waitlist: 0 },
      { time: "18:30", name: "Yoga Vinyasa", coach: "Lina", room: "Studio", booked: 9, capacity: 14, waitlist: 0 }
    ].freeze

    # The page's "today": the browser's in Angular, the platform's time zone
    # here, as on the sign-in panel — the server cannot know the browser's
    # (MIGRATION_AUDIT §10, M-06).
    def landing_today
      Time.current.in_time_zone("Africa/Tunis")
    end

    # LandingComponent#todayLabel: "Mercredi 14 octobre", in the page's language.
    def landing_today_label
      Web::DateFormat.capitalize_first(Web::DateFormat.intl(landing_today, :weekday_day_month_long, locale: locale_code))
    end

    # #bookingDays: tomorrow and the two days after.
    def landing_booking_days
      (1..3).map do |offset|
        day = landing_today + offset.days
        { weekday: Web::DateFormat.intl(day, :weekday_short, locale: locale_code), date: Web::DateFormat.intl(day, :day_month_short, locale: locale_code) }
      end
    end

    # #fill and #isFull: how full a class is; a one-to-one slot is booked, not "full".
    def landing_fill(item) = [ 100, (item[:booked] * 100.0 / item[:capacity]).round ].min
    def landing_full?(item) = item[:capacity] > 1 && item[:booked] >= item[:capacity]
  end
end
