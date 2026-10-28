# The end of a shift at the desk: one login, one salle, one day. What the
# drawer should hold — the cash payments that login took that day — beside
# what was counted in it, so a difference shows the day it happens rather
# than at the end of the month.
#
# Counting again the same day replaces the count: a closing is the drawer
# as it was last counted, not a log of every attempt.
class CashClosing < ApplicationRecord
  belongs_to :company
  belongs_to :closed_by, class_name: "User"

  validates :business_date, presence: true
  validates :currency, presence: true
  validates :expected_cash, :counted_cash, numericality: { greater_than_or_equal_to: 0 }
  validates :closed_by_id, uniqueness: { scope: %i[company_id business_date] }

  # Closes (or counts again) `user`'s drawer for `date` and returns it.
  # `counted` is what the desk typed.
  def self.close!(company:, user:, date:, counted:, notes: nil)
    raise Refused.new("A day still to come cannot be closed.", key: "cash.errors.future_day") if date > Date.current

    amount = parse_amount(counted)
    expected = Payments::Till.new(company, date: date, user: user).expected_cash(user)
    transaction do
      closing = lock.find_or_initialize_by(company: company, closed_by: user, business_date: date)
      closing.update!(expected_cash: expected, counted_cash: amount, currency: company.currency, notes: notes.presence)
      closing
    end
  end

  def self.parse_amount(value)
    amount = BigDecimal(value.to_s.tr(",", ".").strip)
    raise ArgumentError if amount.negative?

    amount.round(2)
  rescue ArgumentError, TypeError
    raise Refused.new("Type the amount counted in the drawer.", key: "cash.errors.invalid_amount")
  end
  private_class_method :parse_amount

  # Counted less expected: positive is more cash than the books say.
  def difference
    counted_cash - expected_cash
  end
end
