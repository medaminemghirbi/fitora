import { Controller } from "@hotwired/stimulus"
import { csrfToken, downloadBlob, spinner } from "../lib/ng"
import { toast } from "../lib/toast"

// DashboardComponent's moves: the check-in dialog on a session (its panel
// fetches the roster) and, once it closes, the figures again (load(): the
// counts changed); the two occasional tasks opened and closed under their
// bar; the report downloaded under the page's own file name; the setup
// card left behind.
export default class extends Controller {
  static targets = ["exportCard", "yearField", "activityCard"]
  static values = { url: String, dismissUrl: String, labels: Object }

  connect() {
    this.open = { export: false, activity: false }
  }

  // ---- checking people in ----------------------------------------------------

  openCheckin(event) {
    this.checkinSession = event.currentTarget.dataset.sessionId
    window.dispatchEvent(new CustomEvent("dashboard-checkin:open"))
  }

  fillCheckin(event) {
    if (event.detail.name !== "dashboard-checkin") return
    const panel = event.detail.panel.querySelector("app-checkin-panel")
    // The panel's controller connects in this same pass; ask it next.
    queueMicrotask(() => this.application.getControllerForElementAndIdentifier(panel, "checkin-panel")?.load(this.checkinSession))
  }

  checkinClosed(event) {
    if (event.target.dataset?.modalNameValue !== "dashboard-checkin") return
    this.checkinSession = null
    this.load()
  }

  // load(): the body again, the tasks left open as they were.
  async load() {
    const response = await fetch(`${this.urlValue}?fragment=1`, { credentials: "same-origin", headers: { Accept: "text/html" } }).catch(() => null)
    if (!response?.ok) return
    const fresh = document.createElement("template")
    fresh.innerHTML = await response.text()
    const first = this.element.querySelector(":scope > .dash-attn")
    while (first.nextSibling) first.nextSibling.remove()
    first.replaceWith(fresh.content)
    for (const name of ["export", "activity"]) if (this.open[name]) this.showCard(name)
  }

  // ---- the occasional tasks ----------------------------------------------------

  toggle(event) {
    const name = event.currentTarget.dataset.toggle
    this.open[name] = !this.open[name]
    if (this.open[name]) this.showCard(name)
    else this.element.querySelector(`[data-card="${name}"]`)?.remove()
    this.drawToggle(name)
  }

  drawToggle(name) {
    const button = this.element.querySelector(`[data-toggle="${name}"]`)
    if (!button) return
    button.setAttribute("aria-expanded", String(this.open[name]))
    const caret = button.lastElementChild
    caret.classList.toggle("bi-chevron-down", !this.open[name])
    caret.classList.toggle("bi-chevron-up", this.open[name])
  }

  // The export card first, then the activity card, under the bar.
  showCard(name) {
    if (this.element.querySelector(`[data-card="${name}"]`)) return
    const card = this[`${name}CardTarget`].content.firstElementChild.cloneNode(true)
    const bar = this.element.querySelector(":scope > .dashboard-utility-bar")
    const exportCard = this.element.querySelector('[data-card="export"]')
    if (name === "activity" && exportCard) exportCard.after(card)
    else bar.after(card)
    this.drawToggle(name)
  }

  periodType(event) {
    const card = event.target.closest('[data-card="export"]')
    const current = card.querySelector("[data-period]")
    if (event.target.value === current.dataset.period) return
    if (event.target.value === "year") {
      this.monthField = current
      current.replaceWith(this.yearFieldTarget.content.firstElementChild.cloneNode(true))
    } else {
      current.replaceWith(this.monthField)
    }
  }

  async exportReport(event) {
    const button = event.currentTarget
    const card = button.closest('[data-card="export"]')
    const type = card.querySelector("#export-period-type").value
    const period = type === "month" ? card.querySelector("#export-month")?.value : card.querySelector("#export-year")?.value
    if (!period) return
    const content = [...button.childNodes]
    button.disabled = true
    button.replaceChildren(spinner(14, "dashboard"))
    const response = await fetch(`${this.urlValue}/report?${new URLSearchParams({ period_type: type, period })}`, { credentials: "same-origin" }).catch(() => null)
    button.disabled = false
    button.replaceChildren(...content)
    if (!response?.ok) return toast("error", this.labelsValue.error)
    downloadBlob(await response.blob(), `fitora-rapport-${period}.xlsx`)
  }

  // ---- the setup card ----------------------------------------------------------

  async dismissSetup() {
    const response = await fetch(this.dismissUrlValue, {
      method: "POST", credentials: "same-origin",
      headers: { Accept: "application/json", "X-CSRF-Token": csrfToken() },
    }).catch(() => null)
    if (response?.ok) this.element.querySelector("[data-setup-card]")?.remove()
  }
}
