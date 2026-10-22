# What each plan (Starter, Pro) costs per month, plus the global annual
# billing discount: what GET and PATCH /api/v1/superadmin/subscription_pricing
# answer and what the web UI's superadmin pricing page shows, from one
# definition (MIGRATION_AUDIT §3.2).
#
# The prices are set in one currency (PlatformSetting#price_currency) and
# every other is a conversion of them at the day's rate, rounded to whole
# units (SubscriptionPrice.for). Prices are informational — payment happens
# outside the app.
module SubscriptionPricing
  module_function

  # The currency asked for when Fitora bills in it; the price currency
  # otherwise — never one made up in a URL.
  def currency(param)
    CurrencyCatalog.valid?(param) ? param.to_s : SubscriptionPrice.price_currency
  end

  # The plans in `currency` — the prices themselves when it is the price
  # currency, their conversion otherwise — and what each one comes to in
  # every currency Fitora bills in, with the rate it was converted at.
  def payload(currency)
    discount = PlatformSetting.current.annual_discount_percent
    price_currency = SubscriptionPrice.price_currency
    rates = ExchangeRate.table
    companies = Company.group(:currency).count

    {
      currencies: CurrencyCatalog::CODES,
      currency: currency,
      price_currency: price_currency,
      annual_discount_percent: discount,
      plans: SubscriptionPrice::PLANS.map do |plan|
        price = SubscriptionPrice.for(currency, plan: plan)
        # How many accounts are on this plan today, whatever they pay in.
        { plan: plan, monthly_cents: price.monthly_cents, annual_cents: price.annual_cents(discount), accounts_count: Subscription.where(plan: plan).count }
      end,
      companies_count: companies.fetch(currency, 0),
      rates_fetched_at: ExchangeRate.fetched_at,
      rates_source: ExchangeRate::SOURCE_NAME,
      conversions: CurrencyCatalog::CODES.map do |code|
        {
          currency: code,
          # Units of `code` one unit of the price currency buys.
          rate: ExchangeRate.rate(from: price_currency, to: code, table: rates).round(6),
          monthly_cents: SubscriptionPrice::PLANS.index_with { |plan| SubscriptionPrice.for(code, plan: plan).monthly_cents },
          companies_count: companies.fetch(code, 0)
        }
      end
    }
  end

  # Sets the prices in `currency`, which becomes the price currency.
  # `plans`: { "starter" => monthly_cents, "pro" => … } — a plan left out
  # keeps its price, converted into `currency` when that is a new one.
  # `discount`: nil leaves it. Returns the error messages, empty when
  # everything saved.
  def update(currency, plans:, discount:)
    setting = PlatformSetting.current

    rows = SubscriptionPrice::PLANS.map do |plan|
      kept = SubscriptionPrice.for(currency, plan: plan).monthly_cents
      row = SubscriptionPrice.find_or_initialize_by(currency: currency, plan: plan)
      row.monthly_cents = plans.fetch(plan) { kept }
      row
    end
    setting.price_currency = currency
    setting.annual_discount_percent = discount unless discount.nil?

    unless rows.all?(&:valid?) && setting.valid?
      return rows.flat_map { |r| r.errors.full_messages } + setting.errors.full_messages
    end

    ActiveRecord::Base.transaction do
      rows.each(&:save!)
      setting.save!
    end
    []
  end
end
