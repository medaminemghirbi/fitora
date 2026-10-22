import * as Sentry from "@sentry/browser"

// Browser errors, to Sentry — what @sentry/angular did for the Angular app.
// Only when the page names a project (SENTRY_BROWSER_DSN, the layout's
// sentry-dsn meta); otherwise nothing starts and nothing is sent. Errors only,
// no performance tracing and no personal data, as on the server
// (config/initializers/sentry.rb).
const dsn = document.querySelector('meta[name="sentry-dsn"]')?.content

if (dsn) {
  Sentry.init({
    dsn,
    environment: document.querySelector('meta[name="sentry-environment"]')?.content,
    sendDefaultPii: false,
    tracesSampleRate: 0,
  })
}
