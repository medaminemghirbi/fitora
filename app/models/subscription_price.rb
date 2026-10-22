# What one plan costs per month. The superadmin sets it once, in the
# currency of their choosing (PlatformSetting#price_currency: 60 EUR); a gym
# sees it converted into its own Company#currency at the day's rate, rounded
# to whole units (202 TND) — ExchangeRate.convert. Only the price
# currency's rows are stored. The year is twelve months less the
# platform-wide annual discount (PlatformSetting). Payment happens outside
# the app — the superadmin just sets the numbers the admin sees.
class SubscriptionPrice < ApplicationRecord
  # The price currency of a fresh install (PlatformSetting's default), and
  # the currency DEFAULT_MONTHLY_CENTS are in.
  REFERENCE_CURRENCY = "TND"

  PLANS = Subscription::PLANS.values.freeze

  # A starting point only, for a plan never priced yet; the superadmin
  # reprices each one from there.
  DEFAULT_MONTHLY_CENTS = { "starter" => 16_500, "pro" => 24_900 }.freeze

  validates :currency, presence: true, inclusion: { in: CurrencyCatalog::CODES }
  validates :currency, uniqueness: { scope: :plan }
  validates :plan, inclusion: { in: PLANS }
  validates :monthly_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  def self.price_currency = PlatformSetting.current.price_currency

  # The price the superadmin sets: the plan's row in the price currency,
  # created the first time at the default, converted from the currency
  # that default is in. An unknown plan reads as Starter rather than
  # raising on bad input.
  def self.base(plan)
    plan = PLANS.include?(plan.to_s) ? plan.to_s : PLANS.first
    currency = price_currency

    find_or_create_by!(currency: currency, plan: plan) do |row|
      row.monthly_cents = ExchangeRate.convert(DEFAULT_MONTHLY_CENTS.fetch(plan), from: REFERENCE_CURRENCY, to: currency)
    end
  end

  # What a plan costs a month in `currency` (the price currency when none
  # is given): the price itself there, its conversion anywhere else — a
  # read-only record that is never saved.
  def self.for(currency, plan:)
    base = base(plan)
    currency = CurrencyCatalog.valid?(currency) ? currency.to_s : base.currency
    return base if currency == base.currency

    new(currency: currency, plan: base.plan, monthly_cents: ExchangeRate.convert(base.monthly_cents, from: base.currency, to: currency)).tap(&:readonly!)
  end

  # Twelve months less the annual discount, rounded to the cent.
  def annual_cents(discount = PlatformSetting.current.annual_discount_percent)
    (monthly_cents * 12 * (100 - discount) / 100.0).round
  end
end
