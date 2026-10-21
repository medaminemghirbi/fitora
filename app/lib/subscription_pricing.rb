# What each plan (Starter, Pro) costs per month in each currency, plus the
# global annual-billing discount: what GET and PATCH
# /api/v1/superadmin/subscription_pricing answer and what the web UI's
# superadmin pricing page shows, from one definition (MIGRATION_AUDIT §3.2).
# Moved here unchanged from Api::V1::Superadmin::SubscriptionPricingController.
# Prices are informational — payment happens outside the app.
module SubscriptionPricing
  module_function

  def currency(param)
    param.presence || SubscriptionPrice::REFERENCE_CURRENCY
  end

  def payload(currency)
    discount = PlatformSetting.current.annual_discount_percent
    plans = SubscriptionPrice::PLANS.map do |plan|
      price = SubscriptionPrice.for(currency, plan: plan)
      {
        plan: plan,
        monthly_cents: price.monthly_cents,
        annual_cents: price.annual_cents(discount),
        # How many accounts this price is charged to today.
        accounts_count: accounts_on(plan, currency)
      }
    end

    {
      currencies: CurrencyCatalog::CODES,
      currency: currency,
      annual_discount_percent: discount,
      plans: plans,
      companies_count: Company.where(currency: currency).count
    }
  end

  # `plans`: { "starter" => monthly_cents, "pro" => … } — either may come
  # alone; an omitted one is left as it is. `discount`: nil leaves it.
  # Returns the error messages, empty when everything saved.
  def update(currency, plans:, discount:)
    setting = PlatformSetting.current
    setting.annual_discount_percent = discount unless discount.nil?

    rows = plans.map do |plan, monthly_cents|
      price = SubscriptionPrice.for(currency, plan: plan)
      price.monthly_cents = monthly_cents
      price
    end

    unless rows.all?(&:valid?) && setting.valid?
      return rows.flat_map { |r| r.errors.full_messages } + setting.errors.full_messages
    end

    ActiveRecord::Base.transaction do
      rows.each(&:save!)
      setting.save!
    end
    []
  end

  # An account pays in its first salle's currency (Subscription#currency).
  def accounts_on(plan, currency)
    Subscription.where(plan: plan).includes(admin: :companies).count { |s| s.currency == currency }
  end
end
