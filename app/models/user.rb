class User < ApplicationRecord
  include UnmaskedEmail
  has_secure_password
  include PasswordResettable
  include EmailVerifiable
  include TokenVersioned
  include TwoFactor

  # A User is always staff: the Fitora-operator ("superadmin", opens every
  # company's account via /superadmin) or an in-gym account (admin, or staff —
  # the specific in-gym role lives on StaffMember).
  # Clients are business records the gym creates, never Users — see Client.
  enum :role, { admin: 0, staff: 1, superadmin: 2 }


  # An admin runs as many salles as they like (each a fully independent
  # tenant — its own clients, staff). active_company is which salle their
  # session is currently scoped to — see #current_company and
  # Api::V1::CompaniesController#switch.
  has_many :companies, foreign_key: :admin_id, inverse_of: :admin, dependent: :destroy
  # Everything across the salles an admin runs.
  has_many :salle_memberships, through: :companies, source: :memberships
  has_many :salle_staff_members, through: :companies, source: :staff_members
  belongs_to :active_company, class_name: "Company", optional: true
  # A staff login holds one record per salle it works in: a moderator the
  # admin posted to two salles has two, each with that salle's own role.
  # active_company picks which one the session is working in.
  has_many :staff_members, dependent: :destroy
  has_many :staffed_companies, through: :staff_members, source: :company
  has_many :notifications, as: :recipient, dependent: :destroy
  has_many :mailing_recipients, dependent: :delete_all

  before_validation { self.email = email.to_s.downcase.strip }

  # A password the person chose themselves is no longer the generated one,
  # whichever screen it came through: first sign-in, a reset, settings, the API.
  before_update(if: :will_save_change_to_password_digest?) { self.must_change_password = false unless @issuing_temporary_password }

  validates :first_name, :last_name, presence: true
  validates :email, presence: true, uniqueness: true,
                     format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :password, length: { minimum: 8 }, if: -> { new_record? || password.present? }
  validates :locale, inclusion: { in: %w[fr en ar] }

  scope :active, -> { where(active: true) }

  # Who an account is, to the superadmin console's tables: its name and
  # e-mail, whether it still has the generated password or is suspended, and
  # its salles' names.
  console_searchable attributes: %i[first_name last_name email must_change_password access_suspended_at], associations: %i[companies]

  def full_name
    "#{first_name} #{last_name}"
  end

  # Opened by a superadmin, and the address not confirmed yet: nothing opens
  # until it is. Admins only — see EmailVerifiable.
  def email_confirmation_pending?
    admin? && !email_verified?
  end

  # Signed in, and still to choose a password of their own or to accept the
  # terms (Web::FirstSignInsController): nothing else opens until they have.
  # Admins only: staff logins are the admin's to hand out, under their terms.
  def first_sign_in_pending?
    admin? && (must_change_password? || terms_accepted_at.nil?)
  end

  # A superadmin closed this account's access (SuperadminActions.suspend_access):
  # an admin's own account, or for staff the account of the salle they work in.
  # SignIn refuses them; a member's login is not concerned.
  def access_suspended?
    return access_suspended_at.present? if admin?

    staff_member&.company&.admin&.access_suspended_at.present?
  end

  # Where an account stands, for the superadmin: suspended, the address to
  # confirm, the first sign-in to make, or done.
  def activation_state
    return :suspended if access_suspended_at.present?
    return :awaiting_email if email_confirmation_pending?

    first_sign_in_pending? ? :awaiting_first_sign_in : :active
  end

  # Gives the login a generated password, which it must replace on first
  # sign-in, and returns it. Saves a new record, so it raises RecordInvalid
  # like any save!. The password is only ever in the mail that carries it.
  def issue_temporary_password!
    generated = SecureRandom.base58(16)
    @issuing_temporary_password = true
    update!(password: generated, must_change_password: true)
    generated
  ensure
    @issuing_temporary_password = false
  end

  # The salle this login is working in right now. An admin's is the one
  # they switched to; a staff login's is the salle of its current staff
  # record, which is never a salle it no longer works in — active_company
  # alone could still name one the admin has since withdrawn it from.
  def current_company
    return active_company if admin?

    staff_member&.company
  end

  # This staff login's record in the salle it is working in: the one for
  # active_company, else its first active post, else its first. nil for an
  # admin or superadmin.
  def staff_member
    return @staff_member if defined?(@staff_member_for) && @staff_member_for == active_company_id

    @staff_member_for = active_company_id
    @staff_member =
      (active_company_id && staff_members.find_by(company_id: active_company_id)) ||
      staff_members.active.order(:created_at).first ||
      staff_members.order(:created_at).first
  end

  def reload(*)
    remove_instance_variable(:@staff_member_for) if defined?(@staff_member_for)
    super
  end

  # The salles this login can switch between: every salle an admin runs, or
  # every salle a staff login is posted to and still active in.
  def workplaces
    return companies if admin?

    Company.where(id: staff_members.active.select(:company_id))
  end

  # Moves the session onto another of this login's OWN salles — never onto
  # one it does not run or work in, since that's exactly the cross-tenant
  # boundary current_company exists to enforce.
  def switch_active_company!(company)
    return false unless workplaces.exists?(company.id)

    update!(active_company: company)
  end

  # ---- what this login can do ---------------------------------------------
  # The single source of truth behind /me/permissions and /bootstrap. Every
  # company has every feature, so the admin gets every permission the
  # product exposes; staff get their assigned Role's list; a platform
  # superadmin gets none (the /superadmin surface isn't capability-gated).

  def permission_keys
    return [] if superadmin?
    return Permission::ALL if admin?

    # A deactivated post grants nothing — BaseController#capability? refuses
    # it anyway, and the menus should not promise otherwise.
    (staff_member&.active? ? staff_member.permission_keys : []) & Permission::ALL
  end

  # The role those permissions came from, as { key:, name: }. The admin's
  # stored "admin" Role row is cosmetic (its name), so new modules light up
  # for them without re-seeding.
  def role_summary
    return nil if superadmin?

    role = admin? ? current_company&.roles&.find_by(key: "admin") : staff_member&.assigned_role
    return { key: role.key, name: role.name } if role

    admin? ? { key: "admin", name: "Administrateur" } : nil
  end
end
