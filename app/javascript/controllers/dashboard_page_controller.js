import { Controller } from "@hotwired/stimulus"
import { csrfToken } from "../lib/ng"

// DashboardComponent's moves: the check-in dialog on a session (its panel
// fetches the roster) and, once it closes, the figures again (load(): the
// counts changed); the recent activity opened and closed under its bar; the
// setup card left behind.
export default class extends Controller {
  static targets = ["activityCard"]
  static values = { url: String, dismissUrl: String }

  connect() {
    this.activityOpen = false
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

  // load(): the body again, the recent activity left open as it was.
  async load() {
    const response = await fetch(`${this.urlValue}?fragment=1`, { credentials: "same-origin", headers: { Accept: "text/html" } }).catch(() => null)
    if (!response?.ok) return
    const fresh = document.createElement("template")
    fresh.innerHTML = await response.text()
    const first = this.element.querySelector(":scope > .dash-attn")
    while (first.nextSibling) first.nextSibling.remove()
    first.replaceWith(fresh.content)
    if (this.activityOpen) this.showActivity()
  }

  // ---- the recent activity -----------------------------------------------------

  toggle() {
    this.activityOpen = !this.activityOpen
    if (this.activityOpen) this.showActivity()
    else this.element.querySelector('[data-card="activity"]')?.remove()
    this.drawToggle()
  }

  drawToggle() {
    const button = this.element.querySelector('[data-toggle="activity"]')
    if (!button) return
    button.setAttribute("aria-expanded", String(this.activityOpen))
    const caret = button.lastElementChild
    caret.classList.toggle("bi-chevron-down", !this.activityOpen)
    caret.classList.toggle("bi-chevron-up", this.activityOpen)
  }

  showActivity() {
    if (this.element.querySelector('[data-card="activity"]')) return
    const card = this.activityCardTarget.content.firstElementChild.cloneNode(true)
    this.element.querySelector(":scope > .dashboard-utility-bar").after(card)
    this.drawToggle()
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
