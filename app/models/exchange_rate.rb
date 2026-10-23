# How many units of a currency one euro buys — one row per currency Fitora
# bills in (CurrencyCatalog), refreshed nightly from ExchangeRate-API's open
# endpoint (RefreshExchangeRatesJob). The euro is only the pivot: a price
# set in dinars converts to dirhams through it.
#
# Until a refresh has stored a currency's rate (a fresh install, the test
# suite, a source that has never answered), the snapshot below stands in, so
# a price can always be shown. A refresh that fails keeps the rates there
# were.
class ExchangeRate < ApplicationRecord
  SOURCE_URL = "https://open.er-api.com/v6/latest/EUR".freeze
  SOURCE_NAME = "ExchangeRate-API".freeze
  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 10

  # Units per euro on 22 October 2026, from the same source.
  SNAPSHOT = {
    "EUR" => 1, "TND" => 3.363395, "MAD" => 10.988794, "DZD" => 151.201601, "EGP" => 61.087552,
    "USD" => 1.123228, "GBP" => 0.838618, "CHF" => 0.926098, "CAD" => 1.5779, "SAR" => 4.212067,
    "AED" => 4.125017, "QAR" => 4.088513, "XOF" => 655.957
  }.freeze

  # The source answered with something that is not a full set of rates.
  class Unavailable < StandardError; end

  validates :currency, presence: true, uniqueness: true, inclusion: { in: CurrencyCatalog::CODES }
  validates :per_eur, numericality: { greater_than: 0 }

  # Every currency's units per euro: what is stored, the snapshot for the rest.
  def self.table
    SNAPSHOT.merge(pluck(:currency, :per_eur).to_h { |code, rate| [ code, rate.to_f ] })
  end

  # How many units of `to` one unit of `from` is worth.
  def self.rate(from:, to:, table: self.table)
    table.fetch(to.to_s) / table.fetch(from.to_s)
  end

  # An amount in cents of `from`, in cents of `to`. A price is rounded to
  # whole units (60 € → 202 DT, not 201.80 DT: a price a gym reads every
  # month); a total, to the cent.
  def self.convert(cents, from:, to:, round: :units)
    return cents if cents.nil? || from.to_s == to.to_s

    units = cents / 100.0 * rate(from: from, to: to)
    round == :units ? units.round * 100 : (units * 100).round
  end

  # When the rates in use were fetched; nil while only the snapshot stands.
  def self.fetched_at = maximum(:fetched_at)

  # Fetches today's rates and stores every currency Fitora bills in. Raises
  # Unavailable — storing nothing — unless each of them came back positive.
  def self.refresh!(now: Time.current)
    rates = fetch.fetch("rates", {}).slice(*CurrencyCatalog::CODES)
    unless rates.size == CurrencyCatalog::CODES.size && rates.values.all? { |rate| rate.is_a?(Numeric) && rate.positive? }
      raise Unavailable, "#{SOURCE_NAME} answered without every currency"
    end

    upsert_all(rates.map { |code, rate| { currency: code, per_eur: rate, fetched_at: now } }, unique_by: :currency)
    rates
  end

  def self.fetch
    uri = URI(SOURCE_URL)
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) do |http|
      http.request(Net::HTTP::Get.new(uri))
    end
    raise Unavailable, "#{SOURCE_NAME} answered #{response.code}" unless response.is_a?(Net::HTTPSuccess)

    body = JSON.parse(response.body)
    raise Unavailable, "#{SOURCE_NAME} answered #{body["result"].inspect}" unless body["result"] == "success"

    body
  rescue JSON::ParserError, SocketError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError => e
    raise Unavailable, "#{SOURCE_NAME}: #{e.class}: #{e.message}"
  end
  private_class_method :fetch
end
