# The fixed set of currencies a company can display. There is no superadmin UI
# to edit this list — it's a code catalog.
# `symbol` is what the app shows next to amounts (see the frontend MoneyPipe
# and CURRENCIES const, which mirror this list); `name` is the English label
# used in backend-only contexts (audit metadata) and as the i18n fallback —
# the frontend translates the display name via the `currency.<CODE>` keys.
module CurrencyCatalog
  CATALOG = {
    "TND" => { symbol: "DT",   name: "Tunisian Dinar" },
    "MAD" => { symbol: "DH",   name: "Moroccan Dirham" },
    "DZD" => { symbol: "DA",   name: "Algerian Dinar" },
    "EGP" => { symbol: "E£",   name: "Egyptian Pound" },
    "EUR" => { symbol: "€",    name: "Euro" },
    "USD" => { symbol: "$",    name: "US Dollar" },
    "GBP" => { symbol: "£",    name: "Pound Sterling" },
    "CHF" => { symbol: "CHF",  name: "Swiss Franc" },
    "CAD" => { symbol: "CA$",  name: "Canadian Dollar" },
    "SAR" => { symbol: "SAR",  name: "Saudi Riyal" },
    "AED" => { symbol: "AED",  name: "UAE Dirham" },
    "QAR" => { symbol: "QAR",  name: "Qatari Riyal" },
    "XOF" => { symbol: "FCFA", name: "West African CFA Franc" }
  }.freeze

  CODES = CATALOG.keys.freeze

  def self.options
    CATALOG.map { |code, meta| { code: code, symbol: meta[:symbol], name: meta[:name] } }
  end

  def self.symbol(code)
    CATALOG.dig(code.to_s, :symbol) || code.to_s
  end

  def self.valid?(code)
    CATALOG.key?(code.to_s)
  end
end
