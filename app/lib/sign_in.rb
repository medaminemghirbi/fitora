# One door for both kinds of account: a platform login (admin, staff) first,
# then a member whose gym enabled their access. Shared by POST
# /api/v1/auth/login and the web UI's sign-in form, so both answer the same
# credentials the same way (MIGRATION_AUDIT §9.1).
#
# Not Fitora's superadmin: their door is /superadmin/connexion, where the
# password is followed by an authenticator app's code (TwoFactor). Here their
# right password is refused as a wrong one would be, so neither door says
# which addresses are the console's.
class SignIn
  Result = Struct.new(:user, :client, :error, keyword_init: true) do
    def success? = error.nil?
  end

  def self.call(email, password)
    email = email.to_s.downcase.strip

    user = User.active.where.not(role: :superadmin).find_by(email: email)
    return Result.new(user: user) if user&.authenticate(password)

    client = Client.active.where.not(password_digest: nil).find_by(email: email)
    if client&.authenticate(password)
      # The member app is a Pro feature. Said only after the password checked
      # out, so it tells nobody but the member which gyms exist.
      unless client.companies.includes(admin: { subscription: :invoices }).any?(&:member_app?)
        return Result.new(error: :member_app_not_included)
      end

      return Result.new(client: client)
    end

    Result.new(error: :invalid_credentials)
  end

  # The console's first factor (Web::Superadmin::SessionsController): the
  # superadmin whose password this is, or nil.
  def self.superadmin(email, password)
    user = User.active.superadmin.find_by(email: email.to_s.downcase.strip)
    user if user&.authenticate(password)
  end
end
