# One recipient of a console mailing (AdminMailing). A mail server that fails is
# tried again twice; after that the recipient is marked failed, by the kind of
# error only, and the mailing's page says so. A job run twice sends once.
class DeliverMailingJob < ApplicationJob
  queue_as :default

  retry_on StandardError, wait: :polynomially_longer, attempts: 3 do |job, error|
    MailingRecipient.find_by(id: job.arguments.first)&.update!(status: :failed, failure: error.class.name)
    Rails.error.report(error, handled: true, context: { mailing_recipient_id: job.arguments.first })
  end

  def perform(recipient_id)
    recipient = MailingRecipient.pending.find_by(id: recipient_id)
    return if recipient.nil?

    AccountMailer.admin_message(recipient).deliver_now
    recipient.update!(status: :sent, sent_at: Time.current)
  end
end
