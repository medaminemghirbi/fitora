import { Controller } from "@hotwired/stimulus"
import { csrfToken } from "../lib/ng"
import { toast } from "../lib/toast"

// SuperadminSupportTicketsComponent: open tickets or all (?status=all,
// M-05) — the list redrawn with the spinner meanwhile, the error state when
// that fails — and a ticket in its dialog, where resolving it redraws the
// dialog and its row (an open-tickets list lets it go), with a toast.
export default class extends Controller {
  static targets = ["count", "spinner", "error"]
  static values = { url: String, filter: String, labels: Object }

  setFilter({ currentTarget, params: { filter } }) {
    if (filter === this.filterValue) return
    this.filterValue = filter
    currentTarget.parentElement.querySelectorAll("button").forEach((button) => {
      button.classList.toggle("is-active", button === currentTarget)
      if (!button.classList.length) button.removeAttribute("class")
    })
    this.load()
  }

  retry() {
    this.load()
  }

  open(event) {
    this.ticketId = event.currentTarget.dataset.ticketId
    window.dispatchEvent(new CustomEvent("support-ticket:open"))
  }

  // A phone link in a row calls, and does not open the ticket.
  stop(event) {
    event.stopPropagation()
  }

  fill(event) {
    if (event.detail.name !== "support-ticket") return
    const template = this.element.querySelector(`template[data-ticket="${this.ticketId}"]`)
    const panel = event.detail.panel
    panel.setAttribute("aria-label", template.dataset.subject)
    panel.querySelector(".modal-panel-header h3").textContent = template.dataset.subject
    this.dialogBody = panel.querySelector(".modal-panel-body")
    this.dialogBody.replaceChildren(template.content.cloneNode(true))
    this.wireResolve()
  }

  async resolve(event) {
    const button = event.currentTarget
    const id = button.dataset.resolve
    button.disabled = true
    const response = await fetch(`${this.urlValue}/${id}/resolve`, { method: "PATCH", headers: { Accept: "application/json", "X-CSRF-Token": csrfToken() }, credentials: "same-origin" }).catch(() => null)
    if (!response?.ok) {
      button.disabled = false
      const body = response ? await response.json().catch(() => null) : null
      return toast("error", body?.error || this.labelsValue.error)
    }
    const { row, detail } = await response.json()
    this.element.querySelector(`template[data-ticket="${id}"]`).innerHTML = detail
    if (this.dialogBody?.isConnected) this.dialogBody.innerHTML = detail
    const current = this.element.querySelector(`tr[data-ticket-id="${id}"]`)
    if (this.filterValue === "open") {
      current?.remove()
      this.countTarget.textContent = String(this.element.querySelectorAll("tr[data-ticket-id]").length)
    } else if (current) {
      current.outerHTML = row
    }
    toast("success", this.labelsValue.resolved)
  }

  // ---------------------------------------------------------------------

  wireResolve() {
    this.dialogBody.querySelector("[data-resolve]")?.addEventListener("click", (event) => this.resolve(event))
  }

  async load() {
    const filter = this.filterValue
    history.replaceState(history.state, "", filter === "all" ? `${this.urlValue}?status=all` : this.urlValue)
    this.region(this.spinnerTarget.content.cloneNode(true))
    const query = new URLSearchParams({ fragment: 1, ...(filter === "all" ? { status: "all" } : {}) })
    const response = await fetch(`${this.urlValue}?${query}`, { credentials: "same-origin" }).catch(() => null)
    if (filter !== this.filterValue) return
    if (!response?.ok) return this.region(this.errorTarget.content.cloneNode(true))

    const page = new DOMParser().parseFromString(await response.text(), "text/html").querySelector(".fx-page")
    this.countTarget.textContent = page.querySelector(".lst-head-count").textContent
    this.element.querySelectorAll("template[data-ticket]").forEach((t) => t.remove())
    const fresh = [...page.children].filter((child) => !child.matches(".lst-head") && !(child.tagName === "TEMPLATE" && !child.dataset.ticket))
    this.region(...fresh.map((node) => document.importNode(node, true)))
  }

  // Everything between the header and the page's own templates.
  region(...nodes) {
    const head = this.element.querySelector(".lst-head")
    while (head.nextElementSibling && !(head.nextElementSibling.tagName === "TEMPLATE" && !head.nextElementSibling.dataset.ticket)) head.nextElementSibling.remove()
    head.after(...nodes)
  }
}
