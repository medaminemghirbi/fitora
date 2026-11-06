# A subject and a text with variables (AdminMailing): a reusable template, or
# what a mailing sent. A variable nobody can fill is refused here, before it
# reaches a customer as it was typed.
module MailContent
  extend ActiveSupport::Concern

  MAX_SUBJECT = 200
  MAX_BODY = 20_000

  included do
    before_validation { self.subject = subject.to_s.squish }

    validates :subject, presence: true, length: { maximum: MAX_SUBJECT }
    validates :body, presence: true, length: { maximum: MAX_BODY }
    validate :only_known_variables
  end

  def unknown_variables
    "#{subject} #{body}".scan(AdminMailing::PLACEHOLDER).flatten.uniq - AdminMailing::VARIABLES
  end

  private

  def only_known_variables
    errors.add(:body, :unknown_variable, message: "uses a variable that does not exist") if unknown_variables.any?
  end
end
