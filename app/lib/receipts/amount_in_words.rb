module Receipts
  # "Arrêtée la présente facture à la somme de : cent soixante-cinq dinars"
  # — an amount in dinars written out in French, as a Tunisian invoice
  # states its total, the millimes in figures after it. Traditional
  # spelling: hyphens under a hundred only, "vingt et un", "quatre-vingts"
  # and "deux cents" taking their s only when nothing follows (but
  # "quatre-vingt mille", "deux cents millions"), "mille" invariable.
  module AmountInWords
    module_function

    UNITS = %w[zéro un deux trois quatre cinq six sept huit neuf dix onze douze treize quatorze quinze seize
               dix-sept dix-huit dix-neuf].freeze
    TENS = { 2 => "vingt", 3 => "trente", 4 => "quarante", 5 => "cinquante", 6 => "soixante" }.freeze

    # An amount in millimes: "Cent soixante-cinq dinars et 425 millimes".
    def dinars(millimes)
      whole, rest = millimes.divmod(1000)
      words =
        if whole >= 1_000_000 && (whole % 1_000_000).zero? then "#{number(whole)} de dinars"
        else "#{number(whole)} dinar#{"s" if whole > 1}"
        end
      words += " et #{rest} millime#{"s" if rest > 1}" if rest.positive?
      words[0].upcase + words[1..]
    end

    def number(value)
      return UNITS[0] if value.zero?

      millions, rest = value.divmod(1_000_000)
      thousands, units = rest.divmod(1000)
      parts = []
      parts << (millions == 1 ? "un million" : "#{below_1000(millions)} millions") if millions.positive?
      parts << (thousands == 1 ? "mille" : "#{below_1000(thousands, ends: false)} mille") if thousands.positive?
      parts << below_1000(units) if units.positive?
      parts.join(" ")
    end

    # `ends`: nothing follows, so "cents" and "quatre-vingts" keep their s —
    # false before "mille", which takes it from them.
    def below_1000(value, ends: true)
      hundreds, rest = value.divmod(100)
      parts = []
      parts << (hundreds == 1 ? "cent" : "#{UNITS[hundreds]} cent#{"s" if rest.zero? && ends}") if hundreds.positive?
      if rest.positive?
        words = below_100(rest)
        parts << (!ends && words.end_with?("vingts") ? words.chomp("s") : words)
      end
      parts.join(" ")
    end

    def below_100(value)
      return UNITS[value] if value < 20

      tens, unit = value.divmod(10)
      case tens
      when 7 then unit == 1 ? "soixante et onze" : "soixante-#{UNITS[10 + unit]}"
      when 8 then unit.zero? ? "quatre-vingts" : "quatre-vingt-#{UNITS[unit]}"
      when 9 then "quatre-vingt-#{UNITS[10 + unit]}"
      else
        return TENS[tens] if unit.zero?

        unit == 1 ? "#{TENS[tens]} et un" : "#{TENS[tens]}-#{UNITS[unit]}"
      end
    end
  end
end
