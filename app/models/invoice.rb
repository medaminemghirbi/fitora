# One period of Fitora access, billed and — once the money is in — paid.
#
# Payment happens off-app. A paid invoice (paid_at set) is the proof that
# money arrived: a Fitora superadmin confirms it, and it lands in the
# admin's account to download. A change of plan bills the account at once
# with an invoice to pay (paid_at nil, at most one per account), which the
# same confirmation then settles (Subscription#bill!, #issue_invoice!). It
# covers the account — every salle the admin runs — not one gym.
#
# Only paid invoices say anything about access: "paid until", the trial and
# arrears read them alone (Subscription#latest_invoice).
#
# Everything about the subscription that used to be stored is read from
# these: "paid until" is the latest period_end, arrears are the periods
# without a row.
class Invoice < ApplicationRecord
  belongs_to :subscription
  belongs_to :issued_by, class_name: "User", optional: true

  enum :billing_period, Subscription::BILLING_PERIODS, prefix: :covers
  # The plan this period was bought on, frozen at issue like the amount.
  # nil on the trial's free period only: nothing was bought.
  attribute :plan, :string
  enum :plan, Subscription::PLANS, prefix: :on, validate: { allow_nil: true }
  validates :plan, presence: true, unless: :trial?

  validates :number, presence: true, uniqueness: true
  validates :period_start, :period_end, :issued_at, presence: true
  validates :amount_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :currency, presence: true
  validate :period_runs_forwards

  delegate :admin, :billing_company, to: :subscription

  scope :paid, -> { where.not(paid_at: nil) }
  scope :due, -> { where(paid_at: nil) }
  scope :chronological, -> { order(:period_start) }
  scope :newest_first, -> { order(period_start: :desc) }
  scope :covering, ->(date) { where(period_start: ..date).where(period_end: date..) }

  # The superadmin console's invoices table: by number or account, sorted by
  # issue date, amount or period, filtered on what was paid, plan and period.
  console_searchable attributes: %i[number issued_at amount_cents period_start paid_at trial plan billing_period],
                     associations: %i[subscription]

  def amount
    amount_cents / 100.0
  end

  def paid?
    paid_at.present?
  end

  def due?
    !paid?
  end

  def covers?(date)
    (period_start..period_end).cover?(date)
  end

  # FIT-2026-0042: the year it was issued in, then a counter within that
  # year, from one counter row per year (invoice_sequences). Atomic under
  # concurrent callers,
  # and inside the caller's transaction, so a rolled-back invoice does not
  # leave a gap.
  def self.next_number(now: Time.current)
    year = now.year
    sequence = connection.select_value(sanitize_sql_array([ <<~SQL, year ]))
      INSERT INTO invoice_sequences (year, last_value) VALUES (?, 1)
      ON CONFLICT (year) DO UPDATE SET last_value = invoice_sequences.last_value + 1
      RETURNING last_value
    SQL
    format("FIT-%<year>d-%<sequence>04d", year: year, sequence: sequence)
  end

  private

  def period_runs_forwards
    return if period_start.blank? || period_end.blank?
    return if period_end >= period_start

    errors.add(:period_end, "must not be before the period starts")
  end
end
