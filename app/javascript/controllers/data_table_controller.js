import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// A superadmin console table (Web::DataTable, web/superadmin/shared/_table):
// the search runs as the typing pauses, a filter or a page size as it is
// picked, each from the first page. Only the table's frame comes back from
// the server, and the URL says what is shown — without the fields left at
// their default — so the page can be reloaded, shared or gone back to. The
// "clear" link shows while anything narrows the table. A row opens what it
// describes, unless the click was on a link or a control inside it.
export default class extends Controller {
  static targets = ["form", "frame", "clear"]

  static DEBOUNCE = 300

  disconnect() {
    clearTimeout(this.timer)
  }

  search() {
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.load(), this.constructor.DEBOUNCE)
  }

  submit(event) {
    event?.preventDefault()
    clearTimeout(this.timer)
    this.load()
  }

  open(event) {
    if (event.target.closest("a, button, input, select, label")) return
    if (window.getSelection()?.toString()) return
    const href = event.currentTarget.dataset.href
    if (event.metaKey || event.ctrlKey) return window.open(href, "_blank", "noopener")
    Turbo.visit(href)
  }

  load() {
    const query = new URLSearchParams()
    for (const field of this.formTarget.elements) {
      if (!field.name || field.disabled) continue
      const value = field.value.trim()
      if (value !== "" && value !== field.dataset.default) query.set(field.name, value)
    }
    this.toggleClear(query)
    const url = query.size ? `${this.formTarget.action}?${query}` : this.formTarget.action
    Turbo.visit(url, { frame: this.frameTarget.id, action: "advance" })
  }

  // ---------------------------------------------------------------------

  // The sort and the page size do not narrow anything.
  toggleClear(query) {
    if (!this.hasClearTarget) return
    this.clearTarget.hidden = ![...query.keys()].some((name) => !["sort", "dir", "limit"].includes(name))
  }
}
