# Sends the "confirm your address" email again, when it may be sent: shared
# by POST /api/v1/email_verifications and the web UI's banner, so both apply
# the same cool-down and the same refusals.
#
# Returns :sent, :no_email, :already_verified, or [:too_soon, seconds].
class EmailVerificationResend
  def self.call(record)
    return :no_email if record.email.blank?
    return :already_verified if record.email_verified?

    wait = record.email_verification_resend_in
    return [ :too_soon, wait ] if wait.positive?

    raw = record.generate_email_verification_token!
    AccountMailer.email_verification(record, raw).deliver_later
    :sent
  end
end
