import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"
import { csrfToken } from "../lib/ng"
import { toast } from "../lib/toast"

// The till (Web::Admin::CashController): another day, the day's sheet
// printed, and this login's drawer closed — the page drawn again with the
// difference once it is.
export default class extends Controller {
  static values = { url: String, page: String, date: String, labels: Object }

  async close(event) {
    event.preventDefault()
    const form = event.currentTarget
    const response = await fetch(this.urlValue, {
      method: "POST", credentials: "same-origin",
      headers: { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": csrfToken() },
      body: JSON.stringify({ date: this.dateValue, counted_cash: form.elements.counted_cash.value, notes: form.elements.notes.value }),
    }).catch(() => null)
    if (!response?.ok) {
      const payload = await response?.json().catch(() => ({}))
      return toast("error", payload?.error ?? this.labelsValue.error)
    }
    toast("success", this.labelsValue.closed)
    Turbo.visit(`${this.pageValue}?date=${this.dateValue}`, { action: "replace" })
  }

  changeDate(event) {
    if (event.currentTarget.value) Turbo.visit(`${this.pageValue}?date=${event.currentTarget.value}`)
  }

  print() {
    window.print()
  }
}
