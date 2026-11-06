# What a Fitora superadmin does for a gym: open its account, send its admin the
# credentials, suspend or restore its access, set a salle's currency and
# language, and step inside to help.
# Called by the superadmin console (Web::Superadmin::CompaniesController). The
# audit-log actions are named as the API's were.
module SuperadminActions
  module_function

  # A gym's account, opened: its first salle and its admin's login, with a
  # generated password, both or neither. Raises ActiveRecord::RecordInvalid.
  #
  # Returns the company and whether the credentials left: the account exists
  # either way, and the console offers to send them again (#send_credentials).
  Opened = Struct.new(:company, :credentials_sent, keyword_init: true)

  def create_company(company_attributes, admin_attributes, by:)
    admin = User.new(admin_attributes.to_h.symbolize_keys.merge(role: :admin, locale: company_attributes[:locale]))
    password = nil
    company = Company.transaction do
      password = admin.issue_temporary_password!
      Company.open!(admin: admin, attributes: company_attributes).tap do |opened|
        AuditLog.record!(company: opened, user: by, action: "superadmin.company_created", auditable: opened, metadata: { admin_email: admin.email })
      end
    end
    Opened.new(company: company, credentials_sent: deliver_credentials(admin, company, password))
  end

  # A new generated password and, while the address is unconfirmed, a new link,
  # by e-mail: the first mail never arrived, or was lost. Only until the admin
  # has chosen their own password, which this must never overwrite: from then
  # on, "mot de passe oublié" is theirs. Returns whether the mail left.
  def send_credentials(company, by:)
    admin = company.admin
    raise ApplicationRecord::Refused, "This admin has already chosen a password." unless admin.must_change_password?

    sent = deliver_credentials(admin, company, admin.issue_temporary_password!)
    AuditLog.record!(company: company, user: by, action: "superadmin.credentials_sent", auditable: company, metadata: { admin_email: admin.email, sent: sent })
    sent
  end

  # Delivered now rather than by a job: a queued mail would leave the password
  # in Redis until it is sent. Any failure here is reported and answered with
  # false, since the account is already saved and the console can send again.
  def deliver_credentials(admin, company, password)
    return false unless ActionMailer::Base.perform_deliveries

    token = admin.email_verified? ? nil : admin.generate_email_verification_token!
    AccountMailer.account_credentials(admin, company, password, token).deliver_now
    admin.update!(credentials_sent_at: Time.current)
    true
  rescue StandardError => e
    Rails.error.report(e, handled: true, context: { admin_id: admin.id })
    false
  end

  # Closes the account: every salle the admin runs, at once. The admin and their
  # team are signed out here and now, on the web and on the app, and SignIn
  # refuses them until it is restored. Members keep their own app, and nothing
  # is deleted. A superadmin can still step inside. Doing it twice changes nothing.
  def suspend_access(company, by:)
    admin = company.admin
    return if admin.access_suspended_at?

    admin.update!(access_suspended_at: Time.current)
    audit_access(company, "superadmin.access_suspended", by)
    User.where(id: admin.salle_staff_members.select(:user_id)).or(User.where(id: admin.id)).find_each(&:revoke_all_tokens!)
  end

  # Opens it again: everyone signs in as usual.
  def restore_access(company, by:)
    admin = company.admin
    return unless admin.access_suspended_at?

    admin.update!(access_suspended_at: nil)
    audit_access(company, "superadmin.access_restored", by)
  end

  def audit_access(company, action, by)
    AuditLog.record!(company: company, user: by, action: action, auditable: company, metadata: { admin_email: company.admin.email })
  end

  # Tenant-wide display settings a superadmin controls on the company's
  # behalf: the app language and the display currency. Returns whether they
  # saved.
  def update_settings(company, attrs, by:)
    return false unless company.update(attrs)

    AuditLog.record!(
      company: company, user: by, action: "superadmin.settings_updated",
      auditable: company, metadata: { currency: company.currency, locale: company.locale }
    )
    true
  end

  # Stepping inside a gym's admin account, marked with who is really there.
  # Returns the admin, or nil when the gym has none.
  def impersonate(company, by:)
    admin = company.admin
    return nil if admin.nil?

    AuditLog.record!(
      company: company, user: admin, action: "superadmin.impersonation_started",
      auditable: company, metadata: { superadmin_id: by.id, superadmin_email: by.email }
    )
    admin
  end
end
