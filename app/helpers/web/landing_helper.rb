module Web
  # The landing page's illustrative data and small sums, as LandingComponent
  # has them.
  module LandingHelper
    # What each plan costs per month, in dinars, and the annual discount —
    # kept in step BY HAND with the superadmin's TND prices, as the Angular
    # page keeps them (there is no public pricing endpoint).
    LANDING_MONTHLY_DT = { "starter" => 165, "pro" => 249 }.freeze
    LANDING_ANNUAL_DISCOUNT = 10

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

    LANDING_PLANS = [
      { key: "starter", items: %w[landing.plan_item_all landing.plan_item_one_salle landing.plan_item_system_roles] },
      # Kept in step with Subscription#pro_features? on the backend.
      { key: "pro", items: %w[landing.plan_item_everything_starter landing.plan_item_multi_salle landing.plan_item_member_app landing.plan_item_custom_roles
                              landing.plan_item_branding landing.plan_item_import landing.plan_item_print landing.plan_item_updates] }
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

    # #priceOf: per month, or the year's total after the discount — whole
    # when it is whole, else two decimals, in the page's language (ar as ar-TN).
    def landing_price(key, billing)
      monthly = LANDING_MONTHLY_DT.fetch(key)
      amount = billing == "monthly" ? monthly : monthly * 12 * (100 - LANDING_ANNUAL_DISCOUNT) / 100.0
      decimals = amount == amount.to_i ? 0 : 2
      Web::NumberFormat.locale_string(amount, locale: locale_code == "ar" ? "ar-TN" : locale_code, max_fraction: decimals, min_fraction: decimals)
    end

    # #fill and #isFull: how full a class is; a one-to-one slot is booked, not "full".
    def landing_fill(item) = [ 100, (item[:booked] * 100.0 / item[:capacity]).round ].min
    def landing_full?(item) = item[:capacity] > 1 && item[:booked] >= item[:capacity]
  end
end
