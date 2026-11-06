# A text the superadmin reuses in the console's mailing (AdminMailing).
class MailTemplate < ApplicationRecord
  include MailContent

  before_validation { self.name = name.to_s.squish }

  validates :name, presence: true, uniqueness: { case_sensitive: false }, length: { maximum: 100 }

  # The superadmin console's templates table.
  console_searchable attributes: %i[name subject updated_at]
end
