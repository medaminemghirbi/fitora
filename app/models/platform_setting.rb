# Singleton row of platform-wide knobs a Fitora superadmin controls: the
# annual-billing discount percentage shown (informationally) on the admin's
# subscription page, and the currency the plans' prices are set in — every
# other one is a conversion (SubscriptionPrice.for).
class PlatformSetting < ApplicationRecord
  validates :annual_discount_percent, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
  validates :price_currency, inclusion: { in: CurrencyCatalog::CODES }

  # The one and only row, created on first access.
  def self.current
    first || create!
  end
end
