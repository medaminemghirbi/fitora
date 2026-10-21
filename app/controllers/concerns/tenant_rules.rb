# Who may do what, in which salle — the rules every staff-facing controller
# applies, whichever front end the request came from. Included by
# Api::V1::BaseController (bearer JWT, answers in JSON) and by
# Web::BaseController (session cookie, answers with pages and redirects), so
# the API and the web UI cannot drift apart on a permission, a plan gate or
# the lock (MIGRATION_AUDIT §3.2).
#
# Only the questions live here. How a refusal is said — a JSON error or a
# redirect — is each base controller's own business.
#
# Expects `current_user`, `current_client` and `current_impersonator`.
module TenantRules
  extend ActiveSupport::Concern

  # The only actions a locked company's admin can still reach — enough to see
  # their status, and nothing that operates the gym. Staff get no exceptions
  # at all: once the free trial expires, only the admin has any access, and
  # only to this much, until a platform superadmin manually grants access
  # again (Api::V1::Superadmin::CompaniesController#update_subscription).
  # Keyed by area, so each front end names the same three things.
  ADMIN_ALLOWED_WHEN_LOCKED = {
    # A locked admin still sees what they owe and can download the invoices
    # they already have: the way out is settling, and both of these are how
    # they work out what settling means.
    subscription: %w[show],
    invoices: %w[index show],
    # Their salles are still theirs to see and move between while the
    # account is locked.
    companies: %w[show index switch]
  }.freeze

  private

  # Never trust a company_id supplied by the client — always derive it from
  # the authenticated user: an admin runs several salles and a staff login may
  # be posted to several, so it is whichever one the session switched to
  # (Api::V1::CompaniesController#switch), or the one this request names and
  # #salle_for allowed (a tab's X-Company-Id, a web URL's salle), and for
  # staff only ever one it still works in (User#current_company). Never
  # confuse either with User#role == "superadmin", the Fitora platform
  # operator handled entirely by Api::V1::Superadmin::*.
  def current_company
    @current_company ||= current_user&.current_company
  end

  # One of this login's OWN salles, by id — or nil. The only door through
  # which a request may name a salle: checked against the login's workplaces
  # every time, never taken on trust.
  def salle_for(user, id)
    user.workplaces.find_by(id: id)
  end

  # For a member's login: the gyms whose app they can use — the ones they
  # belong to whose account includes the member app (a paid Pro period). A
  # Starter or trial gym's members have no app to open.
  def member_companies
    @member_companies ||= (current_client&.companies&.includes(admin: { subscription: :invoices }) || []).select(&:member_app?)
  end

  def current_staff_member
    return nil unless current_user&.staff?

    @current_staff_member ||= current_user.staff_member
  end

  # True for the admin (always) or for staff whose role grants this
  # capability — the only two ways in.
  def capability?(capability)
    return true if current_user.admin?

    current_staff_member&.active? && current_staff_member.can?(capability) || false
  end

  # Anyone with a seat in the company can see the calendar — the schedule is
  # shared operational context for every role.
  def staff_access?
    current_user.admin? || current_staff_member&.active? || false
  end

  # Read access to the reference data a session is built from (the activity
  # catalogue, the opening hours): whoever owns that data (`capability`) *plus*
  # anyone who can edit the schedule (`:sessions`), since you can't plan a
  # week of sessions without seeing the options.
  def schedule_reference_access?(capability)
    return true if current_user.admin?

    current_staff_member&.active? &&
      (current_staff_member.can?(capability) || current_staff_member.can?(:sessions)) || false
  end

  # Pro's tools (several salles, custom roles, branding, import / export):
  # open on a paid Pro period, refused on Starter and the trial.
  def pro_access?
    current_company&.pro_features? || false
  end

  # An admin who signed up and has not clicked the link yet reaches nothing
  # past sign-up. A superadmin impersonating them is let through: they are
  # there to help, and the address is not theirs to confirm.
  def email_confirmation_required?
    return false if current_user.nil? || current_impersonator.present?

    current_user.email_confirmation_pending?
  end

  # The subscription that shuts this request out, or nil. A member's own
  # login is never shut out (their gym's status is not theirs to see), nor is
  # the platform superadmin; an admin is let into ADMIN_ALLOWED_WHEN_LOCKED.
  def locking_subscription(area: nil, action: nil)
    return nil if current_client || current_user.superadmin?

    subscription = current_company&.subscription
    return nil unless subscription&.locked?
    return nil if current_user.admin? && area && ADMIN_ALLOWED_WHEN_LOCKED[area]&.include?(action.to_s)

    subscription
  end

  # Why the door is shut, in words the person reading them can act on.
  # Staff are told to talk to their admin whatever the reason: the money is
  # not theirs to settle and the detail is not theirs to see.
  def lock_message(subscription)
    return "This gym's account is locked. Contact your gym's admin." unless current_user.admin?

    reason = subscription.lock_reason
    if reason == :unpaid && subscription.trial?
      "Your free trial has ended. Choose Starter or Pro and settle with Fitora to reopen access."
    elsif reason == :unpaid
      "The period you paid for has run out. Access closed #{Subscription::GRACE_DAYS} days later; settle with Fitora to reopen it."
    else
      "Your access has been suspended by Fitora. Get in touch to find out why."
    end
  end
end
