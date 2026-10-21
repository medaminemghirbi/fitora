import { Controller } from "@hotwired/stimulus"
import { csrfToken } from "../lib/ng"
import { highlight } from "../lib/highlight"
import { toast } from "../lib/toast"

// CheckinPanelComponent: the session's roster, fetched when the panel is
// given a session (load, or `session` from the start), narrowed by name, one tap per person — the row
// busy while its mark is written, every button waiting, nothing sent when
// the tap repeats the status the person has. Says checkin-panel:marked.
export default class extends Controller {
  static values = { url: String, labels: Object, session: String }

  // A page that knows its session already (the desk) loads it at once.
  connect() {
    if (this.sessionValue) this.load(this.sessionValue)
  }

  async load(sessionId) {
    this.sessionId = sessionId
    const response = await fetch(`${this.urlValue}/${sessionId}`, { credentials: "same-origin", headers: { Accept: "text/html" } }).catch(() => null)
    if (!response?.ok) return this.showError()
    const fresh = document.createElement("template")
    fresh.innerHTML = await response.text()
    this.element.replaceChildren(fresh.content)
    this.rows = [...this.element.querySelectorAll(".ckin-row")]
    this.list = this.element.querySelector(".ckin-list")
    this.term = ""
  }

  // ErrorStateComponent with its retry.
  showError() {
    const template = document.querySelector("template[data-checkin-error]")
    if (!template) return
    this.element.replaceChildren(template.content.cloneNode(true))
    this.element.querySelector(".fx-state button")?.addEventListener("click", () => this.load(this.sessionId))
  }

  search(event) {
    this.term = event.target.value
    const needle = this.term.trim().toLowerCase()
    const shown = needle ? this.rows.filter((row) => row.dataset.name.toLowerCase().includes(needle)) : this.rows
    for (const row of this.rows) {
      const name = row.querySelector("[data-highlight]")
      name.innerHTML = highlight(name.dataset.highlight, this.term)
    }
    const empty = this.element.querySelector(":scope > app-empty-state")
    if (shown.length === 0) {
      this.list.remove()
      if (!empty) this.element.append(this.element.querySelector("template[data-checkin-no-results]").content.cloneNode(true))
      return
    }
    empty?.remove()
    this.list.replaceChildren(...shown)
    if (!this.list.isConnected) this.element.querySelector(".ckin-head").after(this.list)
  }

  async mark(event) {
    const button = event.currentTarget
    const row = button.closest(".ckin-row")
    const status = button.dataset.status
    if (row.dataset.status === status || this.marking) return
    this.marking = true
    row.classList.add("is-busy")
    this.rows.forEach((r) => r.querySelectorAll(".ckin-btn").forEach((b) => (b.disabled = true)))
    const response = await fetch(this.urlValue, {
      method: "POST", credentials: "same-origin",
      headers: { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": csrfToken() },
      body: JSON.stringify({ booking_id: row.dataset.bookingId, status }),
    }).catch(() => null)
    const payload = await response?.json().catch(() => ({}))
    this.marking = false
    row.classList.remove("is-busy")
    this.rows.forEach((r) => r.querySelectorAll(".ckin-btn").forEach((b) => (b.disabled = false)))
    if (!response?.ok) return toast("error", payload?.error ?? this.labelsValue.error)

    row.dataset.status = payload.attendance.attendance?.status ?? ""
    row.querySelectorAll(".ckin-btn").forEach((b) => b.classList.toggle("is-on", b.dataset.status === row.dataset.status))
    const present = this.rows.filter((r) => r.dataset.status === "present").length
    this.element.querySelector("[data-count]").textContent = `${present}/${this.rows.length}`
    this.dispatch("marked")
  }
}
