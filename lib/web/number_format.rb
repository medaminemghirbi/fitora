module Web
  # Number#toLocaleString(lang) as Chromium prints it (lib/web/date_words.json,
  # "numbers"): up to three fraction digits, rounded half away from zero,
  # the language's grouping and decimal marks and digits.
  module NumberFormat
    #
    # `locale` may be a browser tag ("ar-TN") for toLocaleString(undefined, …),
    # which formats in the browser's language (B-03); `max_fraction` and
    # `min_fraction` are maximumFractionDigits and minimumFractionDigits when
    # the call sets them.
    def self.locale_string(number, locale: I18n.locale, max_fraction: nil, min_fraction: 0)
      spec = Web::DateFormat::WORDS.dig("numbers", locale.to_s) || Web::DateFormat::WORDS.dig("numbers", "fr")
      value = number.to_d.round(max_fraction || spec["max_fraction"], half: :up)
      negative = value.negative?
      whole, fraction = value.abs.to_s("F").split(".")
      fraction = fraction.to_s.sub(/0+\z/, "").ljust(min_fraction, "0")
      grouped = whole.length > 3 ? whole.reverse.scan(/\d{1,3}/).join(spec["group"].reverse).reverse : whole
      text = fraction.empty? ? grouped : "#{grouped}#{spec['decimal']}#{fraction}"
      text = text.gsub(/\d/) { |d| spec["digits"][d.to_i] }
      negative ? "-#{text}" : text
    end
  end
end
