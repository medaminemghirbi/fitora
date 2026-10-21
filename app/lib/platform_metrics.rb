# What Fitora itself looks like this month: GET /api/v1/superadmin/metrics
# and the web UI's superadmin overview, from one definition
# (MIGRATION_AUDIT §3.2). Moved here unchanged from
# Api::V1::Superadmin::MetricsController.
#
# Deliberately small. A platform dashboard grows statistics nobody acts on
# faster than anything else in a product, so every number here has a
# decision behind it: are gyms still signing up, are they still using it, is
# anyone locked out, and is anyone not paying.
#
# Cross-tenant by design — the superadmin's is the one namespace that is,
# and it reads aggregates only. No member, booking or payment row from any
# gym is reachable from here (see docs/PERMISSIONS.md §6).
module PlatformMetrics
  module_function

  def call
    {
      companies: companies,
      members: members,
      activity: activity,
      money: money,
      recent_companies: recent_companies
    }
  end

  def companies
    total = Company.count
    # "Open" means the door is open, not that the row exists: a suspended or
    # unpaid gym is still a company and still counted in `total`, and it is
    # the gap between the two that matters.
    #
    # Locked is the remainder rather than a count of its own, so the two
    # always add up to the total. A company with no subscription row at all
    # counts as locked — the same way the company list reports it
    # (SuperadminCompanySerializer#access_open). Access is the account's, so
    # a salle is open when its admin's account is.
    open = Company.joins(admin: :subscription).where(subscriptions: { active: true }).count

    {
      total: total,
      open: open,
      locked: total - open,
      new_this_month: Company.where(created_at: current_month).count,
      new_last_month: Company.where(created_at: last_month).count,
      # Accounts per plan — what Fitora actually sells.
      plans: SubscriptionPrice::PLANS.index_with { |plan| Subscription.where(plan: plan).count }
    }
  end

  def members
    {
      total: Client.count,
      new_this_month: Client.where(created_at: current_month).count
    }
  end

  # Whether gyms are actually running on this, as opposed to having signed
  # up. Sessions and bookings in the last 30 days is the honest version of
  # that question.
  def activity
    since = 30.days.ago

    {
      sessions_last_30_days: Session.where(starts_at: since..Time.current).count,
      bookings_last_30_days: Booking.where(created_at: since..).count,
      companies_with_activity: Session.where(starts_at: since..Time.current).distinct.count(:company_id)
    }
  end

  # Fitora's own money, not any gym's takings. Amounts are cents in the
  # platform's reference currency; a gym billed in another currency is
  # counted at its own tariff, which is what it will actually be invoiced.
  def money
    # The money in: invoices paid this month (a bill still to pay is not).
    invoiced = Invoice.paid.where(paid_at: current_month).sum(:amount_cents)
    arrears = Subscription.includes(:invoices, admin: :companies).sum { |s| s.arrears_cents }

    {
      invoiced_this_month_cents: invoiced,
      arrears_cents: arrears,
      currency: SubscriptionPrice::REFERENCE_CURRENCY
    }
  end

  def recent_companies
    Company.includes(admin: :subscription).order(created_at: :desc).limit(5).map do |company|
      {
        id: company.id,
        name: company.name,
        city: company.city,
        admin_name: company.admin.full_name,
        created_at: company.created_at,
        access_open: company.subscription&.active || false
      }
    end
  end

  def current_month
    Time.current.beginning_of_month..Time.current
  end

  def last_month
    (Time.current - 1.month).beginning_of_month..(Time.current - 1.month).end_of_month
  end
end
