module Web
  # Dates written the way the Angular app writes them, word for word.
  #
  # The Angular app formats dates two ways, so there are two here:
  #
  # - .angular(time, "d MMM y") — Angular's DatePipe, which reads its month
  #   and day names from @angular/common's own locale data;
  # - .intl(time, :day_month_short) — Date#toLocaleDateString /
  #   Intl.DateTimeFormat, which the browser's ICU answers.
  #
  # Both read lib/web/date_words.json, extracted from those two sources by
  # test/parity/extract-date-words.mjs. Times are shown in the zone they come
  # in: callers pass them in the gym's time zone (Web::BaseController runs
  # every request in it).
  module DateFormat
    WORDS = JSON.parse(File.read(File.expand_path("date_words.json", __dir__))).freeze
    LOCALES = %w[fr en ar].freeze

    # The DatePipe tokens the app's templates use.
    def self.angular(time, pattern, locale: I18n.locale)
      return "" if time.nil?

      words = WORDS.fetch("angular").fetch(code(locale))
      pattern = words.fetch("formats").fetch(pattern, pattern) # "mediumDate" → "d MMM y"
      pattern.gsub(/d{1,2}|M{1,4}|y{1,4}|E{3,4}|H{1,2}|h{1,2}|m{2}|s{2}|a/) do |token|
        case token
        when "d" then time.day.to_s
        when "M" then time.month.to_s
        when "h" then ((time.hour % 12).nonzero? || 12).to_s
        when "hh" then format("%02d", (time.hour % 12).nonzero? || 12)
        when "H" then time.hour.to_s
        when "a" then words.fetch("day_periods")[time.hour < 12 ? 0 : 1]
        when "dd" then format("%02d", time.day)
        when "MMM" then words.fetch("months_abbreviated")[time.month - 1]
        when "MMMM" then words.fetch("months_wide")[time.month - 1]
        when "MM" then format("%02d", time.month)
        when "y", "yyyy" then time.year.to_s
        when "yy" then format("%02d", time.year % 100)
        when "EEEE" then words.fetch("days_wide")[time.wday]
        when "EEE" then words.fetch("days_abbreviated")[time.wday]
        when "HH" then format("%02d", time.hour)
        when "mm" then format("%02d", time.min)
        when "ss" then format("%02d", time.sec)
        else raise ArgumentError, "unsupported DatePipe token #{token}"
        end
      end
    end

    # An Intl format, by the name extract-date-words.mjs gave it: its parts
    # in the locale's order, its words, its digits and its clock.
    def self.intl(time, format_name, locale: I18n.locale)
      return "" if time.nil?

      spec = WORDS.fetch("intl").fetch(code(locale)).fetch(format_name.to_s)
      options = spec.fetch("options")
      two = ->(key) { options[key] == "2-digit" }
      spec.fetch("parts").map do |part|
        next part["literal"] if part.key?("literal")

        case part["type"]
        when "day" then digits(two.call("day") ? format("%02d", time.day) : time.day.to_s, spec)
        when "month" then spec.fetch("month")[time.month - 1]
        when "weekday" then spec.fetch("weekday")[time.wday]
        when "year" then digits(time.year.to_s, spec)
        when "hour"
          hour = spec["hour12"] ? (time.hour % 12).nonzero? || 12 : time.hour
          digits(two.call("hour") ? format("%02d", hour) : hour.to_s, spec)
        when "minute" then digits(format("%02d", time.min), spec)
        when "dayPeriod" then spec.dig("dayPeriod", time.hour < 12 ? "am" : "pm")
        else raise ArgumentError, "unsupported Intl part #{part['type']}"
        end
      end.join
    end

    # JavaScript's label.charAt(0).toLocaleUpperCase() + label.slice(1).
    def self.capitalize_first(text)
      text.empty? ? text : text[0].upcase + text[1..]
    end

    def self.code(locale)
      LOCALES.include?(locale.to_s) ? locale.to_s : "fr"
    end

    # ASCII digits written the way this locale writes them.
    def self.digits(text, spec)
      table = spec.fetch("digits")
      text.gsub(/\d/) { |d| table[d.to_i] }
    end
  end
end
