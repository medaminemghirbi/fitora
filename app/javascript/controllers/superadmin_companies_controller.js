import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// SuperadminCompaniesComponent: the search (a second after the typing stops,
// back to the first page), the closed-access filter, the pages — each a new
// request with the spinner in the list's place meanwhile and the error state
// when it fails; the count, the filter button and the list come back from
// the server as it draws them. The filters stay in the URL (M-05). A row
// opens the gym.
export default class extends Controller {
  static targets = ["count", "toggle", "spinner", "error"]
  static values = { url: String, query: String, closed: Boolean, page: Number }

  static DEBOUNCE = 1000 // SEARCH_DEBOUNCE_MS

  disconnect() {
    clearTimeout(this.timer)
  }

  search(event) {
    this.queryValue = event.target.value
    clearTimeout(this.timer)
    this.timer = setTimeout(() => {
      this.pageValue = 1
      this.load()
    }, this.constructor.DEBOUNCE)
  }

  toggleClosed() {
    this.closedValue = !this.closedValue
    this.pageValue = 1
    this.load()
  }

  goToPage(event) {
    this.pageValue = Number(event.currentTarget.dataset.page)
    this.load()
  }

  retry() {
    this.load()
  }

  open(event) {
    Turbo.visit(event.currentTarget.dataset.href)
  }

  async load() {
    const query = new URLSearchParams()
    if (this.queryValue) query.set("q", this.queryValue)
    if (this.closedValue) query.set("closed", "1")
    if (this.pageValue > 1) query.set("page", this.pageValue)
    history.replaceState(history.state, "", query.size ? `${this.urlValue}?${query}` : this.urlValue)

    const request = (this.request = Symbol("load"))
    this.region(this.spinnerTarget.content.cloneNode(true))
    query.set("fragment", "1")
    const response = await fetch(`${this.urlValue}?${query}`, { credentials: "same-origin" }).catch(() => null)
    if (request !== this.request) return
    if (!response?.ok) return this.region(this.errorTarget.content.cloneNode(true))

    const page = new DOMParser().parseFromString(await response.text(), "text/html").querySelector(".fx-page")
    this.countTarget.textContent = page.querySelector(".lst-head-count").textContent
    const toggle = page.querySelector(".fx-toolbar > .btn")
    if (this.hasToggleTarget) this.toggleTarget.remove()
    if (toggle) this.element.querySelector(".fx-toolbar").append(document.importNode(toggle, true))
    const list = [...page.children].filter((child) => !child.matches(".lst-head, .fx-toolbar, template"))
    this.region(...list.map((node) => document.importNode(node, true)))
  }

  // Everything between the toolbar and the templates.
  region(...nodes) {
    const toolbar = this.element.querySelector(".fx-toolbar")
    while (toolbar.nextElementSibling && toolbar.nextElementSibling.tagName !== "TEMPLATE") toolbar.nextElementSibling.remove()
    toolbar.after(...nodes)
  }
}
