# Singleton row: who publishes Fitora, as its legal pages name it (Superadmin →
# Identité, Web::LegalHelper), and which default e-mail templates the seed has
# already created (db/seeds/mail_templates.rb).
class PlatformSetting < ApplicationRecord
  IDENTITY_FIELDS = %i[legal_name address city tax_id phone email website].freeze

  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  validates(*IDENTITY_FIELDS, length: { maximum: 200 })

  before_validation { IDENTITY_FIELDS.each { |field| self[field] = self[field].to_s.strip.presence } }

  # The one and only row, created on first access.
  def self.current
    first || create!
  end

  # What the legal pages need before they can name a publisher.
  def identity_complete? = legal_name.present? && tax_id.present?
end
