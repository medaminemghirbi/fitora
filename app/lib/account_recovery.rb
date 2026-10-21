# What the account screens do with an account — sign up, ask for a reset,
# choose a new password, accept a gym's invitation, confirm an address —
# shared by the API (Api::V1::{Auth,PasswordResets,Invitations,
# EmailVerifications}Controller) and the web UI's account pages, so both
# apply the same rules (MIGRATION_AUDIT §3.2).
module AccountRecovery
  # A gym opening its own account: the admin's login and nothing else. The
  # gym is named afterwards (Company.open!), which is where the trial starts.
  # Returns the user, saved or carrying its errors.
  def self.register(attributes)
    user = User.new(attributes.to_h.symbolize_keys.merge(role: :admin))
    if user.save
      raw = user.generate_email_verification_token!
      AccountMailer.email_verification(user, raw).deliver_later
    end
    user
  end

  # Mails a reset link if the address is a platform login or a member with
  # a password — and says nothing either way, so the form cannot be used to
  # find out who has an account.
  def self.request_password_reset(email)
    normalized = email.to_s.downcase.strip
    return if normalized.blank?

    record = User.active.where.not(role: :superadmin).find_by(email: normalized) ||
             Client.active.where.not(password_digest: nil).find_by(email: normalized)
    return if record.nil?

    raw = record.generate_password_reset_token!
    AccountMailer.password_reset(record, raw).deliver_later
  end

  # :invalid_token, or the record — check record.errors for a refused password.
  def self.reset_password(token, password)
    record = User.active.where.not(role: :superadmin).find_by_reset_password_token(token) ||
             Client.active.find_by_reset_password_token(token)
    return :invalid_token if record.nil?

    record.clear_password_reset_token! if record.update(password: password)
    record
  end

  # :invalid_token, or the member — check its errors for a refused password.
  def self.accept_invitation(token, password)
    client = Client.active.find_by_invitation_token(token)
    return :invalid_token if client.nil?

    client.accept_invitation!(password)
    client
  end

  # The record whose address this link confirms, now confirmed — or nil.
  def self.verify_email(token)
    record = User.where.not(role: :superadmin).find_by_email_verification_token(token) ||
             Client.find_by_email_verification_token(token)
    record&.verify_email!
    record
  end
end
