# Account mails carry the raw token of their link — a password reset, an
# invitation, an address confirmation — as a job argument
# (AccountMailer.password_reset(user, raw).deliver_later), and Active Job
# writes every argument into its "Enqueued …" / "Performing …" lines at
# info, production's level. filter_parameters never sees positional job
# arguments, so anyone reading the logs could finish someone's reset. The
# mail job is the only one handed a secret; other jobs keep their arguments
# in the log. (Sentry gets the same treatment in sentry.rb.)
Rails.application.config.after_initialize do
  ActionMailer::MailDeliveryJob.log_arguments = false
end
