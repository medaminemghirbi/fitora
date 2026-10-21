import { Controller } from "@hotwired/stimulus"
import { csrfToken } from "../lib/ng"
import { toast } from "../lib/toast"

// MemberScheduleComponent#book: one booking at a time — every button waits
// while it is out — then the row says "booked" (redrawn by the server, with
// the room now left) and a toast; a refusal is a toast with the server's
// words.
export default class extends Controller {
  static values = { url: String, labels: Object }

  async book(event) {
    if (this.booking) return
    const row = event.currentTarget.closest(".mb-slot")
    this.booking = row.dataset.sessionId
    this.buttons().forEach((button) => (button.disabled = true))

    const response = await fetch(this.urlValue, {
      method: "POST",
      headers: { "Content-Type": "application/json", Accept: "text/html", "X-CSRF-Token": csrfToken() },
      credentials: "same-origin",
      body: JSON.stringify({ session_id: this.booking }),
    }).catch(() => null)
    this.booking = null

    if (response?.ok) {
      const fresh = document.createElement("template")
      fresh.innerHTML = await response.text()
      row.replaceWith(fresh.content)
      toast("success", this.labelsValue.booked)
    } else {
      const body = response ? await response.json().catch(() => null) : null
      toast("error", body?.error || this.labelsValue.error)
    }
    this.buttons().forEach((button) => (button.disabled = button.dataset.full === "true"))
  }

  buttons() {
    return [...this.element.querySelectorAll(".mb-slot-cta")]
  }
}
