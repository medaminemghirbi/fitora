# The superadmin's second factor: the six-digit codes of an authenticator
# app (TOTP, RFC 6238 — Google Authenticator, Microsoft Authenticator,
# 1Password…), asked for after the password at /superadmin/connexion
# (Web::Superadmin::SessionsController). Set up there too, at the first
# sign-in, from a QR code.
#
# The app's secret is kept encrypted, with a key derived from
# secret_key_base: a copy of the database alone does not make the codes.
# A code is good once: the time step it was accepted for is kept, and a code
# from that step or an earlier one is refused, so one read over a shoulder
# cannot be used again in its 30 seconds.
#
# Lost phone: `bin/rails superadmin:reset_two_factor EMAIL=…` turns it off,
# and the next sign-in sets it up again.
module TwoFactor
  extend ActiveSupport::Concern

  ISSUER = "Fitora".freeze
  # The app's own step: a code is good for the 30 seconds the app shows it,
  # and no longer — the one before or after it is refused.
  INTERVAL = 30

  # A new secret, for an app being set up.
  def self.new_secret = ROTP::Base32.random

  # The step a code was made for (its start, as a Unix time) if it is the
  # app's code of this very step and newer than `after`; nil otherwise.
  def self.verify(secret, code, after: nil)
    code = code.to_s.gsub(/\s/, "")
    return nil unless code.match?(/\A\d{6}\z/)

    totp(secret).verify(code, after: after&.to_i)
  end

  # What the app reads from the QR code: the secret, and the account it is
  # for — "Fitora (admin@…)" in the app's list.
  def self.provisioning_uri(secret, email)
    totp(secret).provisioning_uri(email)
  end

  def self.totp(secret) = ROTP::TOTP.new(secret, issuer: ISSUER, interval: INTERVAL)

  def self.encryptor
    @encryptor ||= ActiveSupport::MessageEncryptor.new(
      Rails.application.key_generator.generate_key("fitora two-factor secret", ActiveSupport::MessageEncryptor.key_len)
    )
  end

  def two_factor_enabled?
    otp_enabled_at.present? && otp_secret_ciphertext.present?
  end

  # Sets the app up with this secret, if the code is the app's: the proof it
  # was scanned right, before the console relies on it.
  def enable_two_factor!(secret, code)
    step = TwoFactor.verify(secret, code) or return false

    update!(otp_secret_ciphertext: TwoFactor.encryptor.encrypt_and_sign(secret),
            otp_enabled_at: Time.current, otp_last_used_at: Time.zone.at(step))
  end

  # Whether the code is the app's, and not used before. Taken in one UPDATE
  # that only a newer step passes, so two requests racing with the same code
  # cannot both get in.
  def verify_two_factor(code)
    return false unless two_factor_enabled?

    step = TwoFactor.verify(otp_secret, code, after: otp_last_used_at) or return false
    used_at = Time.zone.at(step)
    taken = self.class.where(id: id).where("otp_last_used_at IS NULL OR otp_last_used_at < ?", used_at)
                .update_all(otp_last_used_at: used_at, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    taken == 1
  end

  def disable_two_factor!
    update!(otp_secret_ciphertext: nil, otp_enabled_at: nil, otp_last_used_at: nil)
  end

  private

  def otp_secret
    TwoFactor.encryptor.decrypt_and_verify(otp_secret_ciphertext)
  end
end
