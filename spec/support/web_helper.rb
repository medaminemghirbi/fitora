module WebHelper
  # Signs in through the web UI's own form, as a person would.
  # A superadmin through the console's own door: the password, then the
  # authenticator's code — the app set up beforehand, as after a first
  # sign-in.
  def web_sign_in(account, password: "password123")
    return post("/connexion", params: { email: account.email, password: password }) unless account.try(:superadmin?)

    secret = enable_two_factor(account)
    post "/superadmin/connexion", params: { email: account.email, password: password }
    post "/superadmin/connexion/code", params: { otp: ROTP::TOTP.new(secret).now }
  end

  # Sets up a superadmin's authenticator app; its secret, to make codes with.
  def enable_two_factor(user, at: 1.minute.ago)
    secret = TwoFactor.new_secret
    user.update!(otp_secret_ciphertext: TwoFactor.encryptor.encrypt_and_sign(secret), otp_enabled_at: at, otp_last_used_at: nil)
    secret
  end

  # Through Active Storage's redirects to the file itself (ServesAttachments).
  def follow_redirects!(limit: 3)
    limit.times { response.redirect? ? follow_redirect! : break }
  end

  # The members a members page lists, in order — read off the rows' links.
  def listed_client_ids(html = response.body)
    html.scan(%r{data-href="/admin/[0-9a-f-]{36}/clients/([0-9a-f-]{36})"}).flatten
  end
end

RSpec.configure do |config|
  config.include WebHelper, type: :request
end
