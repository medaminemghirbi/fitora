import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"
import { withProgress } from "../lib/progress"

// ClientsListComponent's behaviour. The filters live here, as they live in
// the component's signals, and every change asks the server for the
// regions that depend on the results (index.turbo_stream.erb) — the same
// moments the component calls load():
//
// - the search box, 1 s after the last keystroke (SEARCH_DEBOUNCE_MS);
// - a status pill, an advanced filter, a chip's ×, "reset": at once, back
//   to page 1;
// - a column header: sorts by it, or flips the direction if it already
//   sorts by it, back to page 1;
// - a page button: that page.
//
// While the request runs the table gives way to the same skeleton (or, if
// it fails, the same error state with its retry) as in Angular. The
// filters also go into the address (MIGRATION_AUDIT §10, M-05).
export default class extends Controller {
  static targets = ["search", "card", "chips", "advancedTemplate", "advancedToggle", "loadingTemplate", "errorTemplate"]
  static values = { url: String, filters: Object, page: Number, openWizard: Boolean, labels: Object }
  static SEARCH_DEBOUNCE_MS = 1000
  static FILTERS = ["search", "status", "contract_type_id", "activity_id", "gender", "joined_from", "joined_to", "sort", "direction"]

  connect() {
    this.filters = { ...this.filtersValue }
    this.page = this.pageValue || 1
    this.advanced = null
    this.requestId = 0
    if (this.openWizardValue) this.openWizard()
  }

  disconnect() {
    clearTimeout(this.searchTimer)
  }

  // ---- the controls -------------------------------------------------------

  searchChanged(event) {
    this.setSearch(event.target.value)
  }

  statusChanged(event) {
    this.filters.status = event.target.value
    this.reload()
  }

  advancedChanged(event) {
    this.filters[event.target.dataset.filter] = event.target.value
    this.reload()
  }

  toggleAdvanced() {
    if (this.advanced) {
      this.advanced.remove()
      this.advanced = null
    } else {
      this.advanced = this.advancedTemplateTarget.content.firstElementChild.cloneNode(true)
      this.syncAdvanced()
      this.element.querySelector("#cl-filters").after(this.advanced)
    }
    const toggle = this.element.querySelector(".fx-adv-toggle")
    toggle.classList.toggle("is-on", Boolean(this.advanced))
    toggle.setAttribute("aria-expanded", String(Boolean(this.advanced)))
  }

  clearFilters() {
    for (const key of ["search", "status", "contract_type_id", "activity_id", "gender", "joined_from", "joined_to"]) this.filters[key] = ""
    this.searchTarget.value = ""
    this.syncAdvanced()
    this.reload()
  }

  // A chip's ×: clears the filter it stands for — the search through the
  // search box, debounced, exactly as typing it away would.
  clearChip(event) {
    const chip = event.currentTarget.dataset.chip
    if (chip === "search") {
      this.searchTarget.value = ""
      this.setSearch("")
      return
    }
    if (chip === "joined") {
      this.filters.joined_from = ""
      this.filters.joined_to = ""
    } else {
      this.filters[chip] = ""
    }
    this.syncAdvanced()
    this.reload()
  }

  sortBy(event) {
    const column = event.currentTarget.dataset.column
    const current = this.filters.sort || "name"
    if (current === column) {
      this.filters.direction = this.filters.direction === "desc" ? "asc" : "desc"
    } else {
      this.filters.sort = column
      this.filters.direction = "asc"
    }
    this.reload()
  }

  goToPage(event) {
    this.page = Number(event.currentTarget.dataset.page)
    this.load()
  }

  retry() {
    this.load()
  }

  openClient(event) {
    if (event.target.closest("a")) return // the name's own link navigates itself
    Turbo.visit(event.currentTarget.dataset.href)
  }

  exportCsv() {
    window.location.assign(this.url({ csv: true }))
  }

  openWizard() {
    window.dispatchEvent(new CustomEvent("clients-wizard:open"))
  }

  // ---- loading -------------------------------------------------------------

  setSearch(term) {
    this.filters.search = term
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
      if (id !== this.requestId) return // a later request has been made since
      if (!response.ok) throw new Error(`HTTP ${response.status}`)
      Turbo.renderStreamMessage(await response.text())
    } catch (error) {
      if (id === this.requestId) this.showInCard(this.errorTemplateTarget)
    }
  }

  // The card keeps its chips; everything under them gives way.
  showInCard(template) {
    const card = this.cardTarget
    for (const child of [...card.children]) {
      if (child !== (this.hasChipsTarget ? this.chipsTarget : null)) child.remove()
    }
    card.append(template.content.firstElementChild.cloneNode(true))
  }

  url({ stream = false, csv = false } = {}) {
    const params = new URLSearchParams()
    for (const key of this.constructor.FILTERS) {
      const value = this.filters[key]
      if (value !== undefined && value !== null && value !== "") params.set(key, value)
    }
    if (!csv && this.page > 1) params.set("page", String(this.page))
    if (stream && this.advanced) params.set("advanced", "1")
    const query = params.toString()
    return `${this.urlValue}${csv ? ".csv" : ""}${query ? `?${query}` : ""}`
  }

  // What the component's computed signals redraw as soon as a filter
  // changes, whatever the request then does: the chips, the advanced
  // filters' count, "reset", the checked pill. The counts wait for the
  // answer, as they wait for it in Angular. Same markup as _filters and
  // _card render.
  renderFilters() {
    const labels = this.labelsValue
    const f = this.filters
    const advanced = ["contract_type_id", "activity_id", "gender", "joined_from", "joined_to"].filter((k) => f[k]).length
    const any = Boolean(f.search) || Boolean(f.status) || advanced > 0

    const pill = this.element.querySelector(`#client-status-${f.status || ""}`)
    if (pill) pill.checked = true

    const toggle = this.element.querySelector(".fx-adv-toggle")
    let badge = toggle.querySelector(".fx-adv-count")
    if (advanced > 0) {
      if (!badge) {
        badge = document.createElement("span")
        badge.className = "fx-adv-count"
        toggle.append(badge)
      }
      badge.textContent = String(advanced)
    } else {
      badge?.remove()
    }

    let reset = this.element.querySelector('[data-action="clients-list#clearFilters"]')
    if (any && !reset) {
      reset = document.createElement("button")
      reset.type = "button"
      reset.className = "btn btn-sm btn-outline-secondary"
      reset.dataset.action = "clients-list#clearFilters"
      const icon = document.createElement("i")
      icon.className = "bi bi-arrow-counterclockwise"
      reset.append(icon, ` ${labels.reset} `)
      toggle.after(reset)
    } else if (!any) {
      reset?.remove()
    }

    const chips = []
    if (f.search) chips.push([`« ${f.search} »`, "search"])
    if (labels.statuses[f.status]) chips.push([labels.statuses[f.status], "status"])
    if (labels.plans[f.contract_type_id]) chips.push([labels.plans[f.contract_type_id], "contract_type_id"])
    if (labels.activities[f.activity_id]) chips.push([labels.activities[f.activity_id], "activity_id"])
    if (f.gender) chips.push([labels.genders[f.gender] ?? f.gender, "gender"])
    if (f.joined_from || f.joined_to) chips.push([`${labels.member_since} ${f.joined_from || "…"} → ${f.joined_to || "…"}`, "joined"])

    if (this.hasChipsTarget) this.chipsTarget.remove()
    if (chips.length > 0) {
      const row = document.createElement("div")
      row.className = "fx-active-filters p-3 pb-0"
      row.dataset.clientsListTarget = "chips"
      for (const [label, clear] of chips) {
        const chip = document.createElement("span")
        chip.className = "fx-active-chip"
        const button = document.createElement("button")
        button.type = "button"
        button.dataset.action = "clients-list#clearChip"
        button.dataset.chip = clear
        button.setAttribute("aria-label", labels.reset)
        const icon = document.createElement("i")
        icon.className = "bi bi-x"
        button.append(icon)
        chip.append(` ${label} `, button)
        row.append(chip)
      }
      this.cardTarget.prepend(row)
    }
  }

  // The advanced fields show the filters' current values ([value] bindings).
  syncAdvanced() {
    if (!this.advanced) return
    for (const field of this.advanced.querySelectorAll("[data-filter]")) {
      field.value = this.filters[field.dataset.filter] ?? ""
    }
  }
}
