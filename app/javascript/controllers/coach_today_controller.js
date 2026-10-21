import { Controller } from "@hotwired/stimulus"
import { csrfToken } from "../lib/ng"
import { toast } from "../lib/toast"

// CoachTodayComponent:
//
// - another day (the arrows, "today"): its title at once, the spinner in the
//   card while the day is fetched, the roster put away; then the day — what
//   is on next and the list — as the server draws it. The day stays in the
//   URL (?date=, M-05). A failure leaves the last day's list, as the
//   Angular page leaves it;
// - a session picked: its card under the day, its spinner, then its roster
//   (a failure says so, and the roster is empty, as the Angular page shows
//   it);
// - a status tapped: that row's buttons wait, then the row comes back
//   marked.
export default class extends Controller {
  static targets = ["next", "card", "label", "body", "spinner", "sessionCard", "emptyRoster"]
  static values = { url: String, attendance: String, date: String, error: String }

  async shift({ params: { date, label } }) {
    this.dateValue = date
    this.labelTarget.textContent = label
    this.closeSession()
    const previous = [...this.bodyTarget.childNodes]
    this.bodyTarget.replaceChildren(this.spinnerTarget.content.cloneNode(true))
    history.replaceState(history.state, "", `${this.urlValue}?date=${date}`)

    const response = await fetch(`${this.urlValue}?${new URLSearchParams({ date, fragment: 1 })}`, { credentials: "same-origin" }).catch(() => null)
    if (date !== this.dateValue) return
    if (!response?.ok) return this.bodyTarget.replaceChildren(...previous)

    const fresh = document.createElement("template")
    fresh.innerHTML = await response.text()
    if (date !== this.dateValue) return
    if (this.hasNextTarget) this.nextTarget.remove()
    this.cardTarget.replaceWith(fresh.content)
  }

  async select(event) {
    const { sessionId, sessionLabel } = event.currentTarget.dataset
    this.closeSession()
    this.sessionId = sessionId
    this.element.querySelectorAll(".schedule-row").forEach((row) => row.classList.toggle("active", row.dataset.sessionId === sessionId))

    const card = this.sessionCard = this.sessionCardTemplate()
    card.querySelector("h2").textContent = sessionLabel
    const body = card.querySelector(".app-card-body")
    body.replaceChildren(this.spinnerTarget.content.cloneNode(true))
    this.cardTarget.after(card)

    const response = await fetch(`${this.attendanceValue}/${sessionId}`, { credentials: "same-origin", headers: { Accept: "text/html" } }).catch(() => null)
    if (this.sessionId !== sessionId) return
    if (!response?.ok) {
      toast("error", await this.errorOf(response))
      return body.replaceChildren(this.emptyRoster())
    }
    const fresh = document.createElement("template")
    fresh.innerHTML = await response.text()
    body.replaceChildren(fresh.content)
  }

  async mark(event) {
    const row = event.currentTarget.closest("tr")
    const buttons = [...row.querySelectorAll("button")]
    buttons.forEach((button) => (button.disabled = true))
    const response = await fetch(this.attendanceValue, {
      method: "POST",
      headers: { "Content-Type": "application/json", Accept: "text/html", "X-CSRF-Token": csrfToken() },
      credentials: "same-origin",
      body: JSON.stringify({ booking_id: row.dataset.bookingId, status: event.params.status }),
    }).catch(() => null)
    if (!response?.ok) {
      buttons.forEach((button) => (button.disabled = false))
      return toast("error", await this.errorOf(response))
    }
    const fresh = document.createElement("template")
    fresh.innerHTML = await response.text()
    row.replaceWith(fresh.content)
  }

  // ---------------------------------------------------------------------

  closeSession() {
    this.sessionId = null
    this.sessionCard?.remove()
    this.sessionCard = null
    this.element.querySelectorAll(".schedule-row.active").forEach((row) => row.classList.remove("active"))
  }

  sessionCardTemplate() {
    return this.sessionCardTarget.content.firstElementChild.cloneNode(true)
  }

  emptyRoster() {
    return this.emptyRosterTarget.content.cloneNode(true)
  }

  // extractErrorMessage: the server's own words, else the generic message.
  async errorOf(response) {
    const body = response ? await response.json().catch(() => null) : null
    return body?.error || this.errorValue
  }
}
