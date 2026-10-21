import { Turbo } from "@hotwired/turbo-rails"

// The top progress bar for a request the page makes itself, as
// ngx-progressbar shows it for every API call: Turbo's own bar, through the
// same adapter calls a form submission makes.
export async function withProgress(work) {
  const adapter = Turbo.session.adapter
  adapter.formSubmissionStarted?.()
  try {
    return await work()
  } finally {
    adapter.formSubmissionFinished?.()
  }
}
