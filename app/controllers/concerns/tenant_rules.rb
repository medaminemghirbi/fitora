# Who may do what, in which salle — the rules every staff-facing controller
# applies, whichever front end the request came from. Included by
# Api::V1::BaseController (bearer JWT, answers in JSON) and by
# Web::BaseController (session cookie, answers with pages and redirects), so
# the API and the web UI cannot drift apart on a permission (MIGRATION_AUDIT
# §3.2).
#
# Only the questions live here. How a refusal is said — a JSON error or a
# redirect — is each base controller's own business.
#
# Expects `current_user`, `current_client` and `current_impersonator`.
module TenantRules
  extend ActiveSupport::Concern

  private

  # Never trust a company_id supplied by the client — always derive it from
  # the authenticated user: an admin runs several salles and a staff login may
  # be posted to several, so it is whichever one the session switched to
  # (Api::V1::CompaniesController#switch), or the one this request names and
  # #salle_for allowed (a tab's X-Company-Id, a web URL's salle), and for
  # staff only ever one it still works in (User#current_company). Never
  # confuse either with User#role == "superadmin", the Fitora platform
  # operator handled entirely by the console (Web::Superadmin::*).
  def current_company
    @current_company ||= current_user&.current_company
  end

  # One of this login's OWN salles, by id — or nil. The only door through
  # which a request may name a salle: checked against the login's workplaces
  # every time, never taken on trust.
  def salle_for(user, id)
    user.workplaces.find_by(id: id)
  end

  # For a member's login: the gyms they belong to, whose app they can use.
  def member_companies
    @member_companies ||= current_client&.companies&.to_a || []
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

  # An admin who has not clicked the link in their credentials e-mail yet
  # reaches nothing. A superadmin impersonating them is let through: they are
  # there to help, and the address is not theirs to confirm.
  def email_confirmation_required?
    return false if current_user.nil? || current_impersonator.present?

    current_user.email_confirmation_pending?
  end

  # The same for the first sign-in: the generated password replaced and the
  # terms accepted, which are the admin's to do and nobody else's.
  def first_sign_in_required?
    return false if current_user.nil? || current_impersonator.present?

    current_user.first_sign_in_pending?
  end
end
