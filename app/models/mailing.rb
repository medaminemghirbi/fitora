# One sending from the console: its own copy of the text, who sent it, and who
# it went to (AdminMailing.start).
class Mailing < ApplicationRecord
  include MailContent

  belongs_to :sent_by, class_name: "User", optional: true
  has_many :recipients, class_name: "MailingRecipient", dependent: :delete_all

  # The superadmin console's table of sendings.
  console_searchable attributes: %i[subject body created_at]
end
