# One admin account a mailing went to, and how that went (DeliverMailingJob).
class MailingRecipient < ApplicationRecord
  belongs_to :mailing
  belongs_to :user

  enum :status, { pending: 0, sent: 1, failed: 2 }
end
