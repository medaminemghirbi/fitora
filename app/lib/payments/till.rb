module Payments
  # One day at the till, in the gym's own time: every payment taken (and
  # those since refunded), what came in by each method and through each
  # login, and the drawers closed that day (CashClosing). Narrowed to one
  # login with `user:` — a desk that may take money but not read the gym's
  # takings sees its own drawer only.
  #
  # A refunded payment is not counted on the day it was taken: the money
  # went back, so neither the takings nor the drawer should hold it.
  class Till
    attr_reader :date

    def initialize(company, date:, user: nil)
      @company = company
      @date = date
      @user = user
    end

    def payments
      @payments ||= begin
        scope = @company.payments.where(paid_at: date.in_time_zone.all_day, status: %i[paid refunded])
        scope = scope.where(created_by: @user) if @user
        scope.includes(:client, :created_by, contract: :contract_type, booking: { session: :activity }).order(:paid_at).to_a
      end
    end

    def taken
      payments.select(&:paid?)
    end

    def refunded
      payments.select(&:refunded?)
    end

    def total
      taken.sum(&:amount)
    end

    # Every selectable method, in the order the desk picks them, with what
    # came in by it — zero included, so the strip always reads the same.
    def by_method
      sums = taken.group_by(&:payment_method).transform_values { |rows| rows.sum(&:amount) }
      Payment::SELECTABLE_METHODS.index_with { |method| sums.fetch(method, 0) }
    end

    # Per login: how many payments, how much, how much of it in cash, and
    # the drawer they closed, if they did. Payments nobody is recorded as
    # taking (imports, the API) come under nil.
    def by_staff
      rows = taken.group_by(&:created_by).map do |user, payments|
        {
          user: user, count: payments.size, total: payments.sum(&:amount),
          cash: payments.select(&:cash?).sum(&:amount), closing: user && closings_by_user[user.id]
        }
      end
      closed_without_payments = closings.reject { |c| rows.any? { |row| row[:user]&.id == c.closed_by_id } }
      rows += closed_without_payments.map { |c| { user: c.closed_by, count: 0, total: 0, cash: 0, closing: c } }
      rows.sort_by { |row| row[:user]&.first_name.to_s }
    end

    # What `user`'s drawer should hold.
    def expected_cash(user)
      taken.select { |payment| payment.cash? && payment.created_by_id == user.id }.sum(&:amount)
    end

    def closings
      @closings ||= begin
        scope = @company.cash_closings.where(business_date: date).includes(:closed_by)
        scope = scope.where(closed_by: @user) if @user
        scope.to_a
      end
    end

    def closing_for(user)
      closings_by_user[user.id]
    end

    private

    def closings_by_user
      @closings_by_user ||= closings.index_by(&:closed_by_id)
    end
  end
end
