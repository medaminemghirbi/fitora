# What Fitora itself looks like this month: the superadmin console's
# overview (Web::Superadmin::OverviewController).
#
# Deliberately small. A platform dashboard grows statistics nobody acts on
# faster than anything else in a product, so every number here has a
# decision behind it: are gyms joining, have they finished opening their
# account, and are they using it.
#
# Cross-tenant by design — the superadmin's is the one namespace that is,
# and it reads aggregates only. No member, booking or payment row from any
# gym is reachable from here (see docs/PERMISSIONS.md §6).
# rubocop:disable Fitora/UnscopedTenantQuery
module PlatformMetrics
  module_function

  def call
    {
      companies: companies,
      members: members,
      activity: activity,
      recent_companies: recent_companies
    }
  end

  def companies
    {
      total: Company.count,
      # The ones whose admin still has the generated password: the first
      # sign-in Fitora may have to chase.
      awaiting_activation: Company.joins(:admin).where(users: { must_change_password: true }).count,
      new_this_month: Company.where(created_at: current_month).count,
      new_last_month: Company.where(created_at: last_month).count
    }
  end

  def members
    {
      total: Client.count,
      new_this_month: Client.where(created_at: current_month).count
    }
  end

  # Whether gyms are actually running on this, as opposed to having an
  # account. Sessions and bookings in the last 30 days is the honest version
  # of that question.
  def activity
    since = 30.days.ago

    {
      sessions_last_30_days: Session.where(starts_at: since..Time.current).count,
      bookings_last_30_days: Booking.where(created_at: since..).count,
      companies_with_activity: Session.where(starts_at: since..Time.current).distinct.count(:company_id)
    }
  end

  def recent_companies
    Company.includes(:admin).order(created_at: :desc).limit(5).map do |company|
      {
        id: company.id,
        name: company.name,
        city: company.city,
        admin_name: company.admin.full_name,
        created_at: company.created_at,
        activation_state: company.admin.activation_state
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
# rubocop:enable Fitora/UnscopedTenantQuery
