import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"
import { withProgress } from "../lib/progress"

// A list the server pages and counts, re-asked whenever a filter changes —
// the shape every Angular list page with a filter rail has (load() on every
// change, the skeleton in the card while it runs, the error state with its
// retry when it fails). The server answers with Turbo Streams for the regions
// that depend on the results; what the component's computed signals redraw at
// once (chips, active tabs, "reset"…) a subclass redraws in renderFilters().
//
//   data-server-list-url-value       the page's own URL
//   data-server-list-filters-value   the filters the page was rendered with
//   data-server-list-search-key-value  which filter the search box writes ("q")
export default class extends Controller {
  static targets = ["card", "chips", "search", "loadingTemplate", "errorTemplate"]
  static values = { url: String, filters: Object, page: Number, searchKey: { type: String, default: "q" } }
  static SEARCH_DEBOUNCE_MS = 1000

  connect() {
    this.filters = { ...this.filtersValue }
    this.page = this.pageValue || 1
    this.requestId = 0
  }

  disconnect() {
    clearTimeout(this.searchTimer)
  }

  searchChanged(event) {
    this.setSearch(event.target.value)
  }

  // data-filter="status" on the control; the value from data-value or .value.
  setFilter(event) {
    const control = event.currentTarget
    this.filters[control.dataset.filter] = control.dataset.value ?? control.value
    this.reload()
  }

  // A chip's ×: its filter, cleared — the search through the search box,
  // debounced, as typing it away would.
  clearChip(event) {
    const keys = event.currentTarget.dataset.chip.split(",")
    if (keys.includes(this.searchKeyValue)) {
      if (this.hasSearchTarget) this.searchTarget.value = ""
      this.setSearch("")
      return
    }
    keys.forEach((key) => (this.filters[key] = ""))
    this.reload()
  }

  reset() {
    for (const key of Object.keys(this.filters)) if (!["sort", "direction"].includes(key)) this.filters[key] = ""
    if (this.hasSearchTarget) this.searchTarget.value = ""
    this.reload()
  }

  goToPage(event) {
    this.page = Number(event.currentTarget.dataset.page)
    this.load()
  }

  retry() {
    this.load()
  }

  // ---------------------------------------------------------------------

  setSearch(term) {
    this.filters[this.searchKeyValue] = term
    clearTimeout(this.searchTimer)
    this.searchTimer = setTimeout(() => this.reload(), this.constructor.SEARCH_DEBOUNCE_MS)
  }

  reload() {
    this.page = 1
    this.load()
  }

  async load() {
    const id = ++this.requestId
    history.replaceState(history.state, "", this.url())
    this.renderFilters()
    this.showInCard(this.loadingTemplateTarget)
    try {
      const response = await withProgress(() =>
        fetch(this.url({ stream: true }), { headers: { Accept: "text/vnd.turbo-stream.html" }, credentials: "same-origin" })
      )
      if (id !== this.requestId) return
      if (!response.ok) throw new Error(`HTTP ${response.status}`)
      Turbo.renderStreamMessage(await response.text())
    } catch {
      if (id === this.requestId) this.showInCard(this.errorTemplateTarget)
    }
  }

  // Redrawn the moment a filter changes, before the answer (subclasses).
  renderFilters() {}

  // The chips row at the top of the card: [label, the filter its × clears].
  drawChips(chips) {
    const name = this.identifier
    if (this.hasChipsTarget) this.chipsTarget.remove()
    if (!chips.length) return
    const row = document.createElement("div")
    row.className = "fx-active-filters p-3 pb-0"
    row.setAttribute(`data-${name}-target`, "chips")
    for (const [label, clear] of chips) {
      const chip = document.createElement("span")
      chip.className = "fx-active-chip"
      const button = document.createElement("button")
      button.type = "button"
      button.dataset.action = `${name}#clearChip`
      button.dataset.chip = clear
      button.setAttribute("aria-label", this.labelsValue.reset)
      const x = document.createElement("i")
      x.className = "bi bi-x"
      button.append(x)
      chip.append(` ${label} `, button)
      row.append(chip)
    }
    this.cardTarget.prepend(row)
  }

  // The "reset" button at the end of `container` (hasFilters()), marked
  // with the `marker` data attribute.
  drawReset(container, show, marker) {
    let reset = container.querySelector(`[data-${marker}]`)
    if (show && !reset) {
      reset = document.createElement("button")
      reset.type = "button"
      reset.className = "btn btn-sm btn-outline-secondary"
      reset.dataset.action = `${this.identifier}#reset`
      reset.setAttribute(`data-${marker}`, "")
      const icon = document.createElement("i")
      icon.className = "bi bi-arrow-counterclockwise"
      reset.append(icon, ` ${this.labelsValue.reset} `)
      container.append(reset)
    } else if (!show) {
      reset?.remove()
    }
  }

  // The active tab of a .fx-cat-tabs row, and the checked status pill.
  markTab(selector, value) {
    this.element.querySelectorAll(`${selector} .fx-cat-tab`).forEach((tab) => tab.classList.toggle("is-active", tab.dataset.value === (value || "")))
  }

  checkPill(name, value) {
    const pill = this.element.querySelector(`#${name}-${value || ""}`)
    if (pill) pill.checked = true
  }

  showInCard(template) {
    const card = this.cardTarget
    const chips = this.hasChipsTarget ? this.chipsTarget : null
    for (const child of [...card.children]) if (child !== chips) child.remove()
    card.append(template.content.firstElementChild.cloneNode(true))
  }

  url({ stream = false } = {}) {
    const params = new URLSearchParams()
    for (const [key, value] of Object.entries(this.filters)) if (value !== undefined && value !== null && value !== "") params.set(key, value)
    if (this.page > 1) params.set("page", String(this.page))
    const query = params.toString()
    return `${this.urlValue}${query ? `?${query}` : ""}`
  }
}
