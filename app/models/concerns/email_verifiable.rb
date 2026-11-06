# Shared by User (admin/staff — never superadmin) and Client.
#
# For an admin it is a gate: an account a superadmin opened confirms its
# address before anything opens (see
# Api::V1::BaseController#require_confirmed_email!), so a mistyped address
# nobody reads never ends up holding a gym. For staff and members — whose
# addresses the gym typed in — it stays informational: it lets the frontend
# show "confirm your email" and lets us trust the address for things like
# the password-reset flow itself.
module EmailVerifiable
  extend ActiveSupport::Concern

  TOKEN_EXPIRY = 3.days

  # Between two sends of the link. Long enough that a double click, or an
  # impatient third one, does not bury the inbox in identical messages.
  RESEND_COOLDOWN = 60.seconds

  class_methods do
    def find_by_email_verification_token(raw_token)
      return nil if raw_token.blank?

      record = find_by(email_verification_token_digest: Digest::SHA256.hexdigest(raw_token))
      record if record&.email_verification_token_valid?(raw_token)
    end
  end

  def email_verified?
    email_verified_at.present?
  end

  # Seconds before the link may be sent again; 0 when it may be now.
  def email_verification_resend_in
    return 0 if email_verification_sent_at.blank?

    [ (email_verification_sent_at + RESEND_COOLDOWN - Time.current).ceil, 0 ].max
  end

  def generate_email_verification_token!
    raw = SecureRandom.urlsafe_base64(32)
    update!(email_verification_token_digest: Digest::SHA256.hexdigest(raw), email_verification_sent_at: Time.current)
    raw
  end

  def email_verification_token_valid?(raw_token)
    return false if email_verification_token_digest.blank? || email_verification_sent_at.blank?
    return false if email_verification_sent_at < TOKEN_EXPIRY.ago

    ActiveSupport::SecurityUtils.secure_compare(email_verification_token_digest, Digest::SHA256.hexdigest(raw_token.to_s))
  end

  def verify_email!
    update!(email_verified_at: Time.current, email_verification_token_digest: nil, email_verification_sent_at: nil)
  end
end
