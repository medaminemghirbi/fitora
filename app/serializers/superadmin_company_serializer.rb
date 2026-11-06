class SuperadminCompanySerializer
  def initialize(company)
    @company = company
  end

  def as_json(*)
    {
      id: company.id,
      name: company.name,
      address: company.address,
      city: company.city,
      country: company.country,
      phone: company.phone,
      currency: company.currency,
      currency_symbol: company.currency_symbol,
      locale: company.locale,
      active: company.active,
      created_at: company.created_at,
      admin: admin_json,
      # Every salle under this admin, this one included.
      account_companies: account_companies,
      # What the gym is actually doing with Fitora: a gym with 180 members and
      # a full week of sessions is a different conversation from one that
      # opened its account and never came back.
      usage: usage
    }
  end

  private

  attr_reader :company

  def admin_json
    admin = company.admin
    {
      id: admin.id,
      full_name: admin.full_name,
      # Whole, not masked: it is where Fitora writes to its admin — Fitora's
      # own customer, not someone else's.
      email: admin.email,
      phone: admin.phone,
      companies_count: admin.companies.size,
      activation_state: admin.activation_state,
      access_suspended_at: admin.access_suspended_at,
      credentials_sent_at: admin.credentials_sent_at,
      email_verified_at: admin.email_verified_at,
      terms_accepted_at: admin.terms_accepted_at,
      must_change_password: admin.must_change_password
    }
  end

  def account_companies
    company.admin.companies.sort_by(&:created_at).map do |c|
      { id: c.id, name: c.name, city: c.city, current: c.id == company.id }
    end
  end

  def usage
    {
      clients: company.memberships.active.count,
      staff: company.staff_members.count,
      activities: company.activities.active.count,
      sessions_last_30_days: company.sessions.where(starts_at: 30.days.ago..).count,
      last_session_at: company.sessions.maximum(:starts_at)
    }
  end
end
