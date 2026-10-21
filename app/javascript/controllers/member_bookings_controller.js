import { Controller } from "@hotwired/stimulus"
import { confirmAsk } from "../lib/confirm"
import { csrfToken, interpolate } from "../lib/ng"
import { toast } from "../lib/toast"

// MemberBookingsComponent: upcoming or past — the list redrawn with its
// skeleton meanwhile (?when= in the URL, M-05), the error state when that
// fails — and giving a booking back: confirmed first, one at a time, then a
// toast and the list again.
export default class extends Controller {
  static targets = ["skeleton", "error"]
  static values = { url: String, when: String, labels: Object }

  show({ currentTarget, params: { when } }) {
    if (when === this.whenValue) return
    this.whenValue = when
    this.element.querySelectorAll(".fx-segmented button").forEach((button) => {
      button.classList.toggle("is-active", button === currentTarget)
      if (!button.classList.length) button.removeAttribute("class")
    })
    history.replaceState(history.state, "", when === "past" ? `${this.urlValue}?when=past` : this.urlValue)
    this.load()
  }

  retry() {
    this.load()
  }

  async cancel(event) {
    if (this.cancelling) return
    const { bookingId, activity } = event.currentTarget.dataset
    const confirmed = await confirmAsk({ title: this.labelsValue.confirm_title, body: interpolate(this.labelsValue.confirm_body, { activity }), danger: true })
    if (!confirmed) return

    this.cancelling = true
    this.ctas().forEach((button) => (button.disabled = true))
    const response = await fetch(`${this.urlValue}/${bookingId}/cancel`, { method: "POST", headers: { Accept: "application/json", "X-CSRF-Token": csrfToken() }, credentials: "same-origin" }).catch(() => null)
    this.cancelling = false
    if (!response?.ok) {
      this.ctas().forEach((button) => (button.disabled = false))
      const body = response ? await response.json().catch(() => null) : null
      return toast("error", body?.error || this.labelsValue.error)
    }
    toast("success", this.labelsValue.cancelled)
    this.load()
  }

  async load() {
    const when = this.whenValue
    this.region(this.skeletonTarget.content.cloneNode(true))
    const query = new URLSearchParams({ fragment: 1, ...(when === "past" ? { when } : {}) })
    const response = await fetch(`${this.urlValue}?${query}`, { credentials: "same-origin" }).catch(() => null)
    if (when !== this.whenValue) return
    if (!response?.ok) return this.region(this.errorTarget.content.cloneNode(true))
    const fresh = document.createElement("template")
    fresh.innerHTML = await response.text()
    if (when === this.whenValue) this.region(fresh.content)
  }

  // Everything under the segmented control.
  region(content) {
    let node = this.element.querySelector(".fx-segmented").nextSibling
    while (node && !(node.nodeName === "TEMPLATE")) {
      const next = node.nextSibling
      node.remove()
      node = next
    }
    this.element.querySelector(".fx-segmented").after(content)
  }

  ctas() {
    return [...this.element.querySelectorAll(".mb-slot-cta")]
  }
}
