# How far along first-time setup a company is: a step confirmed by hand, a
# step declined, the flow left — for /api/v1/onboarding and the web UI's
# onboarding page alike (moved unchanged from Api::V1::OnboardingController).
# Nothing else is written: the steps themselves are done on their own pages.
module OnboardingProgress
  # A step that cannot be skipped, asked to be.
  class NotSkippable < StandardError; end

  # "I have done this one." Only meaningful for a step nothing in the
  # database can confirm; for every other step the data is the answer.
  def self.complete!(company, step)
    stored = company.settings.onboarding
    save!(company, completed: stored[:completed] | [ step.key ], skipped: stored[:skipped] - [ step.key ])
  end

  # "I do not need this one."
  def self.skip!(company, step)
    raise NotSkippable, "This step cannot be skipped" unless step.skippable?

    stored = company.settings.onboarding
    save!(company, completed: stored[:completed] - [ step.key ], skipped: stored[:skipped] | [ step.key ])
  end

  # Leave the flow. The steps that remain stay remaining; this only stops
  # the app asking.
  def self.dismiss!(company)
    company.update!(setup_dismissed_at: Time.current)
  end

  def self.save!(company, completed:, skipped:)
    company.settings = { onboarding: { completed: completed, skipped: skipped } }
    company.save!
  end
  private_class_method :save!
end
