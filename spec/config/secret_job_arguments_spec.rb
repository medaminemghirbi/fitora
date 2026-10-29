require "rails_helper"
require "sentry/test_helper"

# The raw token of a reset / invitation / confirmation link travels as a
# mail job argument (see config/initializers/action_mailer.rb and the
# before_send in sentry.rb). Neither the log nor Sentry may receive it.
RSpec.describe "Secret mail job arguments" do
  include ActiveJob::TestHelper

  let!(:user) { create(:user, :admin, email: "reset.me@example.test") }

  # Any 43-char urlsafe string in the text that hashes to the stored digest.
  def raw_token_in(text)
    digest = user.reload.reset_password_token_digest
    text.scan(/[A-Za-z0-9_-]{43}/).find { |candidate| Digest::SHA256.hexdigest(candidate) == digest }
  end

  it "keeps the raw password-reset token out of the Active Job log" do
    io = StringIO.new
    previous = ActiveJob::Base.logger
    ActiveJob::Base.logger = ActiveSupport::TaggedLogging.new(ActiveSupport::Logger.new(io)).tap { |logger| logger.level = :info }
    begin
      AccountRecovery.request_password_reset(user.email)
      perform_enqueued_jobs
    ensure
      ActiveJob::Base.logger = previous
    end

    expect(io.string).to include("Enqueued ActionMailer::MailDeliveryJob")
    expect(raw_token_in(io.string)).to be_nil
  end

  describe "a failed mail job reported to Sentry" do
    include Sentry::TestHelper

    before { setup_sentry_test }
    after { teardown_sentry_test }

    it "carries the job's class and id but not its arguments" do
      AccountRecovery.request_password_reset(user.email)
      job = enqueued_jobs.last
      payload = {
        "class" => "Sidekiq::ActiveJob::Wrapper", "wrapped" => job[:job].name, "queue" => "default",
        "jid" => "abc123", "retry" => true, "args" => [ { "job_class" => job[:job].name, "arguments" => job[:args] } ]
      }
      expect(raw_token_in(payload.to_json)).to be_present

      Sentry::Sidekiq::ErrorHandler.new.call(Net::SMTPServerBusy.new("421"), { context: "Job raised exception", job: payload })

      event = last_sentry_event
      expect(event).to be_present
      expect(event.contexts[:sidekiq]).to include("jid" => "abc123")
      expect(event.contexts[:sidekiq]).not_to have_key("args")
      expect(raw_token_in(event.to_json_compatible.to_json)).to be_nil
    end
  end
end
