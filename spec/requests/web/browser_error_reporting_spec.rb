require "rails_helper"

# Browser errors go to Sentry (app/javascript/lib/error_reporting.js) only
# when SENTRY_BROWSER_DSN names a project: the page carries it in a meta tag,
# which the script reads. openapi: false — not part of the API's contract.
RSpec.describe "Web browser error reporting", type: :request, openapi: false do
  around do |example|
    before = Rails.configuration.x.sentry_browser_dsn
    example.run
  ensure
    Rails.configuration.x.sentry_browser_dsn = before
  end

  it "names no DSN when none is configured" do
    Rails.configuration.x.sentry_browser_dsn = nil
    get "/connexion"
    expect(response.body).not_to include('name="sentry-dsn"')
  end

  it "hands the page the DSN and the environment when one is" do
    Rails.configuration.x.sentry_browser_dsn = "https://public@o1.ingest.sentry.io/2"
    get "/connexion"
    expect(response.body).to include('<meta name="sentry-dsn" content="https://public@o1.ingest.sentry.io/2">',
                                     '<meta name="sentry-environment" content="test">')
  end
end
