module Web
  # The Angular app's currency catalogue (core/models/currency.ts): the
  # symbol MoneyPipe prints after an amount. An unknown code prints itself.
  module Currency
    SYMBOLS = {
      "TND" => "DT", "MAD" => "DH", "DZD" => "DA", "EGP" => "E£", "EUR" => "€", "USD" => "$",
      "GBP" => "£", "CHF" => "CHF", "CAD" => "CA$", "SAR" => "SAR", "AED" => "AED",
      "QAR" => "QAR", "XOF" => "FCFA"
    }.freeze

    def self.symbol(code)
      return "" if code.blank?

      SYMBOLS.fetch(code.to_s, code.to_s)
    end
  end
end
