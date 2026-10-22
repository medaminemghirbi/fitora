# Every night: today's exchange rates (ExchangeRate.refresh!), which convert
# the plans' prices into each gym's currency. A source that fails keeps
# yesterday's rates — prices go on converting at them — and is reported
# (Sentry, through Rails.error), so a source down for days gets noticed.
class RefreshExchangeRatesJob < ApplicationJob
  queue_as :default

  def perform
    ExchangeRate.refresh!
  rescue ExchangeRate::Unavailable => e
    Rails.error.report(e, handled: true, context: { source: ExchangeRate::SOURCE_URL })
  end
end
