# Singleton row of platform-wide knobs a Fitora superadmin controls: the
# annual-billing discount percentage shown (informationally) on the admin's
# subscription page, the currency the plans' prices are set in — every
# other one is a conversion (SubscriptionPrice.for) — and what heads
# Fitora's invoices: who issues them, the TVA rate and the timbre fiscal.
class PlatformSetting < ApplicationRecord
  # What an invoice says of its issuer, in the order it prints it.
  ISSUER_FIELDS = %i[legal_name address city tax_id phone email website].freeze

  validates :annual_discount_percent, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
  validates :price_currency, inclusion: { in: CurrencyCatalog::CODES }
  validates :vat_percent, numericality: { greater_than_or_equal_to: 0, less_than: 100 }
  validates :stamp_duty_millimes, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  validates(*ISSUER_FIELDS, length: { maximum: 200 })

  before_validation { ISSUER_FIELDS.each { |field| self[field] = self[field].to_s.strip.presence } }

  # The one and only row, created on first access.
  def self.current
    first || create!
  end

  def issuer = ISSUER_FIELDS.index_with { |field| self[field] }.compact.stringify_keys

  # An invoice may be frozen with its issuer once it has a name and a
  # matricule fiscal; until then it reads whatever is set when printed.
  def issuer_complete? = legal_name.present? && tax_id.present?
end
