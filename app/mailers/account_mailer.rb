# The first real transactional mailer in the app (ApplicationMailer existed
# but nothing subclassed it yet) — password reset + email verification,
# shared by User (admin/staff — never superadmin, see
# Api::V1::PasswordResetsController) and Client.
class AccountMailer < ApplicationMailer
  # The web UI's origin — see config.x.frontend_url, the one place
  # it is decided, which production's host list reads too.
  FRONTEND_URL = Rails.configuration.x.frontend_url

  def password_reset(record, raw_token)
    @record = record
    @first_name = record.respond_to?(:first_name) ? record.first_name : nil
    @reset_url = "#{FRONTEND_URL}/auth/reset-password?token=#{raw_token}"
    @expires_in_minutes = PasswordResettable::TOKEN_EXPIRY.to_i / 60

    mail(to: record.email, subject: "Réinitialisez votre mot de passe Fitora")
  end

  def email_verification(record, raw_token)
    @record = record
    @first_name = record.respond_to?(:first_name) ? record.first_name : nil
    @verify_url = "#{FRONTEND_URL}/verify-email?token=#{raw_token}"
    @expires_in_days = EmailVerifiable::TOKEN_EXPIRY.to_i / 1.day
    # For an admin the link is what opens the account, and the mail says so.
    @opens_account = record.is_a?(User) && record.admin?

    mail(to: record.email, subject: "Confirmez votre adresse e-mail Fitora")
  end

  # The account a superadmin opened (SuperadminActions.create_company): where
  # to sign in, the login, a generated password to replace on first sign-in,
  # and, while the address is unconfirmed, the link that confirms it. Sent
  # straight away, never queued, so the password does not wait in Redis.
  def account_credentials(admin, company, password, raw_token)
    @first_name = admin.first_name
    @company_name = company.name
    @email = admin.email
    @password = password
    @sign_in_url = "#{FRONTEND_URL}/connexion"
    @verify_url = raw_token && "#{FRONTEND_URL}/verify-email?token=#{raw_token}"
    @expires_in_days = EmailVerifiable::TOKEN_EXPIRY.to_i / 1.day

    mail(to: admin.email, subject: "Votre compte Fitora pour #{company.name}")
  end

  # One admin's copy of a console mailing (AdminMailing): the variables theirs,
  # replies going to Fitora rather than to a mailbox nobody reads.
  def admin_message(recipient)
    values = AdminMailing.values_for(recipient.user)
    @body = AdminMailing.fill(recipient.mailing.body, values)
    @html_body = linked_paragraphs(@body)

    mail(to: recipient.email, reply_to: PlatformSetting.current.email.presence || "contact@fitora.io",
         subject: AdminMailing.fill(recipient.mailing.subject, values).squish)
  end

  # A gym switching on a member's own app. The member chooses their password
  # from the link; the gym never sees it.
  def member_invitation(client, company, raw_token)
    @first_name = client.first_name
    @gym_name = company.name
    @invite_url = "#{FRONTEND_URL}/auth/accept-invitation?token=#{raw_token}"
    @expires_in_days = Invitable::INVITATION_EXPIRY.to_i / 1.day

    mail(to: client.email, subject: "#{company.name} vous invite sur Fitora")
  end

  # A gym asking to add someone Fitora already knows (MembershipRequest).
  # Nothing joins until they accept from the link; ignoring it is a no.
  def membership_request(request, raw_token)
    @first_name = request.client.first_name
    @gym_name = request.company.name
    @accept_url = "#{FRONTEND_URL}/adhesion?token=#{raw_token}"
    @expires_in_days = MembershipRequest::EXPIRY.to_i / 1.day

    mail(to: request.client.email, subject: "#{request.company.name} souhaite vous compter parmi ses membres")
  end

  private

  # The text as typed, escaped, its paragraphs and web addresses made HTML.
  def linked_paragraphs(text)
    linked = ERB::Util.html_escape(text).to_str.gsub(%r{https?://(?:(?!&quot;|&#39;)[^\s<])*[^\s<.,;:!?)]}) do |url|
      %(<a href="#{url}" style="color:#4a2a8f;">#{url}</a>)
    end
    view_context.simple_format(linked, { style: "margin:0 0 14px;" }, sanitize: false)
  end
end
